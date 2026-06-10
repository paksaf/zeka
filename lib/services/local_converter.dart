/// Pure-Dart unit conversion catalogue — ported verbatim from
/// src/lib/unit-conversion.ts so the offline experience matches the
/// web exactly. Same 25 categories incl. local PK units (Marla,
/// Kanal, Murabba, Bigha, Killa, Tola, Pao, Ser, Maund, Quintal).
import 'dart:math' as math;

class Unit {
  final String name;
  final String symbol;
  /// Multiply a value in this unit by ratioToBase to get the base-unit value.
  /// Unused for temperature (handled specially).
  final double ratioToBase;
  const Unit(this.name, this.symbol, this.ratioToBase);
}

class ConversionCategory {
  final String id;
  final String name;
  final List<Unit> units;
  const ConversionCategory(this.id, this.name, this.units);
}

double convert(double value, Unit from, Unit to, ConversionCategory category) {
  if (from == to) return value;
  if (category.id == 'temperature') {
    double c;
    switch (from.symbol) {
      case '°C': c = value; break;
      case '°F': c = (value - 32) * 5 / 9; break;
      case 'K':  c = value - 273.15; break;
      default:   c = value;
    }
    switch (to.symbol) {
      case '°C': return c;
      case '°F': return c * 9 / 5 + 32;
      case 'K':  return c + 273.15;
      default:   return c;
    }
  }
  final inBase = value * from.ratioToBase;
  return inBase / to.ratioToBase;
}

String formatResult(double n) {
  if (n.isInfinite || n.isNaN) return '—';
  final abs = n.abs();
  if (abs >= 1e15 || (abs < 1e-4 && n != 0)) {
    return n.toStringAsExponential(6).replaceAll(RegExp(r'\.?0+e'), 'e');
  }
  // Trim trailing zeros and keep up to 6 decimals.
  var s = n.toStringAsFixed(6);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

const conversionCategories = <ConversionCategory>[
  ConversionCategory('length', 'Length', [
    Unit('Metre', 'm', 1),
    Unit('Kilometre', 'km', 1000),
    Unit('Centimetre', 'cm', 0.01),
    Unit('Millimetre', 'mm', 0.001),
    Unit('Inch', 'in', 0.0254),
    Unit('Foot', 'ft', 0.3048),
    Unit('Yard', 'yd', 0.9144),
    Unit('Mile', 'mi', 1609.344),
    Unit('Nautical mile', 'nmi', 1852),
  ]),
  ConversionCategory('area', 'Area', [
    Unit('Square metre', 'm²', 1),
    Unit('Square kilometre', 'km²', 1e6),
    Unit('Square centimetre', 'cm²', 0.0001),
    Unit('Square mile', 'mi²', 2589988.110336),
    Unit('Square foot', 'ft²', 0.09290304),
    Unit('Square inch', 'in²', 0.00064516),
    Unit('Acre', 'ac', 4046.8564224),
    Unit('Hectare', 'ha', 10000),
    Unit('Marla (Punjab)', 'marla', 25.2929),
    Unit('Kanal', 'kanal', 505.857),
    Unit('Murabba', 'murabba', 101171.4106),
    Unit('Bigha (Punjab)', 'bigha', 2530),
    Unit('Killa', 'killa', 4046.8564224),
  ]),
  ConversionCategory('volume', 'Volume', [
    Unit('Litre', 'L', 1),
    Unit('Millilitre', 'mL', 0.001),
    Unit('Cubic metre', 'm³', 1000),
    Unit('Gallon (US)', 'gal', 3.785411784),
    Unit('Gallon (UK)', 'gal UK', 4.54609),
    Unit('Quart (US)', 'qt', 0.946352946),
    Unit('Pint (US)', 'pt', 0.473176473),
    Unit('Cup (US)', 'cup', 0.2365882365),
    Unit('Fluid ounce (US)', 'fl oz', 0.0295735296),
    Unit('Tablespoon', 'tbsp', 0.01478676478125),
    Unit('Teaspoon', 'tsp', 0.00492892159375),
  ]),
  ConversionCategory('weight', 'Weight', [
    Unit('Kilogram', 'kg', 1),
    Unit('Gram', 'g', 0.001),
    Unit('Milligram', 'mg', 1e-6),
    Unit('Pound', 'lb', 0.45359237),
    Unit('Ounce', 'oz', 0.028349523125),
    Unit('Stone', 'st', 6.35029318),
    Unit('Metric ton', 't', 1000),
    Unit('US ton', 'ton US', 907.18474),
    Unit('Tola', 'tola', 0.0116638),
    Unit('Pao', 'pao', 0.25),
    Unit('Ser (PK)', 'ser', 0.93310),
    Unit('Maund (PK)', 'maund', 37.3242),
    Unit('Quintal', 'q', 100),
  ]),
  ConversionCategory('temperature', 'Temperature', [
    Unit('Celsius', '°C', 1),
    Unit('Fahrenheit', '°F', 1),
    Unit('Kelvin', 'K', 1),
  ]),
  ConversionCategory('time', 'Time', [
    Unit('Second', 's', 1),
    Unit('Millisecond', 'ms', 0.001),
    Unit('Minute', 'min', 60),
    Unit('Hour', 'h', 3600),
    Unit('Day', 'd', 86400),
    Unit('Week', 'wk', 604800),
    Unit('Month (30d)', 'mo', 2592000),
    Unit('Year (365d)', 'yr', 31536000),
  ]),
  ConversionCategory('speed', 'Speed', [
    Unit('Metre / second', 'm/s', 1),
    Unit('Kilometre / hour', 'km/h', 0.2777777778),
    Unit('Mile / hour', 'mph', 0.44704),
    Unit('Foot / second', 'ft/s', 0.3048),
    Unit('Knot', 'kn', 0.5144444444),
  ]),
  ConversionCategory('pressure', 'Pressure', [
    Unit('Pascal', 'Pa', 1),
    Unit('Kilopascal', 'kPa', 1000),
    Unit('Megapascal', 'MPa', 1e6),
    Unit('Bar', 'bar', 100000),
    Unit('Atmosphere', 'atm', 101325),
    Unit('PSI', 'psi', 6894.757293168),
    Unit('mmHg / Torr', 'mmHg', 133.322387415),
  ]),
  ConversionCategory('energy', 'Energy', [
    Unit('Joule', 'J', 1),
    Unit('Kilojoule', 'kJ', 1000),
    Unit('Megajoule', 'MJ', 1e6),
    Unit('Calorie', 'cal', 4.184),
    Unit('Kilocalorie', 'kcal', 4184),
    Unit('Watt-hour', 'Wh', 3600),
    Unit('Kilowatt-hour', 'kWh', 3.6e6),
  ]),
  ConversionCategory('yield', 'Crop yield', [
    Unit('Kilogram / hectare', 'kg/ha', 1),
    Unit('Tonne / hectare', 't/ha', 1000),
    Unit('Maund (PK) / acre', 'md/ac', 9.222),
    Unit('Maund (PK) / kanal', 'md/kanal', 73.79),
    Unit('Pound / acre', 'lb/ac', 1.12085),
    Unit('Bushel (wheat) / acre', 'bu/ac', 67.25),
    Unit('Kilogram / acre', 'kg/ac', 2.4710538),
  ]),
  ConversionCategory('flow', 'Flow rate', [
    Unit('Litre / second', 'L/s', 1),
    Unit('Litre / minute', 'L/min', 0.0166667),
    Unit('Litre / hour', 'L/h', 0.0002778),
    Unit('Cubic metre / hour', 'm³/h', 0.2777778),
    Unit('Gallon (US) / minute', 'gpm', 0.0630902),
    Unit('Acre-foot / day', 'ac-ft/d', 14.27641),
  ]),
];

/// Lookup by id, fallback to length.
ConversionCategory categoryById(String id) =>
    conversionCategories.firstWhere((c) => c.id == id, orElse: () => conversionCategories.first);
