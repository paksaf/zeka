import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import '../services/auth_service.dart';
import '../services/deepseek_service.dart';
import '../services/language_service.dart';
import '../services/user_storage.dart';
import '../theme.dart';
import 'handwriting_pad.dart';

/// The voice-first conversation surface. Opens as a bottom sheet from
/// the home screen. Flow:
///   1. Mic immediately activates and listens (or user taps mic if
///      they prefer to read the cue first).
///   2. Live transcription streams into the text box — user can edit
///      before submitting.
///   3. Alternative inputs: camera (photo OCR), handwriting pad
///      (write the problem with finger / Apple Pencil / mouse).
///   4. Submit → AI returns steps + answer → TTS speaks it back in
///      the user's language.
///
/// All four input modes share the same TextField so the user can
/// freely switch — speak something, edit it, snap a photo to add
/// context, then send.
class SpeakSheet extends ConsumerStatefulWidget {
  final bool autoListen;
  const SpeakSheet({super.key, this.autoListen = true});
  @override
  ConsumerState<SpeakSheet> createState() => _SpeakSheetState();
}

class _SpeakSheetState extends ConsumerState<SpeakSheet> {
  final _service = DeepSeekService();
  final _controller = TextEditingController();
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();
  // Focus nodes for D-pad / TV navigation. Without these the remote
  // can't escape the multi-line TextField (same trap we hit on the
  // login screen).
  final _inputFocus = FocusNode();
  final _solveFocus = FocusNode();
  bool _listening = false;
  bool _busy = false;
  AiResult? _result;
  String? _error;
  XFile? _image;

  @override
  void initState() {
    super.initState();
    // Don't call _stt.initialize() here without a callback chain — on
    // some devices it errors silently and the mic just doesn't work.
    // _toggleListening calls initialize() with proper error + status
    // callbacks already, so we let the user trigger it via tap.
    if (widget.autoListen) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _toggleListening());
    }

    // TV-remote D-pad escape from the multi-line TextField. Flutter's
    // default behaviour treats arrowDown / arrowRight inside a
    // multi-line field as cursor movement — they never bubble up to
    // the FocusScope. We intercept here and forward to the Solve
    // button so the user can finish typing → press D-pad down → press
    // OK on Solve. Tab and Enter on a USB keyboard also work.
    _inputFocus.onKeyEvent = (FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.tab) {
        FocusScope.of(context).requestFocus(_solveFocus);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        // Back up to the mic — leaves the TextField cleanly so the
        // user can re-record without dismissing the soft keyboard
        // (TV usually has no soft keyboard anyway).
        node.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    // Release the mic + TTS engine cleanly when the sheet closes.
    // Without this, dismissing the sheet mid-recording leaves the
    // recogniser running invisibly until the OS reclaims the audio
    // stream — battery drain + privacy concern.
    () async {
      try {
        await _stt.cancel();
      } catch (_) {/* non-fatal */}
      try {
        await _tts.stop();
      } catch (_) {/* non-fatal */}
    }();
    _controller.dispose();
    _inputFocus.dispose();
    _solveFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    final lang = ref.read(languageProvider);
    if (_listening) {
      // Manual stop — always allow user to tap the mic to cancel.
      try {
        await _stt.stop();
      } catch (_) {/* non-fatal */}
      if (mounted) setState(() => _listening = false);
      return;
    }
    // Runtime mic permission. Manifest declares RECORD_AUDIO but
    // Android 6+ needs explicit user grant.
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      if (mic.isPermanentlyDenied) {
        // User tapped "Don't allow" twice (or "Don't ask again").
        // The only path now is the system Settings page. Offer to
        // open it directly.
        setState(() => _error =
            'Microphone permission is blocked. Tap the mic again to open Settings.');
        // Second tap → bring up the app settings page.
        await openAppSettings();
      } else {
        setState(() => _error =
            'Microphone permission is needed. Tap "Allow" when prompted.');
      }
      return;
    }

    // Initialize — register error + status callbacks that flip the
    // listening flag back to false. Without these the mic icon stays
    // "recording" forever after the recogniser auto-stops.
    bool ok = false;
    try {
      ok = await _stt.initialize(
        onError: (e) {
          debugPrint('[stt] error: ${e.errorMsg} permanent=${e.permanent}');
          if (mounted) {
            setState(() {
              _error = _friendlySttError(e.errorMsg);
              _listening = false;
            });
          }
        },
        onStatus: (s) {
          debugPrint('[stt] status: $s');
          // v7 statuses: 'listening' | 'notListening' | 'done'
          if (s == 'notListening' || s == 'done') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
    } catch (e) {
      setState(() => _error = 'Voice unavailable on this device: $e');
      return;
    }
    if (!ok) {
      setState(() => _error =
          'Speech recogniser not available. Install the Google app and check microphone permission in Android Settings.');
      return;
    }

    // Locale fallback — many devices don't have the Urdu/Arabic/etc.
    // offline pack installed; the recogniser silently returns no
    // results. Probe the available locales and fall back to en-US so
    // SOMETHING transcribes. If the user is speaking Urdu but only
    // en-US is available, the recogniser will keep firing
    // error_no_match — surface that hint.
    String useLocale = lang.speechLocale;
    try {
      final locales = await _stt.locales();
      final hasWanted =
          locales.any((l) => l.localeId == lang.speechLocale);
      if (!hasWanted) {
        debugPrint(
            '[stt] locale ${lang.speechLocale} not installed, falling back to en-US');
        useLocale = 'en-US';
        if (lang.speechLocale != 'en-US') {
          // Brief hint — surfaces ONCE per session at the bottom of
          // the sheet so user knows why their Urdu/Arabic speech
          // isn't transcribing.
          _error =
              '${lang.englishName} voice pack isn\'t installed — '
              'using English. Speak in English, or install the pack '
              'in Settings → Voice typing → Offline speech.';
        }
      }
    } catch (_) {/* probe optional */}

    setState(() {
      _listening = true;
      _error = null;
      // Reset previous transcription so the new attempt starts clean.
      _controller.clear();
    });

    try {
      await _stt.listen(
        onResult: (r) {
          if (mounted) {
            setState(() => _controller.text = r.recognizedWords);
          }
        },
        localeId: useLocale,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          // dictation > confirmation for math/conversion questions —
          // the user is likely speaking a longer phrase than a single
          // command, and dictation keeps the mic open across short
          // pauses ("what is..." [pause] "fifty marla in...").
          listenMode: stt.ListenMode.dictation,
          // Auto-punctuation pollutes math expressions ("2, plus, 3.")
          // so we disable it. The AI proxy handles natural language
          // fine without commas.
          autoPunctuation: false,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = 'Could not start listening: $e';
        });
      }
      return;
    }

    // Watchdog — if the onStatus callback never fires "notListening"
    // (which happens on some Android builds when the recogniser fails
    // partway), force-stop after 35 s so the mic icon doesn't get
    // stuck in the recording state forever.
    Future.delayed(const Duration(seconds: 35), () async {
      if (mounted && _listening) {
        debugPrint('[stt] watchdog firing — force-stopping listener');
        try {
          await _stt.stop();
        } catch (_) {/* non-fatal */}
        if (mounted) setState(() => _listening = false);
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // 2048px @ q85 is the sweet spot for dense document OCR
      // (PDF screenshots, textbook pages). Earlier 1600px @ q80 was
      // blurring small text below the vision-LLM recognition floor —
      // user reported "We couldn't find readable text" on a clear PDF.
      // 2048px JPEG is typically 1-2 MB, well under the 10 MB cap.
      final x = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (x != null) setState(() => _image = x);
    } catch (e) {
      setState(() => _error =
          'Could not open ${source == ImageSource.camera ? "camera" : "gallery"}: $e');
    }
  }

  Future<void> _openHandwriting() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const HandwritingPad()),
    );
    if (text != null && text.isNotEmpty) {
      setState(() {
        _controller.text = _controller.text.isEmpty ? text : '${_controller.text} $text';
      });
    }
  }

  Future<void> _solve() async {
    // Stop the mic before sending — otherwise the recogniser keeps
    // capturing while the AI request is in flight and the next
    // utterance overwrites the question the user already submitted.
    if (_listening) {
      try {
        await _stt.stop();
      } catch (_) {/* non-fatal */}
      if (mounted) setState(() => _listening = false);
    }
    final q = _controller.text.trim();
    if (q.isEmpty && _image == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      List<int>? bytes;
      if (_image != null) bytes = await File(_image!.path).readAsBytes();
      final res = await _service.ask(
        q.isNotEmpty ? q : 'Solve the problem in this image. Show working step by step.',
        imageBytes: bytes,
        // Detect MIME from the picker's path extension. Hardcoding
        // image/jpeg was rejecting PNG screenshots and confusing the
        // vision LLM into treating them as malformed JPEGs.
        imageMime: _image == null ? null : _mimeFor(_image!.path),
      );
      setState(() {
        _result = res;
        _busy = false;
      });
      // Don't auto-speak — the result block has a 🔊 button next to
      // the answer. Auto-playing was startling on phone speakers and
      // useless on Android TV (no TTS engine), per user feedback.
      // Log to per-user scratchpad so the AI Q&A shows up in history.
      // Fire-and-forget — UserStorage handles the size cap.
      final session = ref.read(authProvider);
      UserStorage.instance.save(
        userId: storageUserKey(session),
        kind: 'ai',
        title: q.isEmpty ? '(image) ${res.answer}' : '$q → ${res.answer}',
        payload: {
          'question': q,
          'answer': res.answer,
          'steps': res.steps,
          'provider': res.provider,
          'hadImage': _image != null,
        },
      );
    } on AiUnconfiguredException catch (e) {
      setState(() {
        _error = e.message.isNotEmpty
            ? e.message
            : tr(context, ref, 'aiNotConfigured');
        _busy = false;
      });
    } on AiNoTextException {
      setState(() {
        _error =
            "We couldn't find readable text or numbers in the image. Try a clearer photo.";
        _busy = false;
      });
    } on AiUnsupportedException {
      setState(() {
        _error =
            "Zeka covers maths, science, and engineering. Try rephrasing "
            "as a calculation, concept (\"what is …\"), or formula (\"explain …\").";
        _busy = false;
      });
    } on AiHttpException catch (e) {
      setState(() {
        _error = e.status == 503
            ? "AI service temporarily unavailable. Please try again in a moment."
            : (e.status == 429
                ? "Too many requests — wait a moment and try again."
                : "Server returned ${e.status}. Please try again.");
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error =
            "Couldn't reach Zeka AI. Check your connection and try again.";
        _busy = false;
      });
    }
  }

  /// Map a local file path to an image MIME type by extension. Used
  /// when sending camera/gallery picks to the AI proxy — the server
  /// rejects anything not in the allowed set, and PNG-vs-JPEG matters
  /// for the vision LLM's image decoder.
  String _mimeFor(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        // Most servers + LLMs don't understand HEIC. ImagePicker on
        // iOS converts to JPEG when imageQuality is set, so this is
        // a defensive fallback — claim JPEG and let the bytes speak.
        return 'image/jpeg';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Translate the raw Android speech recogniser error codes into
  /// something an end-user can act on. Without this, the UI shows
  /// cryptic strings like "Speech error: error_no_match." and the
  /// user has no idea why their speech didn't transcribe.
  String _friendlySttError(String code) {
    switch (code.toLowerCase()) {
      case 'error_no_match':
      case 'error_speech_timeout':
        // The mic captured audio but the recogniser couldn't make out
        // words. Usually: speech too quiet, background noise, or the
        // language pack doesn't match what the user actually said
        // (e.g. speaking Urdu while only en-US is installed).
        return "Couldn't catch that. Speak a bit louder and clearer, "
            "or check the language matches in Settings → Voice typing → "
            "Offline speech recognition.";
      case 'error_network':
      case 'error_network_timeout':
        return "Voice recognition needs a network connection (or an "
            "installed offline language pack). Check your connection "
            "and try again.";
      case 'error_audio':
        return "Microphone issue. Make sure no other app (call, "
            "recorder, video) is using the mic.";
      case 'error_recognizer_busy':
        return "Voice recogniser is busy. Wait a second and try again.";
      case 'error_insufficient_permissions':
        return "Microphone permission was revoked. Enable it in "
            "Settings → Apps → Zeka → Permissions.";
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        return "This language isn't installed for voice recognition. "
            "Open Settings → System → Languages → Voice typing → "
            "Offline speech recognition to download a language pack.";
      case 'error_client':
        return "Voice service hiccup. Try tapping the mic again.";
      case 'error_server':
        return "Google's speech server is down. Try again in a moment.";
      default:
        return "Voice error ($code). Tap the mic and try again.";
    }
  }

  Future<void> _speak(String text) async {
    // TTS isn't installed on most Android TV builds, and missing
    // language packs throw a MissingPluginException on flutter_tts.
    // Failing to speak shouldn't break the rest of the AI flow.
    try {
      final lang = ref.read(languageProvider);
      await _tts.setLanguage(lang.speechLocale);
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS not available, skipping: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Drag handle + Close button row. The drag handle
                // alone isn't reachable by a TV remote — adding an
                // explicit X button so the user can always escape the
                // sheet with the D-pad.
                Padding(
                  padding: const EdgeInsets.only(
                      left: 8, right: 8, top: 4, bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 40),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: ZekaColors.muted),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _MicHero(listening: _listening, onTap: _toggleListening),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _controller,
                        focusNode: _inputFocus,
                        // Switch from multi-line to single-line for TV
                        // friendliness — multi-line TextFields can trap
                        // D-pad navigation. The text wraps visually
                        // regardless, and most questions fit in one
                        // line anyway.
                        maxLines: 4,
                        minLines: 1,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          // OK / Enter on the remote → if the text is
                          // long enough to be a question, solve it;
                          // otherwise hop focus to the Solve button so
                          // the user can press OK again to send.
                          if (_controller.text.trim().length >= 3 && !_busy) {
                            _solve();
                          } else {
                            FocusScope.of(context).requestFocus(_solveFocus);
                          }
                        },
                        style: const TextStyle(
                            color: ZekaColors.text, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: tr(context, ref, 'voiceHint'),
                          hintStyle: const TextStyle(
                              color: ZekaColors.muted, fontSize: 14),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: Colors.white12)),
                        ),
                      ),
                      if (_image != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ZekaColors.cyan.withOpacity(0.06),
                            border: Border.all(color: ZekaColors.cyan.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(File(_image!.path),
                                    width: 48, height: 48, fit: BoxFit.cover),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text('Image attached',
                                    style: TextStyle(color: ZekaColors.text, fontSize: 12)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18, color: ZekaColors.muted),
                                onPressed: () => setState(() => _image = null),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Input mode strip
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _ModeBtn(
                              icon: Icons.photo_camera,
                              label: 'Camera',
                              onTap: () => _pickImage(ImageSource.camera)),
                          _ModeBtn(
                              icon: Icons.image_outlined,
                              label: 'Photo',
                              onTap: () => _pickImage(ImageSource.gallery)),
                          _ModeBtn(
                              icon: Icons.edit,
                              label: 'Write',
                              onTap: _openHandwriting),
                          FilledButton.icon(
                            focusNode: _solveFocus,
                            // canRequestFocus stays true so D-pad
                            // can land on Solve even when the button
                            // is technically idle. autofocus=false
                            // because we don't want it stealing focus
                            // from the TextField at open time.
                            autofocus: false,
                            onPressed: _busy ? null : _solve,
                            icon: _busy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.auto_awesome),
                            label: Text(_busy
                                ? tr(context, ref, 'thinking')
                                : tr(context, ref, 'solve')),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: 20),
                        ..._result!.steps.map((s) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(s,
                                  style: const TextStyle(
                                      color: ZekaColors.muted,
                                      fontFamily: 'monospace',
                                      fontSize: 13)),
                            )),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: ZekaColors.cyan.withOpacity(0.08),
                            border: Border.all(color: ZekaColors.cyan.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('= ${_result!.answer}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      color: ZekaColors.cyan,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    )),
                              ),
                              IconButton(
                                icon: const Icon(Icons.volume_up, color: ZekaColors.cyan),
                                onPressed: () => _speak(_result!.answer),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('via ${_result!.provider}',
                            style: const TextStyle(color: ZekaColors.muted, fontSize: 10)),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MicHero extends StatelessWidget {
  final bool listening;
  final VoidCallback onTap;
  const _MicHero({required this.listening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: listening
                ? const LinearGradient(colors: [Colors.red, Colors.deepOrange])
                : const LinearGradient(colors: [ZekaColors.purple, ZekaColors.cyan]),
            boxShadow: listening
                ? [
                    BoxShadow(
                        color: Colors.red.withOpacity(0.5), blurRadius: 20, spreadRadius: 6),
                  ]
                : [
                    BoxShadow(
                        color: ZekaColors.purple.withOpacity(0.4), blurRadius: 14, spreadRadius: 2),
                  ],
          ),
          child: Icon(
            listening ? Icons.stop : Icons.mic,
            color: Colors.white,
            size: 38,
          ),
        ),
      ),
    );
  }
}

class _ModeBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ModeBtn(
      {required this.icon, required this.label, required this.onTap});
  @override
  State<_ModeBtn> createState() => _ModeBtnState();
}

class _ModeBtnState extends State<_ModeBtn> {
  bool _focused = false;

  // Same shortcut bindings as the home _FocusableTile so the TV remote
  // can activate Camera / Photo / Write with the D-pad center button.
  static final _activateShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (f) {
        if (mounted) setState(() => _focused = f);
      },
      shortcuts: _activateShortcuts,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _focused
                ? ZekaColors.cyan.withOpacity(0.18)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? ZekaColors.cyan : Colors.white12,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: ZekaColors.cyan, size: 20),
              const SizedBox(height: 2),
              Text(widget.label,
                  style: const TextStyle(
                      color: ZekaColors.text, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
