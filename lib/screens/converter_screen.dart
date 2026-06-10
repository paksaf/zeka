import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/local_converter.dart';
import '../services/language_service.dart';
import '../services/user_storage.dart';
import '../theme.dart';

/// Unit Converter — category strip across the top, input/output rows,
/// swap button. Mirrors the calculator's defensive layout:
///   * Scaffold has an explicit background so the page never renders
///     blank if the theme doesn't pick up.
///   * TextEditingController lives in state (NOT rebuilt every frame),
///     which fixes the cursor-jumping + blank-input bug.
///   * Conversion happens in a pure getter, never as a side effect of
///     build().
class ConverterScreen extends ConsumerStatefulWidget {
  const ConverterScreen({super.key});
  @override
  ConsumerState<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends ConsumerState<ConverterScreen> {
  late ConversionCategory _category;
  late Unit _from;
  late Unit _to;
  final TextEditingController _input = TextEditingController(text: '1');
  Timer? _logDebounce;

  @override
  void initState() {
    super.initState();
    _category = conversionCategories.first;
    _from = _category.units[0];
    _to = _category.units.length > 1 ? _category.units[1] : _category.units[0];
    _restore();
  }

  @override
  void dispose() {
    _logDebounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _scheduleHistoryLog() {
    _logDebounce?.cancel();
    _logDebounce = Timer(const Duration(milliseconds: 900), () {
      final v = _input.text.trim();
      if (v.isEmpty || _result == '—') return;
      final session = ref.read(authProvider);
      UserStorage.instance.save(
        userId: storageUserKey(session),
        kind: 'conv',
        title: '$v ${_from.symbol} = $_result ${_to.symbol}',
        payload: {
          'category': _category.id,
          'value': v,
          'from': _from.symbol,
          'to': _to.symbol,
          'result': _result,
        },
      );
    });
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cid = prefs.getString('zeka.conv.cat');
      final fs = prefs.getString('zeka.conv.from');
      final ts = prefs.getString('zeka.conv.to');
      if (cid != null && mounted) {
        final c = categoryById(cid);
        setState(() {
          _category = c;
          _from = c.units.firstWhere(
            (u) => u.symbol == fs,
            orElse: () => c.units.first,
          );
          _to = c.units.firstWhere(
            (u) => u.symbol == ts,
            orElse: () =>
                c.units.length > 1 ? c.units[1] : c.units.first,
          );
        });
      }
    } catch (_) {
      // Stick with defaults if prefs read fails.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zeka.conv.cat', _category.id);
      await prefs.setString('zeka.conv.from', _from.symbol);
      await prefs.setString('zeka.conv.to', _to.symbol);
    } catch (_) {/* non-fatal */}
  }

  String get _result {
    final v = double.tryParse(_input.text);
    if (v == null) return '—';
    try {
      return formatResult(convert(v, _from, _to, _category));
    } catch (_) {
      return '—';
    }
  }

  void _swap() {
    setState(() {
      final tmp = _from;
      _from = _to;
      _to = tmp;
    });
    _save();
  }

  void _pickCategory(ConversionCategory c) {
    setState(() {
      _category = c;
      _from = c.units.first;
      _to = c.units.length > 1 ? c.units[1] : c.units.first;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Directionality(
      textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: ZekaColors.navy,
        appBar: AppBar(
          backgroundColor: ZekaColors.navy,
          elevation: 0,
          title: Text(tr(context, ref, 'converter')),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Category strip — horizontally scrollable. The fade
                // on the right edge hints there are more categories
                // beyond what fits on screen (11 categories in total).
                ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.85, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: conversionCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final c = conversionCategories[i];
                      final active = c.id == _category.id;
                      return InkWell(
                        onTap: () => _pickCategory(c),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: active
                                ? ZekaColors.purple
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active
                                  ? ZekaColors.purple
                                  : Colors.white12,
                            ),
                          ),
                          child: Text(
                            c.name,
                            style: TextStyle(
                              color: active ? Colors.white : ZekaColors.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${conversionCategories.length} categories →',
                      style: const TextStyle(
                          color: ZekaColors.muted, fontSize: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // FROM row
                _LabeledBlock(
                  label: tr(context, ref, 'from'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) {
                            setState(() {});
                            _scheduleHistoryLog();
                          },
                          style: const TextStyle(
                            fontSize: 22,
                            fontFamily: 'monospace',
                            color: ZekaColors.text,
                          ),
                          decoration: _decoration(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UnitPicker(
                        units: _category.units,
                        selected: _from,
                        onChanged: (u) {
                          setState(() => _from = u);
                          _save();
                        },
                      ),
                    ],
                  ),
                ),

                // Swap
                Center(
                  child: IconButton(
                    icon: const Icon(Icons.swap_vert,
                        color: ZekaColors.cyan, size: 32),
                    onPressed: _swap,
                    tooltip: 'Swap',
                  ),
                ),

                // TO row
                _LabeledBlock(
                  label: tr(context, ref, 'to'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 12),
                          decoration: BoxDecoration(
                            color: ZekaColors.cyan.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: ZekaColors.cyan.withOpacity(0.3)),
                          ),
                          child: Text(
                            _result,
                            style: const TextStyle(
                              fontSize: 22,
                              fontFamily: 'monospace',
                              color: ZekaColors.cyan,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _UnitPicker(
                        units: _category.units,
                        selected: _to,
                        onChanged: (u) {
                          setState(() => _to = u);
                          _save();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Compact equation line
                if (_input.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${_input.text} ${_from.symbol}  =  $_result ${_to.symbol}',
                      style: const TextStyle(
                        color: ZekaColors.muted,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const Spacer(),

                // Hint footer
                Text(
                  '${_category.units.length} units · ${conversionCategories.length} categories',
                  style: const TextStyle(
                    color: ZekaColors.muted,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration() => InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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
          borderSide: const BorderSide(color: ZekaColors.cyan),
        ),
      );
}

class _LabeledBlock extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledBlock({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: ZekaColors.muted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  final List<Unit> units;
  final Unit selected;
  final void Function(Unit) onChanged;
  const _UnitPicker({
    required this.units,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String>(
        value: selected.symbol,
        isExpanded: true,
        items: units
            .map(
              (u) => DropdownMenuItem(
                value: u.symbol,
                child: Text(
                  '${u.name} (${u.symbol})',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          onChanged(units.firstWhere((u) => u.symbol == v));
        },
        dropdownColor: const Color(0xFF202036),
        style: const TextStyle(color: ZekaColors.text, fontSize: 12),
        iconEnabledColor: ZekaColors.cyan,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withOpacity(0.04),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12),
          ),
        ),
      ),
    );
  }
}
