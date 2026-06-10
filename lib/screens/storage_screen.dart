import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/policy_service.dart';
import '../services/user_storage.dart';
import '../theme.dart';

/// Per-user storage panel. Surfaces:
///   * total usage (vs. policy cap)
///   * breakdown by kind (calc, conv, ai, ink)
///   * retention window
///   * "clear my history" button
///
/// Limits come from the remote policy endpoint so an admin can change
/// them centrally. If the endpoint hasn't been reached yet, the bundled
/// defaults (50 MB / 30 d) apply.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});
  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  StorageUsage? _usage;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = ref.read(authProvider);
      final u = await UserStorage.instance.usage(storageUserKey(session));
      if (mounted) setState(() => _usage = u);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear all history?',
            style: TextStyle(color: ZekaColors.text)),
        content: const Text(
          "This removes your calculator history, conversion history, "
          "and AI Q&A on this device. Server-side history isn't touched.",
          style: TextStyle(color: ZekaColors.muted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(authProvider);
    await UserStorage.instance.clearUser(storageUserKey(session));
    await _load();
  }

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final policy = ref.watch(policyProvider);
    final session = ref.watch(authProvider);
    final u = _usage;

    return Scaffold(
      backgroundColor: ZekaColors.navy,
      appBar: AppBar(
        backgroundColor: ZekaColors.navy,
        elevation: 0,
        title: const Text('Storage & history'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: ZekaColors.cyan),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading || u == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _AccountBlock(session: session),
                  const SizedBox(height: 16),
                  _UsageCard(
                    used: u.bytes,
                    max: policy.maxBytes,
                    count: u.count,
                    fmt: _fmtBytes,
                  ),
                  const SizedBox(height: 12),
                  _PolicyCard(policy: policy, fmt: _fmtBytes),
                  const SizedBox(height: 16),
                  const _SectionLabel('By type'),
                  _KindRow(
                      label: 'Calculator',
                      count: u.countOf('calc'),
                      bytes: u.bytesOf('calc'),
                      fmt: _fmtBytes,
                      icon: Icons.calculate_outlined),
                  _KindRow(
                      label: 'Conversions',
                      count: u.countOf('conv'),
                      bytes: u.bytesOf('conv'),
                      fmt: _fmtBytes,
                      icon: Icons.swap_horiz),
                  _KindRow(
                      label: 'AI Q&A',
                      count: u.countOf('ai'),
                      bytes: u.bytesOf('ai'),
                      fmt: _fmtBytes,
                      icon: Icons.auto_awesome),
                  _KindRow(
                      label: 'Handwriting',
                      count: u.countOf('ink'),
                      bytes: u.bytesOf('ink'),
                      fmt: _fmtBytes,
                      icon: Icons.edit),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.15),
                        foregroundColor: Colors.redAccent),
                    onPressed: u.count == 0 ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear my history on this device'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AccountBlock extends StatelessWidget {
  final SessionState session;
  const _AccountBlock({required this.session});
  @override
  Widget build(BuildContext context) {
    final name = session.user?.displayName ??
        (session.anonymous ? 'Anonymous' : 'Not signed in');
    final sub = session.user?.email ?? session.user?.phone ?? 'Local-only';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: ZekaColors.purple,
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: ZekaColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        color: ZekaColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final int used;
  final int max;
  final int count;
  final String Function(int) fmt;
  const _UsageCard(
      {required this.used,
      required this.max,
      required this.count,
      required this.fmt});
  @override
  Widget build(BuildContext context) {
    final pct = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ZekaColors.purple, ZekaColors.cyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Local storage',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 12,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmt(used),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace')),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('/ ${fmt(max)}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontFamily: 'monospace',
                        fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.18),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text('$count items saved',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 12)),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final StoragePolicy policy;
  final String Function(int) fmt;
  const _PolicyCard({required this.policy, required this.fmt});
  @override
  Widget build(BuildContext context) {
    final fetched = policy.fetchedAt.millisecondsSinceEpoch == 0
        ? 'using defaults'
        : 'updated ${_relative(policy.fetchedAt)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: ZekaColors.cyan, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Policy: ${fmt(policy.maxBytes)} cap · '
                    '${policy.retentionDays}-day retention',
                    style: const TextStyle(
                        color: ZekaColors.text, fontSize: 13)),
                const SizedBox(height: 2),
                Text(fetched,
                    style: const TextStyle(
                        color: ZekaColors.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: ZekaColors.muted,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold)),
      );
}

class _KindRow extends StatelessWidget {
  final String label;
  final int count;
  final int bytes;
  final IconData icon;
  final String Function(int) fmt;
  const _KindRow(
      {required this.label,
      required this.count,
      required this.bytes,
      required this.icon,
      required this.fmt});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: ZekaColors.cyan, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: ZekaColors.text, fontSize: 14))),
          Text('$count',
              style: const TextStyle(
                  color: ZekaColors.muted,
                  fontSize: 12,
                  fontFamily: 'monospace')),
          const SizedBox(width: 10),
          Text(fmt(bytes),
              style: const TextStyle(
                  color: ZekaColors.cyan,
                  fontSize: 12,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
