import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'auth_service.dart';
import 'policy_service.dart';

/// Per-user encrypted-by-OS-sandbox scratchpad. Holds:
///
///  * calculator history rows           (kind = 'calc')
///  * conversion history                (kind = 'conv')
///  * AI Q&A turns                      (kind = 'ai')
///  * handwriting samples (PNG bytes)   (kind = 'ink')
///
/// Each row is keyed on the owning userId (or `anon` for skipped sign-in),
/// so multiple users on the same device get isolated buckets. A nightly-ish
/// trim runs on every insert and enforces two caps simultaneously:
///
///   1. total bytes per user ≤ policy.maxBytes (default 50 MB)
///   2. records older than policy.retentionDays are dropped
///
/// Both caps are sourced from the remote policy endpoint
/// (/api/zeka/policy) so an admin can change them without a new APK.
/// If the endpoint can't be reached, the defaults baked into
/// PolicyService apply.
class UserStorage {
  static final UserStorage instance = UserStorage._();
  UserStorage._();

  Database? _db;
  StoragePolicy _policy = StoragePolicy.fallback();

  Future<Database> _open() async {
    if (_db != null && _db!.isOpen) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'zeka_user_data.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE entries (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id     TEXT NOT NULL,
            kind        TEXT NOT NULL,
            title       TEXT NOT NULL,
            payload     TEXT NOT NULL,
            bytes       INTEGER NOT NULL,
            created_at  INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_entries_user_created ON entries(user_id, created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_entries_user_kind ON entries(user_id, kind)',
        );
      },
    );
    return _db!;
  }

  /// Replace the in-memory policy. Called by the policy provider when the
  /// admin endpoint returns a new shape.
  void applyPolicy(StoragePolicy policy) {
    _policy = policy;
  }

  /// Persist a structured entry. `payload` is JSON-encoded; `title` is what
  /// the history strip / settings screen shows. Returns the new row id.
  Future<int> save({
    required String userId,
    required String kind,
    required String title,
    required Map<String, Object?> payload,
  }) async {
    final db = await _open();
    final body = jsonEncode(payload);
    final id = await db.insert('entries', {
      'user_id': userId,
      'kind': kind,
      'title': title.length > 200 ? title.substring(0, 200) : title,
      'payload': body,
      'bytes': body.length,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    // Trim eagerly. Cheap because the indexes cover both queries.
    unawaited(_trim(userId));
    return id;
  }

  Future<List<StoredEntry>> list({
    required String userId,
    String? kind,
    int limit = 50,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'entries',
      where: kind == null ? 'user_id = ?' : 'user_id = ? AND kind = ?',
      whereArgs: kind == null ? [userId] : [userId, kind],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(StoredEntry.fromRow).toList();
  }

  Future<int> deleteById(int id) async {
    final db = await _open();
    return db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  /// Wipe everything for one user. Used by the storage screen's "clear all"
  /// button and on sign-out (so a shared device doesn't leak prior users'
  /// history to the next signed-in person).
  Future<int> clearUser(String userId) async {
    final db = await _open();
    return db.delete('entries', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<StorageUsage> usage(String userId) async {
    final db = await _open();
    final agg = await db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(bytes),0) AS b FROM entries WHERE user_id = ?',
      [userId],
    );
    final n = (agg.first['n'] as int?) ?? 0;
    final b = (agg.first['b'] as int?) ?? 0;
    // Breakdown by kind for the settings screen.
    final breakdown = await db.rawQuery(
      'SELECT kind, COUNT(*) AS n, COALESCE(SUM(bytes),0) AS b '
      'FROM entries WHERE user_id = ? GROUP BY kind',
      [userId],
    );
    return StorageUsage(
      count: n,
      bytes: b,
      maxBytes: _policy.maxBytes,
      retentionDays: _policy.retentionDays,
      byKind: {
        for (final r in breakdown)
          (r['kind'] as String): _KindUsage(
            count: (r['n'] as int?) ?? 0,
            bytes: (r['b'] as int?) ?? 0,
          ),
      },
    );
  }

  /// Enforce policy: drop oldest until the user is under both caps.
  Future<void> _trim(String userId) async {
    try {
      final db = await _open();
      final cutoff = DateTime.now()
              .subtract(Duration(days: _policy.retentionDays))
              .millisecondsSinceEpoch;

      // 1. Age trim — cheap blanket delete.
      await db.delete(
        'entries',
        where: 'user_id = ? AND created_at < ?',
        whereArgs: [userId, cutoff],
      );

      // 2. Size trim — walk rows oldest-first until under cap.
      final used = await db.rawQuery(
        'SELECT COALESCE(SUM(bytes),0) AS b FROM entries WHERE user_id = ?',
        [userId],
      );
      var bytes = (used.first['b'] as int?) ?? 0;
      if (bytes <= _policy.maxBytes) return;

      final candidates = await db.query(
        'entries',
        columns: ['id', 'bytes'],
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at ASC',
      );
      for (final row in candidates) {
        if (bytes <= _policy.maxBytes) break;
        final id = row['id'] as int;
        final sz = (row['bytes'] as int?) ?? 0;
        await db.delete('entries', where: 'id = ?', whereArgs: [id]);
        bytes -= sz;
      }
    } catch (e) {
      debugPrint('UserStorage._trim failed: $e');
    }
  }
}

class StoredEntry {
  final int id;
  final String userId;
  final String kind;
  final String title;
  final Map<String, Object?> payload;
  final int bytes;
  final DateTime createdAt;
  const StoredEntry({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.payload,
    required this.bytes,
    required this.createdAt,
  });

  factory StoredEntry.fromRow(Map<String, Object?> row) {
    Map<String, Object?> p;
    try {
      p = jsonDecode(row['payload'] as String) as Map<String, Object?>;
    } catch (_) {
      p = const {};
    }
    return StoredEntry(
      id: row['id'] as int,
      userId: row['user_id'] as String,
      kind: row['kind'] as String,
      title: row['title'] as String,
      payload: p,
      bytes: (row['bytes'] as int?) ?? 0,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch((row['created_at'] as int?) ?? 0),
    );
  }
}

class _KindUsage {
  final int count;
  final int bytes;
  const _KindUsage({required this.count, required this.bytes});
}

class StorageUsage {
  final int count;
  final int bytes;
  final int maxBytes;
  final int retentionDays;
  final Map<String, _KindUsage> byKind;
  const StorageUsage({
    required this.count,
    required this.bytes,
    required this.maxBytes,
    required this.retentionDays,
    required this.byKind,
  });

  double get fractionUsed => maxBytes <= 0 ? 0 : bytes / maxBytes;

  int countOf(String kind) => byKind[kind]?.count ?? 0;
  int bytesOf(String kind) => byKind[kind]?.bytes ?? 0;
}

/// Convenience helper: return the "key" we save against — either the
/// signed-in user's id, or "anon" so skipped-sign-in users still get
/// their own bucket.
String storageUserKey(SessionState s) =>
    s.user?.id ?? (s.anonymous ? 'anon' : 'anon');

/// Riverpod provider for the singleton.
final userStorageProvider = Provider<UserStorage>((_) => UserStorage.instance);
