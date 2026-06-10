import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';
import 'services/language_service.dart';
import 'services/policy_service.dart';
import 'services/user_storage.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow all orientations explicitly. Flutter's default behaviour
  // matches the OS but some plugins (notably image_picker on older
  // Android) ship a portrait lock; this overrides it so the
  // calculator + converter can go landscape on tablets / TVs.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {
    // No .env — fine. AI tab will show a configure-key message;
    // calculator + converter still work fully.
  }
  runApp(const ProviderScope(child: ZekaApp()));
}

class ZekaApp extends ConsumerWidget {
  const ZekaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final session = ref.watch(authProvider);
    // Push the latest remote policy into the storage layer on every
    // rebuild — cheap (just sets a field on a singleton) and means the
    // 50 MB / 30 d caps stay in sync once admin tunes them.
    UserStorage.instance.applyPolicy(ref.watch(policyProvider));
    return MaterialApp(
      title: 'Zeka',
      debugShowCheckedModeBanner: false,
      theme: ZekaTheme.dark,
      locale: Locale(lang.code),
      supportedLocales: const [
        Locale('en'),
        Locale('ur'),
        Locale('ar'),
        Locale('tr'),
        Locale('ru'),
        Locale('es'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Gate the app behind sign-in. Signed-in OR anonymous users go
      // straight to home; first-time users land on the sign-in screen.
      home: (session.isSignedIn || session.anonymous)
          ? const HomeScreen()
          : const SignInScreen(),
    );
  }
}
