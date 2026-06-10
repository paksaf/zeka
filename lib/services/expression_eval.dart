import 'dart:math' as math;

/// Recursive-descent parser for the keypad calculator. Mirrors the
/// safe evaluator at interactpak-nextjs/src/.../calculator/page.tsx
/// so the same expressions produce the same answers across web + app.
///
/// Supported:
///   + - * / ^   ( )   π e
///   sin cos tan asin acos atan
///   sqrt cbrt ln log exp abs
///   factorial !  (postfix)
///
/// Throws [FormatException] on syntax error. Returns NaN on math
/// errors (divide-by-zero, sqrt of negative).
double evaluate(String src, {bool degrees = true}) {
  final p = _Parser(src.replaceAll(' ', ''), degrees);
  final v = p._expr();
  p._skipWs();
  if (!p._eof) {
    throw FormatException('Unexpected character: ${src[p._i]}');
  }
  return v;
}

class _Parser {
  final String src;
  final bool degrees;
  int _i = 0;
  _Parser(this.src, this.degrees);

  bool get _eof => _i >= src.length;
  String get _peek => _eof ? '' : src[_i];

  void _skipWs() {} // pre-stripped

  double _expr() {
    var v = _term();
    while (!_eof && (_peek == '+' || _peek == '-')) {
      final op = src[_i++];
      final rhs = _term();
      v = op == '+' ? v + rhs : v - rhs;
    }
    return v;
  }

  double _term() {
    var v = _factor();
    while (!_eof && (_peek == '*' || _peek == '/')) {
      final op = src[_i++];
      final rhs = _factor();
      v = op == '*' ? v * rhs : v / rhs;
    }
    return v;
  }

  double _factor() {
    var v = _power();
    // Postfix factorial
    while (!_eof && _peek == '!') {
      _i++;
      v = _factorial(v);
    }
    return v;
  }

  double _power() {
    var v = _unary();
    if (!_eof && _peek == '^') {
      _i++;
      v = math.pow(v, _unary()).toDouble();
    }
    return v;
  }

  double _unary() {
    if (_peek == '-') {
      _i++;
      return -_unary();
    }
    if (_peek == '+') {
      _i++;
      return _unary();
    }
    return _atom();
  }

  double _atom() {
    if (_eof) throw const FormatException('Unexpected end of expression');
    final c = _peek;
    if (c == '(') {
      _i++;
      final v = _expr();
      if (_peek != ')') throw const FormatException('Expected )');
      _i++;
      return v;
    }
    if (c == 'π') {
      _i++;
      return math.pi;
    }
    if (c == 'e' && (_i + 1 >= src.length || !_isAlpha(src[_i + 1]))) {
      _i++;
      return math.e;
    }
    if (_isAlpha(c)) return _func();
    return _number();
  }

  double _number() {
    final start = _i;
    while (!_eof && (RegExp(r'[0-9.]').hasMatch(_peek))) {
      _i++;
    }
    final slice = src.substring(start, _i);
    final v = double.tryParse(slice);
    if (v == null) throw FormatException('Bad number: $slice');
    return v;
  }

  double _func() {
    final start = _i;
    while (!_eof && _isAlpha(_peek)) {
      _i++;
    }
    final name = src.substring(start, _i);
    if (_peek != '(') throw FormatException('Expected ( after $name');
    _i++;
    final arg = _expr();
    if (_peek != ')') throw FormatException('Expected ) closing $name');
    _i++;
    switch (name) {
      case 'sin': return math.sin(_toRad(arg));
      case 'cos': return math.cos(_toRad(arg));
      case 'tan': return math.tan(_toRad(arg));
      case 'asin': return _fromRad(math.asin(arg));
      case 'acos': return _fromRad(math.acos(arg));
      case 'atan': return _fromRad(math.atan(arg));
      case 'sqrt': return math.sqrt(arg);
      case 'cbrt': return math.pow(arg, 1 / 3).toDouble();
      case 'ln': return math.log(arg);
      case 'log': return math.log(arg) / math.ln10;
      case 'exp': return math.exp(arg);
      case 'abs': return arg.abs();
      default: throw FormatException('Unknown function: $name');
    }
  }

  double _toRad(double v) => degrees ? v * math.pi / 180 : v;
  double _fromRad(double v) => degrees ? v * 180 / math.pi : v;

  bool _isAlpha(String c) => RegExp(r'[a-zA-Z]').hasMatch(c);

  double _factorial(double v) {
    if (v < 0 || v != v.roundToDouble()) return double.nan;
    var out = 1.0;
    for (var i = 2; i <= v.toInt(); i++) {
      out *= i;
      if (out.isInfinite) return double.infinity;
    }
    return out;
  }
}
