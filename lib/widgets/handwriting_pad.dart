import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/deepseek_service.dart';
import '../theme.dart';

/// Free-form handwriting / drawing pad. The user writes their problem
/// with finger / mouse / stylus, then submits — we render the strokes
/// to a PNG and feed it to the vision LLM (gpt-4o-mini / Claude Haiku)
/// for transcription + solving. The interactpak Pro app already does
/// proper handwriting recognition; this is the lightweight equivalent
/// until that engine is exported as a Flutter plugin.
///
/// Returns the recognised text via Navigator.pop(context, recognised),
/// so the caller can drop it into the AI sheet's text field.
class HandwritingPad extends StatefulWidget {
  const HandwritingPad({super.key});
  @override
  State<HandwritingPad> createState() => _HandwritingPadState();
}

class _HandwritingPadState extends State<HandwritingPad> {
  final List<List<Offset>> _strokes = [];
  final GlobalKey _canvasKey = GlobalKey();
  bool _busy = false;
  String? _error;

  void _startStroke(Offset p) => setState(() => _strokes.add([p]));
  void _appendStroke(Offset p) => setState(() => _strokes.last.add(p));
  void _clear() => setState(() => _strokes.clear());

  Future<void> _recogniseAndReturn() async {
    if (_strokes.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Render strokes to a PNG at pixelRatio: 2.5. Earlier we tried
      // 1.5 to save bandwidth but the vision LLM returned NO_TEXT for
      // 8+8 drawings — thin 3-px strokes downsample to invisibility.
      // Combined with the thicker stroke width in _StrokePainter
      // (now 7 px), the AI reliably sees the ink.
      final boundary =
          _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final svc = DeepSeekService();
      // Transcription request — the server's system prompt sees the
      // word "transcribe" + image suffix and returns the recognised
      // text in the `answer` line.
      final result = await svc.ask(
        'TRANSCRIBE ONLY: read the handwritten text, digits, or math '
        'expression in this image exactly as written. Return just the '
        'transcribed characters on the "= " line, no commentary, no '
        'evaluation, no solving. Preserve operators (+, -, ×, ÷) and '
        'symbols.',
        imageBytes: bytes,
        imageMime: 'image/png',
      );
      final transcribed = result.answer.replaceFirst(RegExp(r'^=\s*'), '').trim();
      if (transcribed.isEmpty) {
        setState(() {
          _error = "Couldn't read the handwriting. Try writing larger or clearer.";
          _busy = false;
        });
        return;
      }
      if (mounted) Navigator.pop(context, transcribed);
    } on AiUnconfiguredException catch (e) {
      setState(() {
        _error = e.message.isNotEmpty
            ? e.message
            : 'AI not configured on the server. Contact admin.';
        _busy = false;
      });
    } on AiNoTextException {
      setState(() {
        _error =
            "We couldn't see any text in your drawing. Try writing larger.";
        _busy = false;
      });
    } on AiHttpException catch (e) {
      setState(() {
        _error = e.status == 502 || e.status == 503
            ? "AI server is busy. Try again in a moment."
            : "Couldn't read the handwriting (server returned ${e.status}).";
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = "Couldn't read the handwriting. Network issue — please try again.";
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write the problem'),
        backgroundColor: const Color(0xFF1A1A2E),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: ZekaColors.muted),
            tooltip: 'Clear',
            onPressed: _strokes.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _canvasKey,
              child: Container(
                color: Colors.white,
                width: double.infinity,
                child: GestureDetector(
                  onPanStart: (d) => _startStroke(d.localPosition),
                  onPanUpdate: (d) => _appendStroke(d.localPosition),
                  child: CustomPaint(
                    painter: _StrokePainter(_strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          Container(
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Write your math or words above',
                    style: const TextStyle(color: ZekaColors.muted),
                  ),
                ),
                FilledButton.icon(
                  onPressed: (_busy || _strokes.isEmpty) ? null : _recogniseAndReturn,
                  icon: _busy
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(_busy ? 'Reading…' : 'Use this'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0B0B1A)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      // 7-px strokes look like a marker on screen but they survive
      // downsampling to vision-LLM input dimensions. 3 px was too thin
      // — strokes disappeared and the model returned NO_TEXT_DETECTED.
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.isNotEmpty) {
          // Match the new stroke thickness so dots survive
          // downsampling alongside the strokes.
          canvas.drawCircle(stroke.first, 4, paint..style = PaintingStyle.fill);
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => old.strokes != strokes;
}
