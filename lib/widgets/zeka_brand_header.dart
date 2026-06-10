import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/language_service.dart';
import '../theme.dart';
import 'language_picker.dart';

/// Brand mark + tagline + the new ZekaLanguagePicker (a flag pill that
/// opens a modal listing all 6 supported languages — much nicer than
/// the old binary EN/اردو toggle which couldn't grow past 2 options).
class ZekaBrandHeader extends ConsumerWidget {
  final bool compact;
  const ZekaBrandHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        // Z brand mark
        Container(
          width: compact ? 36 : 48,
          height: compact ? 36 : 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [ZekaColors.purple, ZekaColors.cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            'Z',
            style: TextStyle(
              fontSize: compact ? 18 : 24,
              fontWeight: FontWeight.w900,
              color: ZekaColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(tr(context, ref, 'brand'),
                      style: TextStyle(
                        fontSize: compact ? 16 : 22,
                        fontWeight: FontWeight.w700,
                        color: ZekaColors.text,
                      )),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: ZekaColors.purple.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tr(context, ref, 'beta').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        color: ZekaColors.purple,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tr(context, ref, 'brandSub'),
                    style: const TextStyle(fontSize: 12, color: ZekaColors.muted),
                  ),
                ),
            ],
          ),
        ),
        // Language picker — current flag/code + dropdown to a modal
        const ZekaLanguagePicker(),
      ],
    );
  }
}
