import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/expression_eval.dart';
import '../services/language_service.dart';
import '../services/user_storage.dart';
import '../theme.dart';

/// Cleaner Calculator — display at top, mode toggles below it, then a
/// fixed-height grid keypad. Builds correctly on any viewport (web,
/// desktop, mobile) because the keypad height is computed from
/// available space, not via Expanded inside a scroll view.
///
/// Live preview is recomputed in setState handlers (no side effects
/// in build()), and parser exceptions are caught silently so a
/// half-typed expression doesn't blank out the result.
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key});
  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _HistoryRow {
  final String expr;
  final String result;
  _HistoryRow(this.expr, this.result);
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  String _expr = '';
  String _result = '0';
  bool _degrees = true;
  final List<_HistoryRow> _history = [];

  @override
  void initState() {
    super.initState();
    // Pull recent calc history from the scratchpad so the strip survives
    // app restarts (was previously in-memory only).
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateHistory());
  }

  Future<void> _hydrateHistory() async {
    try {
      final session = ref.read(authProvider);
      final entries = await UserStorage.instance.list(
        userId: storageUserKey(session),
        kind: 'calc',
        limit: 12,
      );
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(entries.map((e) => _HistoryRow(
                e.payload['expr'] as String? ?? '',
                e.payload['result'] as String? ?? '',
              )));
      });
    } catch (_) {/* empty on first run */}
  }

  void _press(String s) => setState(() {
        _expr = _expr + s;
        _recompute();
      });

  void _back() => setState(() {
        if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
        _recompute();
      });

  void _clear() => setState(() {
        _expr = '';
        _result = '0';
      });

  void _equals() => setState(() {
        if (_expr.trim().isEmpty) return;
        // Auto-balance: append missing close-parens. Without this,
        // tapping "sqrt" → "9" → "=" fails because the user never had
        // to type the closing ")". Same fix covers sin/cos/tan/ln/log/abs.
        var balanced = _expr;
        final opens = '('.allMatches(balanced).length;
        final closes = ')'.allMatches(balanced).length;
        if (opens > closes) {
          balanced = balanced + (')' * (opens - closes));
        }
        try {
          final v = evaluate(balanced, degrees: _degrees);
          final s = _fmt(v);
          final exprBefore = balanced;
          _history.insert(0, _HistoryRow(exprBefore, s));
          if (_history.length > 12) _history.removeLast();
          _expr = s;
          _result = s;
          // Persist to per-user scratchpad. Fire-and-forget; the UI
          // doesn't wait on disk. UserStorage handles the size cap.
          final session = ref.read(authProvider);
          UserStorage.instance.save(
            userId: storageUserKey(session),
            kind: 'calc',
            title: '$exprBefore = $s',
            payload: {
              'expr': exprBefore,
              'result': s,
              'degrees': _degrees,
            },
          );
        } catch (_) {
          _result = 'Error';
        }
      });

  void _recompute() {
    if (_expr.trim().isEmpty) {
      _result = '0';
      return;
    }
    // Mid-typing live preview: try to evaluate with auto-closed
    // parens so sqrt(9 shows 3 immediately, even before the user
    // adds the close-paren themselves.
    var balanced = _expr;
    final opens = '('.allMatches(balanced).length;
    final closes = ')'.allMatches(balanced).length;
    if (opens > closes) {
      balanced = balanced + (')' * (opens - closes));
    }
    try {
      _result = _fmt(evaluate(balanced, degrees: _degrees));
    } catch (_) {
      // Keep last good result while user is mid-expression
    }
  }

  String _fmt(double n) {
    if (n.isNaN) return 'NaN';
    if (n.isInfinite) return '∞';
    if (n == n.roundToDouble() && n.abs() < 1e15) return n.toInt().toString();
    var s = n.toStringAsFixed(10);
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: ZekaColors.navy,
        appBar: AppBar(
          backgroundColor: ZekaColors.navy,
          elevation: 0,
          title: Text(
              '${tr(context, ref, 'calculator')}${isLandscape ? ' · scientific' : ''}'),
          actions: [
            TextButton(
              onPressed: () => setState(() => _degrees = !_degrees),
              child: Text(
                _degrees ? 'DEG' : 'RAD',
                style: const TextStyle(
                    color: ZekaColors.purple, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Display(expr: _expr, result: _result),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final h = _history[i];
                        return InkWell(
                          onTap: () => setState(() {
                            _expr = h.result;
                            _recompute();
                          }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Text(h.expr,
                                    style: const TextStyle(
                                        color: ZekaColors.muted,
                                        fontFamily: 'monospace',
                                        fontSize: 11)),
                                const SizedBox(width: 6),
                                Text('= ${h.result}',
                                    style: const TextStyle(
                                        color: ZekaColors.cyan,
                                        fontFamily: 'monospace',
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _FnRow(press: _press),
                const SizedBox(height: 10),
                Expanded(child: isLandscape
                    ? Row(
                        children: [
                          // Left: extended scientific keypad (only
                          // visible in landscape — phones flip to use
                          // the wider screen for more buttons).
                          Expanded(
                            flex: 3,
                            child: _SciKeypad(press: _press),
                          ),
                          const SizedBox(width: 8),
                          // Right: the regular numeric keypad.
                          Expanded(
                            flex: 4,
                            child: _Keypad(
                              press: _press,
                              back: _back,
                              clear: _clear,
                              equals: _equals,
                            ),
                          ),
                        ],
                      )
                    : _Keypad(
                        press: _press,
                        back: _back,
                        clear: _clear,
                        equals: _equals,
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Display extends StatelessWidget {
  final String expr;
  final String result;
  const _Display({required this.expr, required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            expr.isEmpty ? '0' : expr,
            maxLines: 2,
            overflow: TextOverflow.fade,
            style: const TextStyle(
              fontSize: 20, color: ZekaColors.muted, fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '= $result',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 30,
              color: ZekaColors.cyan,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FnRow extends StatelessWidget {
  final void Function(String) press;
  const _FnRow({required this.press});
  @override
  Widget build(BuildContext context) {
    const fns = ['sin(', 'cos(', 'tan(', 'sqrt(', 'ln(', 'log(', 'π', 'e', '^', '!'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final f = fns[i];
          return InkWell(
            onTap: () => press(f),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ZekaColors.cyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ZekaColors.cyan.withOpacity(0.25)),
              ),
              child: Center(
                child: Text(
                  f.replaceAll('(', ''),
                  style: const TextStyle(
                    color: ZekaColors.cyan,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) press;
  final VoidCallback back;
  final VoidCallback clear;
  final VoidCallback equals;
  const _Keypad({
    required this.press, required this.back,
    required this.clear, required this.equals,
  });

  @override
  Widget build(BuildContext context) {
    // 5 rows × 4 cols = 20 buttons. Compute size from available
    // height so the keypad always fits without scrolling.
    return LayoutBuilder(builder: (_, c) {
      const cols = 4;
      const rows = 5;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final h = (c.maxHeight - gap * (rows - 1)) / rows;
      return Column(
        children: [
          _row([_k('AC', clear, _V.clear), _k('⌫', back, _V.op),
                _k('(', () => press('('), _V.op), _k(')', () => press(')'), _V.op)],
              w, h, gap),
          SizedBox(height: gap),
          _row([_k('7', () => press('7')), _k('8', () => press('8')),
                _k('9', () => press('9')), _k('÷', () => press('/'), _V.op)],
              w, h, gap),
          SizedBox(height: gap),
          _row([_k('4', () => press('4')), _k('5', () => press('5')),
                _k('6', () => press('6')), _k('×', () => press('*'), _V.op)],
              w, h, gap),
          SizedBox(height: gap),
          _row([_k('1', () => press('1')), _k('2', () => press('2')),
                _k('3', () => press('3')), _k('−', () => press('-'), _V.op)],
              w, h, gap),
          SizedBox(height: gap),
          _row([_k('0', () => press('0')), _k('.', () => press('.')),
                _k('=', equals, _V.primary), _k('+', () => press('+'), _V.op)],
              w, h, gap),
        ],
      );
    });
  }

  Widget _row(List<_KSpec> keys, double w, double h, double gap) {
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          SizedBox(width: w, height: h, child: _build(keys[i])),
        ],
      ],
    );
  }

  _KSpec _k(String label, VoidCallback onTap, [_V variant = _V.digit]) =>
      _KSpec(label, onTap, variant);

  Widget _build(_KSpec k) {
    Color bg;
    Color fg;
    switch (k.variant) {
      case _V.primary: bg = ZekaColors.purple; fg = Colors.white; break;
      case _V.op:      bg = Colors.white12;    fg = ZekaColors.cyan; break;
      case _V.clear:   bg = Colors.red.withOpacity(0.18); fg = Colors.red.shade300; break;
      default:         bg = Colors.white.withOpacity(0.05); fg = ZekaColors.text;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: k.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            k.label,
            style: TextStyle(
              color: fg, fontSize: 20, fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

enum _V { digit, op, primary, clear }
class _KSpec {
  final String label;
  final VoidCallback onTap;
  final _V variant;
  _KSpec(this.label, this.onTap, this.variant);
}

/// Scientific keypad shown ONLY in landscape — uses the extra width
/// to surface trig, log, power, root, factorial without needing the
/// horizontal scroll bar at the top.
class _SciKeypad extends StatelessWidget {
  final void Function(String) press;
  const _SciKeypad({required this.press});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      const cols = 3;
      const rows = 5;
      const gap = 6.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      final h = (c.maxHeight - gap * (rows - 1)) / rows;
      Widget btn(String label, String emit) => SizedBox(
            width: w,
            height: h,
            child: Material(
              color: ZekaColors.cyan.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => press(emit),
                borderRadius: BorderRadius.circular(10),
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                        color: ZekaColors.cyan,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ),
            ),
          );
      Widget row(List<Widget> kids) => Row(
            children: [
              for (var i = 0; i < kids.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                kids[i],
              ],
            ],
          );
      return Column(
        children: [
          row([btn('sin', 'sin('), btn('cos', 'cos('), btn('tan', 'tan(')]),
          const SizedBox(height: gap),
          row([btn('ln', 'ln('), btn('log', 'log('), btn('√', 'sqrt(')]),
          const SizedBox(height: gap),
          row([btn('x²', '^2'), btn('xʸ', '^'), btn('!', '!')]),
          const SizedBox(height: gap),
          row([btn('π', 'π'), btn('e', 'e'), btn('|x|', 'abs(')]),
          const SizedBox(height: gap),
          row([btn('(', '('), btn(')', ')'), btn('%', '/100')]),
        ],
      );
    });
  }
}
