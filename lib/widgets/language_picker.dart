import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/language_service.dart';
import '../theme.dart';

/// A pill button that shows the current language, with a tap to open
/// a modal of all 6 supported languages with their native names + flags.
class ZekaLanguagePicker extends ConsumerWidget {
  const ZekaLanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return InkWell(
      onTap: () => _openSheet(context, ref),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: ZekaColors.purple.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ZekaColors.purple.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              lang.pillLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    final current = ref.read(languageProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(ctx, ref, 'selectLanguage'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ZekaColors.text,
                    ),
                  ),
                ),
                ...ZekaLang.values.map((l) => _LangRow(
                      lang: l,
                      selected: l == current,
                      onTap: () {
                        ref.read(languageProvider.notifier).set(l);
                        Navigator.pop(ctx);
                      },
                    )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LangRow extends StatelessWidget {
  final ZekaLang lang;
  final bool selected;
  final VoidCallback onTap;
  const _LangRow({required this.lang, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: selected ? ZekaColors.purple.withOpacity(0.12) : Colors.transparent,
        child: Row(
          children: [
            Text(lang.flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang.nativeName,
                    style: TextStyle(
                      color: selected ? ZekaColors.purple : ZekaColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (lang.nativeName != lang.englishName)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        lang.englishName,
                        style: const TextStyle(color: ZekaColors.muted, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: ZekaColors.purple, size: 22),
          ],
        ),
      ),
    );
  }
}
