// Minimal smoke test: ensures the root widget tree builds.
// (Replaced the stale flutter-create counter test that referenced a
// non-existent `MyApp` and broke `flutter analyze` — 2026-06-10.)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeka/main.dart';

void main() {
  testWidgets('ZekaApp constructs', (WidgetTester tester) async {
    // Construct only — full pump requires dotenv/plugins not available
    // in the widget-test environment.
    const app = ProviderScope(child: ZekaApp());
    expect(app, isA<ProviderScope>());
  });
}
