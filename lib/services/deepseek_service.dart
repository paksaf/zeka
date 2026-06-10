import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Multi-provider LLM client (DeepSeek text → OpenAI text+vision →
/// Anthropic vision) mirroring the web /api/zeka/ai server route.
///
/// Picks the first configured provider. Caches text-only responses
/// in-memory (per session) to avoid burning tokens on repeats —
/// the calculator AI sees the same question many times in practice.
class DeepSeekService {
  static const _systemPrompt =
      "You are a precise calculator assistant. Each question is a maths "
      "or unit-conversion problem in natural language. Reply with up to "
      "6 short numbered steps then a final line starting with '= ' and "
      "the answer (with unit if implied). For Pakistan land/weight units: "
      "1 Maund (PK) = 40 kg, 1 Kanal = 505.857 m², 1 Marla = 25.2929 m², "
      "1 Bigha (Punjab) = 2530 m². No extra commentary, no emoji. If the "
      "question is not a maths/conversion problem, reply '= UNSUPPORTED'.";

  static const _imageSystemSuffix =
      "An image is attached. First scan for printed/handwritten text or "
      "digits. If there is none readable, reply EXACTLY '= NO_TEXT_DETECTED'. "
      "Otherwise transcribe the problem and solve it.";

  final Map<String, AiResult> _cache = {};

  /// The server proxy. Production APKs ship without API keys, so the
  /// app routes every AI call through /api/zeka/ai on interactpak.com
  /// where the keys actually live. This keeps secrets off-device.
  // Canonical host — apex redirects to www and Dart's http drops the
  // POST body across 301 (manifests as "Network error" on the client).
  static const _serverProxy = 'https://www.interactpak.com/api/zeka/ai';

  /// Returns structured result: steps + answer + provider. Throws on
  /// no-provider-configured or HTTP error so the UI can show a clear
  /// error message.
  Future<AiResult> ask(String question, {List<int>? imageBytes, String? imageMime}) async {
    final cacheKey = imageBytes == null ? 'text:$question' : null;
    if (cacheKey != null && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // PRIMARY PATH — proxy through the INTERACT VPS. Keys live there.
    // Falls through to direct provider calls only if the proxy errors
    // out AND a local key exists (covers dev / offline debugging).
    try {
      final result = await _askViaProxy(question,
          imageBytes: imageBytes, imageMime: imageMime);
      if (cacheKey != null) _cache[cacheKey] = result;
      return result;
    } on AiUnconfiguredException {
      // Server says no key — try local fallback below if we have one.
    } on AiNoTextException {
      rethrow;
    } on AiUnsupportedException {
      rethrow;
    } catch (e) {
      // Proxy down or transport error — try local fallback if we can.
      debugPrint('Zeka AI proxy failed, will try local fallback: $e');
    }

    final ds = _env('DEEPSEEK_API_KEY');
    final oa = _env('OPENAI_API_KEY');
    final an = _env('ANTHROPIC_API_KEY');

    String raw;
    String provider;
    if (imageBytes != null) {
      // Image path — DeepSeek doesn't support vision (yet); use OpenAI
      // gpt-4o-mini or Claude Haiku.
      if (oa != null) {
        raw = await _callOpenAI(oa, 'gpt-4o-mini', question,
            imageBytes: imageBytes, imageMime: imageMime ?? 'image/jpeg');
        provider = 'openai';
      } else if (an != null) {
        raw = await _callAnthropic(an, question,
            imageBytes: imageBytes, imageMime: imageMime ?? 'image/jpeg');
        provider = 'anthropic';
      } else {
        throw const AiUnconfiguredException('Vision needs OPENAI_API_KEY or ANTHROPIC_API_KEY');
      }
    } else {
      // Text path — DeepSeek is cheapest, prefer it
      if (ds != null) {
        raw = await _callOpenAICompatible('https://api.deepseek.com/v1/chat/completions',
            ds, 'deepseek-chat', question);
        provider = 'deepseek';
      } else if (oa != null) {
        raw = await _callOpenAI(oa, 'gpt-4o-mini', question);
        provider = 'openai';
      } else if (an != null) {
        raw = await _callAnthropic(an, question);
        provider = 'anthropic';
      } else {
        throw const AiUnconfiguredException('Set DEEPSEEK_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY');
      }
    }

    final result = _parse(raw, provider);
    if (cacheKey != null) _cache[cacheKey] = result;
    return result;
  }

  // ── Provider implementations ──────────────────────────────────────

  Future<String> _callOpenAICompatible(
      String url, String key, String model, String question) async {
    final res = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': question},
            ],
            'temperature': 0.1,
            'max_tokens': 300,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw AiHttpException(res.statusCode, res.body);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (((j['choices'] as List).first as Map)['message']['content'] as String).trim();
  }

  Future<String> _callOpenAI(String key, String model, String question,
      {List<int>? imageBytes, String? imageMime}) async {
    final List<dynamic> content;
    if (imageBytes != null && imageMime != null) {
      content = [
        {'type': 'text', 'text': question},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:$imageMime;base64,${base64Encode(imageBytes)}',
            'detail': 'low',
          },
        },
      ];
    } else {
      content = [
        {'type': 'text', 'text': question}
      ];
    }
    final sys = imageBytes != null ? '$_systemPrompt $_imageSystemSuffix' : _systemPrompt;
    final res = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': sys},
              {'role': 'user', 'content': content},
            ],
            'temperature': 0.1,
            'max_tokens': 400,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw AiHttpException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (((j['choices'] as List).first as Map)['message']['content'] as String).trim();
  }

  Future<String> _callAnthropic(String key, String question,
      {List<int>? imageBytes, String? imageMime}) async {
    final sys = imageBytes != null ? '$_systemPrompt $_imageSystemSuffix' : _systemPrompt;
    final List<Map<String, dynamic>> content = [];
    if (imageBytes != null && imageMime != null) {
      content.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': imageMime,
          'data': base64Encode(imageBytes),
        }
      });
    }
    content.add({'type': 'text', 'text': question});
    final res = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode({
            'model': 'claude-haiku-4-5-20251001',
            'max_tokens': 400,
            'system': sys,
            'messages': [
              {'role': 'user', 'content': content}
            ],
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw AiHttpException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final blocks = j['content'] as List;
    final text = blocks.firstWhere((b) => b['type'] == 'text', orElse: () => null);
    return text == null ? '' : (text['text'] as String).trim();
  }

  /// Call the INTERACT server proxy at /api/zeka/ai. The proxy already
  /// returns `{ok, answer, steps, provider}` so we don't need to
  /// re-parse the raw LLM text. Error cases mapped to typed exceptions
  /// so the UI can show the right message without string-matching.
  Future<AiResult> _askViaProxy(
    String question, {
    List<int>? imageBytes,
    String? imageMime,
  }) async {
    final body = <String, dynamic>{'question': question};
    if (imageBytes != null) {
      body['imageBase64'] = base64Encode(imageBytes);
      body['imageMime'] = imageMime ?? 'image/png';
    }
    final res = await http
        .post(
          Uri.parse(_serverProxy),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 35));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200 && j['ok'] == true) {
      return AiResult(
        steps: ((j['steps'] as List?) ?? const []).cast<String>(),
        answer: (j['answer'] as String?) ?? '—',
        provider: (j['provider'] as String?) ?? 'server',
      );
    }
    // Map error codes to typed exceptions matching the legacy local path.
    final err = (j['error'] as String?) ?? 'unknown';
    if (err == 'no_text_in_image') throw const AiNoTextException();
    if (err == 'not_a_math_problem') throw const AiUnsupportedException();
    if (err == 'ai_not_configured') {
      throw AiUnconfiguredException(
          (j['detail'] as String?) ?? 'AI not configured on server');
    }
    throw AiHttpException(res.statusCode, res.body);
  }

  AiResult _parse(String content, String provider) {
    if (content.contains('NO_TEXT_DETECTED')) {
      throw const AiNoTextException();
    }
    if (content.contains('UNSUPPORTED')) {
      throw const AiUnsupportedException();
    }
    final lines = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final steps = <String>[];
    String answer = '';
    for (final line in lines) {
      if (line.startsWith('=')) {
        answer = line.replaceFirst(RegExp(r'^=+\s*'), '');
      } else {
        steps.add(line);
      }
    }
    if (answer.isEmpty && lines.isNotEmpty) answer = lines.last;
    return AiResult(answer: answer, steps: steps, provider: provider);
  }

  String? _env(String key) {
    final v = dotenv.maybeGet(key) ?? const String.fromEnvironment('').trim();
    if (v.isEmpty) return null;
    // Reject obvious placeholder values.
    if (v.startsWith('<') || v.contains('...')) return null;
    return v;
  }

  bool get isConfigured => _env('DEEPSEEK_API_KEY') != null ||
      _env('OPENAI_API_KEY') != null ||
      _env('ANTHROPIC_API_KEY') != null;

  bool get supportsVision => _env('OPENAI_API_KEY') != null || _env('ANTHROPIC_API_KEY') != null;
}

@immutable
class AiResult {
  final String answer;
  final List<String> steps;
  final String provider;
  const AiResult({required this.answer, required this.steps, required this.provider});
}

class AiUnconfiguredException implements Exception {
  final String message;
  const AiUnconfiguredException(this.message);
  @override
  String toString() => message;
}

class AiHttpException implements Exception {
  final int status;
  final String body;
  AiHttpException(this.status, this.body);
  @override
  String toString() => 'ai_error_$status';
}

class AiNoTextException implements Exception {
  const AiNoTextException();
}

class AiUnsupportedException implements Exception {
  const AiUnsupportedException();
}
