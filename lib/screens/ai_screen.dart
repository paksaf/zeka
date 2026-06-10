import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import '../services/deepseek_service.dart';
import '../services/language_service.dart';
import '../theme.dart';
import '../widgets/zeka_brand_header.dart';

class AIScreen extends ConsumerStatefulWidget {
  const AIScreen({super.key});
  @override
  ConsumerState<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends ConsumerState<AIScreen> {
  final _service = DeepSeekService();
  final _controller = TextEditingController();
  final _stt = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _listening = false;
  bool _loading = false;
  AiResult? _result;
  String? _error;
  XFile? _image;

  @override
  void initState() {
    super.initState();
    _stt.initialize();
  }

  Future<void> _toggleListening() async {
    final lang = ref.read(languageProvider);
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _stt.initialize();
    if (!ok) return;
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (r) {
        setState(() {
          _controller.text = r.recognizedWords;
        });
      },
      localeId: lang == ZekaLang.ur ? 'ur-PK' : 'en-US',
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 85);
    if (xfile != null) setState(() => _image = xfile);
  }

  Future<void> _solve() async {
    final q = _controller.text.trim();
    if (q.isEmpty && _image == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      List<int>? bytes;
      if (_image != null) bytes = await File(_image!.path).readAsBytes();
      final res = await _service.ask(
        q.isNotEmpty ? q : 'Solve the problem shown in this image. Show working step by step.',
        imageBytes: bytes,
        imageMime: _image == null ? null : 'image/jpeg',
      );
      setState(() {
        _result = res;
        _loading = false;
      });
      _speak(res.answer);
    } on AiUnconfiguredException {
      setState(() {
        _error = tr(context, ref, 'aiNotConfigured');
        _loading = false;
      });
    } on AiNoTextException {
      setState(() {
        _error = tr(context, ref, 'noTextInImage');
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    final lang = ref.read(languageProvider);
    await _tts.setLanguage(lang == ZekaLang.ur ? 'ur-PK' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(child: ZekaBrandHeader(compact: true)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(tr(context, ref, 'askZeka').toUpperCase(),
                    style: const TextStyle(color: ZekaColors.muted, letterSpacing: 2, fontSize: 10)),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLines: 5,
                  minLines: 3,
                  textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(color: ZekaColors.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: lang == ZekaLang.ur
                        ? 'مثلاً: 5 من گندم کلوگرام میں کتنی ہو گی؟'
                        : 'e.g. 5 maund of wheat to kg',
                    hintStyle: const TextStyle(color: ZekaColors.muted),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
                if (_image != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
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
                            child: Image.file(File(_image!.path), width: 56, height: 56, fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Image attached — Zeka will read and solve.',
                                style: TextStyle(color: ZekaColors.text, fontSize: 12)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: ZekaColors.muted),
                            onPressed: () => setState(() => _image = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(_listening ? Icons.stop_circle : Icons.mic_none,
                          color: _listening ? Colors.red : ZekaColors.purple, size: 30),
                      onPressed: _toggleListening,
                      tooltip: tr(context, ref, 'voiceHint'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.photo_camera, color: ZekaColors.purple, size: 28),
                      onPressed: () => _pickImage(ImageSource.camera),
                      tooltip: tr(context, ref, 'cameraHint'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.attach_file, color: ZekaColors.purple, size: 28),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _loading ? null : _solve,
                      icon: _loading
                          ? const SizedBox(
                              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome),
                      label: Text(_loading ? tr(context, ref, 'thinking') : tr(context, ref, 'solve')),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ),
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  ..._result!.steps.map((s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(s,
                            style: const TextStyle(color: ZekaColors.muted, fontFamily: 'monospace', fontSize: 13)),
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
                  const SizedBox(height: 6),
                  Text('via ${_result!.provider}',
                      style: const TextStyle(color: ZekaColors.muted, fontSize: 10)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
