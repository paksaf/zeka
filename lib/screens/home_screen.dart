import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/language_service.dart';
import '../theme.dart';
import '../widgets/local_context_card.dart';
import '../widgets/speak_sheet.dart';
import '../widgets/zeka_brand_header.dart';
import 'calculator_screen.dart';
import 'converter_screen.dart';
import 'storage_screen.dart';

/// Zeka home — v0.2 layout (the one users said felt right) wired to
/// the v0.3 SpeakSheet behaviour:
///
///   Top         : brand header (Z + name + lang picker)
///   Below       : LocalContextCard (time + city + temp)
///   Tile row    : Calculator + Unit converter (full Material tiles)
///   Hero        : "Ask Zeka" gradient banner — tap → SpeakSheet
///   Bottom row  : History tile (full width) + Hey Zeka FAB
///
/// Both the Ask Zeka card and the floating Hey Zeka button open the
/// same SpeakSheet so users have two equally obvious entry points.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final session = ref.watch(authProvider);
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              const ZekaBrandHeader(),
              const SizedBox(height: 18),
              const LocalContextCard(),
              if (session.user != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    '${_timeOfDayGreeting(context, ref)}, ${session.user!.displayName.split(' ').first} 👋',
                    style: const TextStyle(
                      color: ZekaColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (session.user != null)
                const Padding(
                  padding: EdgeInsets.only(top: 2, left: 4),
                  child: Text(
                    "What would you like Zeka to help with today?",
                    style: TextStyle(color: ZekaColors.muted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 22),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.15,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _Tile(
                    icon: Icons.calculate_outlined,
                    title: tr(context, ref, 'calculator'),
                    subtitle: 'Basic · Scientific · Formulas',
                    color: ZekaColors.purple,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CalculatorScreen())),
                  ),
                  _Tile(
                    icon: Icons.swap_horiz,
                    title: tr(context, ref, 'converter'),
                    subtitle: '25 categories · Marla · Maund',
                    color: ZekaColors.cyan,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ConverterScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AskZekaTile(onTap: () => _openSpeakSheet(context)),
              const SizedBox(height: 12),
              _Tile(
                icon: Icons.history,
                title: tr(context, ref, 'history'),
                subtitle: tr(context, ref, 'historySub'),
                color: ZekaColors.cyan,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StorageScreen()),
                ),
                fullWidth: true,
              ),
            ],
          ),
        ),
        floatingActionButton: _HeyZekaFab(onTap: () => _openSpeakSheet(context)),
      ),
    );
  }

  void _openSpeakSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // autoListen disabled — auto-starting the mic on open was firing
      // a no_match error spam on TV (no mic) and felt jarring on phone
      // too. User explicitly taps the mic when they want to speak.
      builder: (_) => const SpeakSheet(autoListen: false),
    );
  }

  /// Localised time-of-day greeting. Falls back to "Hello" for
  /// languages we haven't translated yet.
  String _timeOfDayGreeting(BuildContext context, WidgetRef ref) {
    final h = DateTime.now().hour;
    final lang = ref.read(languageProvider);
    String key;
    if (h < 12) {
      key = 'goodMorning';
    } else if (h < 17) {
      key = 'goodAfternoon';
    } else {
      key = 'goodEvening';
    }
    // The lang service falls back to English if the key isn't
    // translated, so any locale renders something sensible.
    final s = tr(context, ref, key);
    if (s == key) {
      // Untranslated — use English defaults
      switch (h) {
        case < 12:
          return lang.isRtl ? 'صباح الخير' : 'Good morning';
        case < 17:
          return 'Good afternoon';
        default:
          return 'Good evening';
      }
    }
    return s;
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final bool fullWidth;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    // _FocusableTile wraps InkWell with a heavy cyan border when focused,
    // so Android TV D-pad navigation is unmistakable (out-of-the-box
    // Material focus ring is invisible on the navy background).
    return _FocusableTile(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF202036),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: fullWidth
              ? Row(
                  children: [
                    _iconBlock(),
                    const SizedBox(width: 14),
                    Expanded(child: _text()),
                    const Icon(Icons.chevron_right, color: ZekaColors.muted),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _iconBlock(),
                    const Spacer(),
                    _text(),
                  ],
                ),
        ),
    );
  }

  Widget _iconBlock() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 26),
      );

  Widget _text() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ZekaColors.text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: ZekaColors.muted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}

/// "Ask Zeka" hero — full-width gradient banner. Taps open the
/// SpeakSheet directly so voice/camera/handwriting are one tap away.
class _AskZekaTile extends ConsumerWidget {
  final VoidCallback onTap;
  const _AskZekaTile({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reuse the home-screen _FocusableTile pattern so the Ask Zeka
    // hero banner participates in TV D-pad navigation (focus ring +
    // OK button) just like the other tiles.
    return _FocusableTile(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [ZekaColors.purple, ZekaColors.cyan],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, ref, 'askZeka'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(context, ref, 'voiceHint'),
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.mic, color: Colors.white, size: 24),
            ],
          ),
      ),
    );
  }
}

/// Floating "Hey Zeka" button — equally prominent CTA next to the
/// hero banner. Opens the same SpeakSheet.
class _HeyZekaFab extends StatelessWidget {
  final VoidCallback onTap;
  const _HeyZekaFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: ZekaColors.purple,
      elevation: 6,
      icon: const Icon(Icons.graphic_eq, color: Colors.white),
      label: const Text(
        'Hey Zeka',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Tile wrapper that draws a thick cyan focus ring + lift when the
/// hardware focus is on it AND translates the TV remote's OK/Select
/// button into an onTap. Without the shortcut bindings, the focus
/// ring appears on D-pad navigation but pressing center does nothing
/// — exactly the "stuck in a loop" symptom on Bravia VH21.
///
/// FocusableActionDetector is the canonical Flutter pattern for
/// D-pad-friendly widgets: it combines Focus + Actions + Shortcuts.
class _FocusableTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _FocusableTile({required this.child, required this.onTap});
  @override
  State<_FocusableTile> createState() => _FocusableTileState();
}

class _FocusableTileState extends State<_FocusableTile> {
  bool _focused = false;

  // Every key Android TV remotes might send for "OK / select".
  // Different vendors fire different LogicalKeyboardKey codes:
  //   Sony Bravia → `select`
  //   Most remotes → `enter`
  //   Some game remotes / phone D-pads → `numpadEnter` or `gameButtonA`
  //   Keyboard testing → `space`
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
      autofocus: false,
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
      // GestureDetector keeps touch / mouse working — the
      // FocusableActionDetector layer only intercepts keyboard events,
      // it doesn't block taps.
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          transform: _focused
              ? (Matrix4.identity()..scale(1.03))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: ZekaColors.cyan.withOpacity(0.55),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
            border: Border.all(
              color: _focused ? ZekaColors.cyan : Colors.transparent,
              width: 3,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(15),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
