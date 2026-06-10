import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hijri.dart';
import '../services/language_service.dart';
import '../services/location_service.dart';
import '../theme.dart';

/// "Local context" surface — sits on the home screen and quietly says
/// "Zeka knows where you are and what time it is, so any answer it
/// gives will be locally meaningful." Shows:
///   - the device's detected city + country (from timezone)
///   - live clock that ticks every second
///   - today's date in the user's language
///   - current outdoor temperature (Open-Meteo, no API key)
///
/// Designed to fade in without flashing — the snapshot is cached after
/// the first weather fetch so subsequent rebuilds are instant.
class LocalContextCard extends ConsumerStatefulWidget {
  const LocalContextCard({super.key});
  @override
  ConsumerState<LocalContextCard> createState() => _LocalContextCardState();
}

class _LocalContextCardState extends ConsumerState<LocalContextCard> {
  final _service = LocationService();
  LocalContext? _ctx;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Live clock — re-render every 30s so the time stays accurate
    // without burning frames every second.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  Future<void> _load() async {
    final ctx = await _service.snapshot();
    if (mounted) setState(() => _ctx = ctx);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _ctx;
    final lang = ref.watch(languageProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ZekaColors.purple.withOpacity(0.12),
            ZekaColors.cyan.withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          // Time block (always available)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctx?.formattedTime ?? '—',
                style: const TextStyle(
                  color: ZekaColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                ctx?.formattedDate ?? '',
                style: const TextStyle(color: ZekaColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                gregorianToHijriString(DateTime.now()),
                style: const TextStyle(
                  color: ZekaColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          // City + temperature pill (right side)
          if (ctx != null) ...[
            const Icon(Icons.location_on_outlined, size: 14, color: ZekaColors.cyan),
            const SizedBox(width: 4),
            Text(
              ctx.countryCode.isEmpty ? ctx.city : '${ctx.city}, ${ctx.countryCode}',
              style: const TextStyle(color: ZekaColors.text, fontWeight: FontWeight.w500, fontSize: 12),
            ),
            if (ctx.temperatureC != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ZekaColors.cyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  ctx.temperatureC!,
                  style: const TextStyle(
                    color: ZekaColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
