import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../theme.dart';
import '../widgets/zeka_brand_header.dart';

/// First-launch sign-in. Two paths:
///   1. Email OR phone → 6-digit code (uses the existing INTERACT
///      Comms Hub, so users get the same magic-link experience as
///      qurbanisahulat / farmer / cgt.llc).
///   2. Skip → "use anonymously" — calculator + converter still work
///      fully without an account. AI still works but history won't
///      sync across devices.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _identCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  // Focus nodes for D-pad navigation on Android TV. Without these the
  // remote can't move off the email TextField — IME's Done/Next has
  // nowhere to go and the user is trapped.
  final _identFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _sendBtnFocus = FocusNode();
  final _verifyBtnFocus = FocusNode();
  bool _isEmail = true; // toggle email <-> phone
  bool _codeStage = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identCtrl.dispose();
    _codeCtrl.dispose();
    _identFocus.dispose();
    _codeFocus.dispose();
    _sendBtnFocus.dispose();
    _verifyBtnFocus.dispose();
    super.dispose();
  }

  bool get _identValid {
    final v = _identCtrl.text.trim();
    if (_isEmail) return v.contains('@') && v.contains('.');
    return v.replaceAll(RegExp(r'\D'), '').length >= 10;
  }

  Future<void> _sendCode() async {
    if (!_identValid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).requestCode(
            email: _isEmail ? _identCtrl.text.trim() : null,
            phone: _isEmail ? null : _identCtrl.text.trim(),
          );
      setState(() {
        _codeStage = true;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = _humanError(e);
        _busy = false;
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).verifyCode(
            email: _isEmail ? _identCtrl.text.trim() : null,
            phone: _isEmail ? null : _identCtrl.text.trim(),
            code: code,
          );
      // SessionState now isSignedIn → parent rebuilds and pushes HomeScreen
    } catch (e) {
      setState(() {
        _error = _humanError(e);
        _busy = false;
      });
    }
  }

  String _humanError(Object e) {
    final raw = e.toString();
    final msg = raw.toLowerCase();
    if (msg.contains('network')) return "Network error — please check your connection.";
    if (msg.contains('verify_400') || msg.contains('verify_401')) {
      return "That code didn't match. Try again.";
    }
    if (msg.contains('request_429')) return "Too many requests. Wait a minute and try again.";
    if (msg.contains('invalid_email')) return "That email doesn't look valid.";
    if (msg.contains('invalid_phone')) return "Enter a valid phone (e.g. 03XX… or +971…).";
    if (msg.contains('rate_limit') || msg.contains('too_soon')) {
      return "Please wait a moment before requesting another code.";
    }
    if (msg.contains('user_inactive')) return "This account is disabled. Contact support.";
    // Try to surface the server's error code if there is one — the
    // generic "Something went wrong" message hides actionable detail.
    final m = RegExp(r'request_(\d+)').firstMatch(msg);
    if (m != null) {
      final code = m.group(1);
      return "Server error ${code ?? ''} — please try again, or use Skip for now.";
    }
    return "Something went wrong. Tap Skip for now to use Zeka anonymously.";
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                const ZekaBrandHeader(),
                const SizedBox(height: 40),
                Text(
                  _codeStage ? "Enter the 6-digit code" : "Welcome",
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: ZekaColors.text),
                ),
                const SizedBox(height: 6),
                Text(
                  _codeStage
                      ? "We sent it to ${_identCtrl.text.trim()}"
                      : "Sign in so Zeka remembers you across devices, or skip to use anonymously.",
                  style: const TextStyle(color: ZekaColors.muted),
                ),
                const SizedBox(height: 28),
                if (!_codeStage) ...[
                  // Email / Phone toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _toggleSeg('Email', _isEmail, () => setState(() => _isEmail = true)),
                        _toggleSeg('Phone', !_isEmail, () => setState(() => _isEmail = false)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _identCtrl,
                    focusNode: _identFocus,
                    keyboardType: _isEmail
                        ? TextInputType.emailAddress
                        : TextInputType.phone,
                    autocorrect: false,
                    autofillHints: [
                      _isEmail
                          ? AutofillHints.email
                          : AutofillHints.telephoneNumber
                    ],
                    // textInputAction.done shows a green check on the
                    // soft keyboard; pressing it (or the D-pad center
                    // on a TV remote) submits via onSubmitted instead
                    // of doing nothing.
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (_identValid && !_busy) {
                        _sendCode();
                      } else {
                        // Move focus to Send Code button anyway so the
                        // user can navigate forward on TV.
                        FocusScope.of(context)
                            .requestFocus(_sendBtnFocus);
                      }
                    },
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                        color: ZekaColors.text, fontSize: 16),
                    decoration: _decoration(_isEmail
                        ? "you@example.com"
                        : "+92 300 1234567"),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    focusNode: _sendBtnFocus,
                    autofocus: false,
                    onPressed: (!_busy && _identValid) ? _sendCode : null,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Send code'),
                  ),
                ] else ...[
                  TextField(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_codeCtrl.text.length >= 4 && !_busy) {
                        _verify();
                      } else {
                        FocusScope.of(context).requestFocus(_verifyBtnFocus);
                      }
                    },
                    style: const TextStyle(
                      color: ZekaColors.cyan,
                      fontSize: 28,
                      letterSpacing: 10,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.center,
                    decoration: _decoration('000000').copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    focusNode: _verifyBtnFocus,
                    onPressed: (!_busy && _codeCtrl.text.length >= 4) ? _verify : null,
                    child: _busy
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _codeStage = false;
                      _codeCtrl.clear();
                    }),
                    child: const Text('Change email / phone', style: TextStyle(color: ZekaColors.muted)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => ref.read(authProvider.notifier).skipAnonymous(),
                    child: const Text(
                      'Skip for now — use anonymously',
                      style: TextStyle(color: ZekaColors.muted, decoration: TextDecoration.underline),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleSeg(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? ZekaColors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : ZekaColors.muted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: ZekaColors.muted),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ZekaColors.purple),
        ),
      );
}
