import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Per-user storage limits sourced from interactpak.com's admin-tunable
/// policy endpoint. Default 50 MB / 30 days; the admin can change either
/// value live and clients pick up the new shape on next cold start.
class StoragePolicy {
  final int maxBytes;
  final int retentionDays;
  final DateTime fetchedAt;

  const StoragePolicy({
    required this.maxBytes,
    required this.retentionDays,
    required this.fetchedAt,
  });

  /// Defaults used until the policy endpoint responds (or if it never
  /// does — the app is offline-first).
  factory StoragePolicy.fallback() => StoragePolicy(
        maxBytes: 50 * 1024 * 1024, // 50 MB
        retentionDays: 30,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, Object?> toJson() => {
        'maxBytes': maxBytes,
        'retentionDays': retentionDays,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory StoragePolicy.fromJson(Map<String, Object?> j) => StoragePolicy(
        maxBytes: (j['maxBytes'] as num?)?.toInt() ?? 50 * 1024 * 1024,
        retentionDays: (j['retentionDays'] as num?)?.toInt() ?? 30,
        fetchedAt: DateTime.tryParse(j['fetchedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Notifier that hydrates from SharedPreferences on construction, then
/// refreshes from the server in the background. UI never blocks on the
/// network — defaults are good enough to start with.
class PolicyNotifier extends StateNotifier<StoragePolicy> {
  PolicyNotifier() : super(StoragePolicy.fallback()) {
    _hydrate();
  }

  static const _prefsKey = 'zeka.policy';
  // Canonical host (apex 301-redirects to www); hit www directly so
  // the cached policy actually updates on launch.
  static const _endpoint = 'https://www.interactpak.com/api/zeka/policy';

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        state = StoragePolicy.fromJson(
            jsonDecode(raw) as Map<String, Object?>);
      }
    } catch (_) {/* fall through to defaults */}
    unawaited(refresh());
  }

  /// Pull the latest limits. Safe to call any time; failures are
  /// silent (we keep the last known shape).
  Future<void> refresh() async {
    try {
      final res = await http
          .get(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, Object?>;
      final next = StoragePolicy(
        maxBytes: (body['maxBytes'] as num?)?.toInt() ?? state.maxBytes,
        retentionDays:
            (body['retentionDays'] as num?)?.toInt() ?? state.retentionDays,
        fetchedAt: DateTime.now(),
      );
      state = next;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(next.toJson()));
      } catch (_) {/* non-fatal */}
    } catch (e) {
      debugPrint('PolicyNotifier.refresh failed: $e');
    }
  }
}

final policyProvider =
    StateNotifierProvider<PolicyNotifier, StoragePolicy>((_) => PolicyNotifier());
