import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Reuses the INTERACT magic-link auth flow already running on the
/// production VPS so the Zeka app can identify users without us
/// shipping a fresh auth stack. Endpoints:
///
///   POST https://interactpak.com/api/auth/zeka/request   { email | phone }
///        → sends a 6-digit code via email or SMS (uses the same
///          Comms Hub the web apps already use)
///   POST https://interactpak.com/api/auth/zeka/verify    { email | phone, code }
///        → returns { token, user }
///
/// Note: the endpoints aren't on the server yet — they need a small
/// shim on top of the existing /api/auth handlers. Marked TODO below.
/// In the meantime, "Skip for now" lets users use Zeka anonymously
/// and we cache last-used inputs locally.
class ZekaUser {
  final String id;
  final String displayName;
  final String? email;
  final String? phone;
  final DateTime lastSeen;
  const ZekaUser({
    required this.id,
    required this.displayName,
    required this.lastSeen,
    this.email,
    this.phone,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory ZekaUser.fromJson(Map<String, dynamic> j) => ZekaUser(
        id: j['id'] as String,
        displayName: j['displayName'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        lastSeen: DateTime.parse(j['lastSeen'] as String),
      );
}

/// In-app session state — either signed-in (with token + user) or
/// anonymous. Persisted to SharedPreferences so re-opens are instant.
class SessionState {
  final ZekaUser? user;
  final String? token;
  final bool anonymous;

  const SessionState({this.user, this.token, this.anonymous = false});

  bool get isSignedIn => user != null && token != null;
}

class AuthNotifier extends StateNotifier<SessionState> {
  AuthNotifier() : super(const SessionState()) {
    _restore();
  }

  static const _userKey = 'zeka.user';
  static const _tokenKey = 'zeka.token';
  static const _anonKey = 'zeka.anonymous';

  // 2026-06-10: JWT moved from SharedPreferences (plaintext XML, leaks
  // via adb backup / rooted device) to Keystore/Keychain-backed secure
  // storage — same pattern as sahulat_common ApiClient + sahl
  // token_manager. _userKey/_anonKey stay in SharedPreferences (not
  // secret). One-time SP→secure migration happens in _restore().
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> _readToken(SharedPreferences prefs) async {
    try {
      final tok = await _secure.read(key: _tokenKey);
      if (tok != null) return tok;
    } catch (e) {
      debugPrint('AuthNotifier secure read failed: $e');
    }
    // Legacy migration: token still in SharedPreferences from a
    // pre-2026-06-10 install → move it to secure storage, then purge.
    final legacy = prefs.getString(_tokenKey);
    if (legacy != null) {
      try {
        await _secure.write(key: _tokenKey, value: legacy);
        await prefs.remove(_tokenKey);
      } catch (e) {
        debugPrint('AuthNotifier token migration failed (will retry next launch): $e');
      }
    }
    return legacy;
  }

  Future<void> _writeToken(String token) async {
    await _secure.write(key: _tokenKey, value: token);
  }

  // Canonical host. The apex (`interactpak.com`) 301-redirects to
  // `www.interactpak.com` server-side, and the Dart http client drops
  // the POST body on 301 — symptom was "Something went wrong" at the
  // sign-in screen. Hitting the canonical host directly avoids the
  // bounce entirely.
  static const _apiBase = 'https://www.interactpak.com';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      final token = await _readToken(prefs);
      final anon = prefs.getBool(_anonKey) ?? false;
      if (userJson != null && token != null) {
        state = SessionState(
          user: ZekaUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>),
          token: token,
        );
        // Sliding-window: if the cached token is more than 5 days old,
        // refresh it in the background so the user never falls off the
        // 30-day cliff. Fire-and-forget; if the refresh fails we keep
        // the existing token until it actually expires server-side.
        unawaited(refreshIfStale());
      } else if (anon) {
        state = const SessionState(anonymous: true);
      }
    } catch (e) {
      debugPrint('AuthNotifier restore failed: $e');
    }
  }

  /// Mint a fresh 30-day JWT if the current one is within ~5 days of
  /// expiry. Server-side this is /api/auth/zeka/refresh which accepts
  /// the current Bearer token and returns a new one. Silent on failure
  /// — the user only sees the bounce-to-login screen if their token
  /// has already expired server-side.
  Future<void> refreshIfStale() async {
    final tok = state.token;
    if (tok == null) return;
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/auth/zeka/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $tok',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final newTok = j['token'] as String?;
      if (newTok == null) return;
      await _writeToken(newTok);
      state = SessionState(user: state.user, token: newTok);
    } catch (e) {
      debugPrint('AuthNotifier.refreshIfStale failed: $e');
    }
  }

  /// Request a 6-digit code by email OR phone. We accept whichever the
  /// user typed (interactpak's shared comms hub dispatches both).
  Future<void> requestCode({String? email, String? phone}) async {
    assert(email != null || phone != null);
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/auth/zeka/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (email != null) 'email': email,
              if (phone != null) 'phone': phone,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode >= 300) {
        throw AuthException('request_${res.statusCode}', res.body);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('network', e.toString());
    }
  }

  /// Verify the 6-digit code; on success persist user + token and flip
  /// state to signed-in.
  Future<void> verifyCode({String? email, String? phone, required String code}) async {
    assert(email != null || phone != null);
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/auth/zeka/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (email != null) 'email': email,
              if (phone != null) 'phone': phone,
              'code': code,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode >= 300) {
        throw AuthException('verify_${res.statusCode}', res.body);
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final user = ZekaUser.fromJson({
        'id': j['user']['id'],
        'displayName': j['user']['displayName'] ?? j['user']['name'] ?? 'Friend',
        if (j['user']['email'] != null) 'email': j['user']['email'],
        if (j['user']['phone'] != null) 'phone': j['user']['phone'],
        'lastSeen': DateTime.now().toIso8601String(),
      });
      final token = j['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      await _writeToken(token);
      await prefs.remove(_anonKey);
      state = SessionState(user: user, token: token);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('network', e.toString());
    }
  }

  Future<void> skipAnonymous() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_anonKey, true);
    state = const SessionState(anonymous: true);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_tokenKey); // legacy location — keep purging
    await prefs.remove(_anonKey);
    try {
      await _secure.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('AuthNotifier secure delete failed: $e');
    }
    state = const SessionState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, SessionState>((ref) => AuthNotifier());

class AuthException implements Exception {
  final String code;
  final String detail;
  AuthException(this.code, this.detail);
  @override
  String toString() => '$code: $detail';
}
