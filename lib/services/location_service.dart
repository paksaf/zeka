import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// Derives a "local context" snapshot from the device — current time,
/// timezone, detected city, today's date, and (when available) current
/// outdoor temperature.
///
/// The whole point: when the user opens Zeka and sees "Karachi · 31°C
/// · 4:18 PM" at the top, they know Zeka is location-aware. That
/// builds trust before they even ask a question.
///
/// We deliberately do NOT request GPS — that needs runtime permission
/// and a geocoding service, both of which slow first launch. Instead
/// we derive city + lat/long from the device's timezone (a single
/// constant lookup, zero network), and call Open-Meteo (free, no key)
/// for the temperature. If the user's device is on "Etc/UTC" or any
/// untyped zone, we just show time-only and skip the weather chip.
class LocalContext {
  final DateTime now;
  final String city;
  final String countryCode;
  final String? temperatureC;
  final String timezone;

  const LocalContext({
    required this.now,
    required this.city,
    required this.countryCode,
    required this.timezone,
    this.temperatureC,
  });

  String get formattedTime => DateFormat('h:mm a').format(now);
  String get formattedDate => DateFormat('EEE, d MMM').format(now);
}

class LocationService {
  /// Cached LocalContext so the weather fetch only runs once per session.
  LocalContext? _cached;

  /// Returns the current snapshot. Live time is always re-computed; the
  /// city + temperature are cached.
  Future<LocalContext> snapshot() async {
    final now = DateTime.now();
    if (_cached != null) {
      return LocalContext(
        now: now,
        city: _cached!.city,
        countryCode: _cached!.countryCode,
        timezone: _cached!.timezone,
        temperatureC: _cached!.temperatureC,
      );
    }
    final tz = _deviceTimezone();
    final cityRow = _timezoneToCity[tz] ?? const _City('Local', '', 0, 0);
    String? temp;
    if (cityRow.lat != 0 || cityRow.lon != 0) {
      temp = await _fetchTemperature(cityRow.lat, cityRow.lon);
    }
    final ctx = LocalContext(
      now: now,
      city: cityRow.name,
      countryCode: cityRow.country,
      timezone: tz,
      temperatureC: temp,
    );
    _cached = ctx;
    return ctx;
  }

  /// Cheap timezone read. On most platforms this returns the IANA
  /// name (e.g. "Asia/Karachi"). On the web we fall through to the
  /// browser Intl API via a JS interop later if we ever need it; for
  /// now `DateTime.now().timeZoneName` is good enough.
  String _deviceTimezone() {
    try {
      // The local name is more useful than the offset for our lookup.
      // On macOS / iOS / Android this returns the IANA name; on Windows
      // it can return a Windows zone — both are mapped below.
      return DateTime.now().timeZoneName;
    } catch (_) {
      return 'UTC';
    }
  }

  Future<String?> _fetchTemperature(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final t = (j['current'] as Map<String, dynamic>?)?['temperature_2m'];
      if (t is num) return '${t.toStringAsFixed(0)}°C';
    } catch (_) {
      // Offline or DNS blocked — fall through and skip the chip.
    }
    return null;
  }
}

/// Compact timezone → city table for the most common IANA zones in our
/// user base. Lat/lon are city-center values used as the weather query
/// coordinates. We can extend this list anytime; missing zones just
/// render "Local" without a weather chip, which is graceful.
const Map<String, _City> _timezoneToCity = {
  'Asia/Karachi':     _City('Karachi',     'PK', 24.86, 67.01),
  'Asia/Lahore':      _City('Lahore',      'PK', 31.55, 74.34),
  'Asia/Islamabad':   _City('Islamabad',   'PK', 33.68, 73.05),
  'Asia/Kolkata':     _City('Delhi',       'IN', 28.61, 77.21),
  'Asia/Dubai':       _City('Dubai',       'AE', 25.20, 55.27),
  'Asia/Riyadh':      _City('Riyadh',      'SA', 24.71, 46.68),
  'Asia/Istanbul':    _City('Istanbul',    'TR', 41.01, 28.98),
  'Europe/Istanbul':  _City('Istanbul',    'TR', 41.01, 28.98),
  'Europe/Moscow':    _City('Moscow',      'RU', 55.75, 37.62),
  'Europe/London':    _City('London',      'GB', 51.51, -0.13),
  'Europe/Madrid':    _City('Madrid',      'ES', 40.42, -3.70),
  'America/New_York': _City('New York',    'US', 40.71, -74.01),
  'America/Los_Angeles': _City('Los Angeles', 'US', 34.05, -118.24),
  // Common short labels (DateTime.timeZoneName returns these on
  // some platforms instead of the IANA tag).
  'PKT':              _City('Karachi',     'PK', 24.86, 67.01),
  'GMT':              _City('London',      'GB', 51.51, -0.13),
  'UTC':              _City('UTC',         '',   0, 0),
  'IST':              _City('Delhi',       'IN', 28.61, 77.21),
  'EST':              _City('New York',    'US', 40.71, -74.01),
  'PST':              _City('Los Angeles', 'US', 34.05, -118.24),
  'CET':              _City('Madrid',      'ES', 40.42, -3.70),
  'MSK':              _City('Moscow',      'RU', 55.75, 37.62),
  'TRT':              _City('Istanbul',    'TR', 41.01, 28.98),
};

class _City {
  final String name;
  final String country;
  final double lat;
  final double lon;
  const _City(this.name, this.country, this.lat, this.lon);
}
