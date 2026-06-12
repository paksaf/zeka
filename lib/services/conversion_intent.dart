// SPDX-License-Identifier: AGPL-3.0
//
// ConversionIntentParser (market-fit Gate B, 2026-06-12) — Zeka's signature
// feature is EXACT local-PK unit conversions (Maund, Marla, Tola, Kanal…).
// LLMs routinely get these wrong (a Pakistani maund is 37.3242 kg, not the
// Indian/imperial value), and a converter that returns wrong numbers is dead
// on arrival. So before any AI call, we try to parse "X <unit> to <unit>"
// and answer it DETERMINISTICALLY from local_converter — exact, offline,
// instant, free. Only genuine free-form questions fall through to the LLM.

import 'deepseek_service.dart' show AiResult;
import 'local_converter.dart';

class ConversionIntentParser {
  ConversionIntentParser() {
    // Build an alias → (category, unit) index across all categories once.
    for (final cat in conversionCategories) {
      for (final u in cat.units) {
        for (final a in _aliasesFor(u)) {
          _index.putIfAbsent(a, () => (cat, u));
        }
      }
    }
  }

  final Map<String, (ConversionCategory, Unit)> _index = {};

  /// Returns an exact AiResult if [question] is a recognizable unit
  /// conversion, else null (caller falls through to the LLM).
  AiResult? tryParse(String question) {
    final q = question.toLowerCase().trim();
    // Patterns: "5 maund to kg" · "convert 5 maund to kg" · "5 maund in kg"
    final m = RegExp(
            r'(?:convert\s+)?(-?\d+(?:\.\d+)?)\s*([a-z²³\.\(\)\s]+?)\s+(?:to|in|into|=)\s+([a-z²³\.\(\)\s]+)$')
        .firstMatch(q);
    if (m == null) return null;
    final value = double.tryParse(m.group(1)!);
    if (value == null) return null;
    final from = _resolve(m.group(2)!);
    final to = _resolve(m.group(3)!);
    if (from == null || to == null) return null;
    // Both units must share a category to be convertible.
    if (from.$1.id != to.$1.id) return null;

    final out = convert(value, from.$2, to.$2, from.$1);
    final result = formatResult(out);
    final answer =
        '${formatResult(value)} ${from.$2.symbol} = $result ${to.$2.symbol}';
    final steps = <String>[
      'Category: ${from.$1.name}',
      if (from.$1.id != 'temperature')
        '1 ${from.$2.symbol} = ${formatResult(from.$2.ratioToBase / to.$2.ratioToBase)} ${to.$2.symbol}',
      'Exact local value (offline, no AI) — Zeka unit catalogue',
    ];
    return AiResult(answer: answer, steps: steps, provider: 'local');
  }

  (ConversionCategory, Unit)? _resolve(String raw) {
    final key = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return _index[key] ?? _index[key.replaceAll(' ', '')] ?? _index[_depluralize(key)];
  }

  String _depluralize(String s) => s.endsWith('s') ? s.substring(0, s.length - 1) : s;

  /// Common spoken/typed aliases per unit (English + PK names).
  Iterable<String> _aliasesFor(Unit u) {
    final base = <String>{u.name.toLowerCase(), u.symbol.toLowerCase()};
    // strip qualifiers like "(PK)" / "(Punjab)" from the name
    base.add(u.name.toLowerCase().replaceAll(RegExp(r'\s*\(.*?\)'), '').trim());
    const extra = {
      'kg': ['kilogram', 'kilograms', 'kilo', 'kilos', 'kgs'],
      'g': ['gram', 'grams', 'gm'],
      'mg': ['milligram', 'milligrams'],
      'lb': ['pound', 'pounds', 'lbs'],
      'maund': ['maund', 'mun', 'mann', 'mn'],
      'ser': ['seer', 'ser'],
      'tola': ['tola', 'tolas'],
      'pao': ['pao', 'paav'],
      'q': ['quintal', 'quintals'],
      'm': ['meter', 'metre', 'meters', 'metres'],
      'km': ['kilometer', 'kilometre', 'kilometers'],
      'cm': ['centimeter', 'centimetre'],
      'mm': ['millimeter', 'millimetre'],
      'ft': ['foot', 'feet'],
      'ac': ['acre', 'acres'],
      'marla': ['marla', 'marlas'],
      'kanal': ['kanal', 'kanals', 'canal'],
      'killa': ['killa', 'kila', 'killas'],
      'bigha': ['bigha', 'beegha'],
      'murabba': ['murabba', 'moraba'],
    };
    if (extra.containsKey(u.symbol.toLowerCase())) {
      base.addAll(extra[u.symbol.toLowerCase()]!);
    }
    return base.where((s) => s.isNotEmpty);
  }
}
