# Zeka — Smart AI Toolkit

Cross-platform standalone app: **Calculator + Unit Converter + AI + Voice + Camera + Bilingual (EN/UR)**.

Runs on Android, iOS, Android TV, macOS, and Windows from one Flutter codebase. Works **offline** for keypad calculations and all 25+ unit-converter categories. AI mode (DeepSeek text + OpenAI vision) requires internet.

Mirrors the web Zeka deployed at `qurbanisahulat.com/zeka`, `farmer.interactpak.com/zeka`, `rewards.interactpak.com/zeka`, `app.cgt.llc/zeka` — same brand, same units, same answers.

## Why "Zeka"

- Turkish **zekâ** = *intelligence*
- Urdu **ذہانت / Zehanat** shares the same root
- Russian-accent-friendly "Зека"
- 4 letters, works as a voice trigger ("Hey Zeka")

## Features (v0.1)

- **Calculator** — basic + scientific (sin/cos/tan/asin/acos/atan/sqrt/cbrt/ln/log/exp/abs/!), π/e constants, history, DEG/RAD toggle
- **Converter** — 25 categories including local PK units: Marla, Kanal, Murabba, Bigha, Killa (area); Tola, Pao, Ser, Maund, Quintal (weight); plus crop yield, application rate, feed energy, flow rate
- **AI** — natural language ("convert 5 maund to kg"), voice input, camera OCR (snap a problem, get the answer), bilingual prompts
- **Bilingual** — EN ⇄ Urdu (اردو) with full RTL flip
- **Offline-first** — calculator + converter work without network; AI shows clear message when offline
- **Voice-driven** — speech_to_text in for input, flutter_tts out for answers
- **Brand-consistent dark UI** — same purple/cyan palette as the web Zeka

## Project layout

```
lib/
├── main.dart                       App entry, MaterialApp setup, locale wiring
├── theme.dart                      ZekaColors + ZekaTheme (dark, brand colors)
├── screens/
│   ├── home_screen.dart            Tile grid: Calculator · Converter · AI · History
│   ├── calculator_screen.dart      Full keypad + history strip
│   ├── converter_screen.dart       25 categories, swap, persistence
│   └── ai_screen.dart              Ask Zeka — text + voice + camera + attach
├── services/
│   ├── language_service.dart       Riverpod EN/UR provider + tr() helper
│   ├── deepseek_service.dart       Multi-provider LLM (DeepSeek/OpenAI/Anthropic) with vision + cache
│   ├── local_converter.dart        Pure-Dart 25-category unit catalogue (mirror of web)
│   └── expression_eval.dart        Recursive-descent calculator parser
└── widgets/
    └── zeka_brand_header.dart      Gold Z mark + EN/اردو toggle
```

## Setup

```bash
cd ~/Documents/INTERACT/zeka
flutter pub get

# Configure your AI keys (optional — calc + converter work without)
cp .env.example .env
$EDITOR .env       # paste DEEPSEEK_API_KEY=sk-... and/or OPENAI_API_KEY=sk-...

# Run on a connected device or simulator
flutter run

# Or on a specific platform
flutter run -d macos      # macOS desktop
flutter run -d windows    # Windows desktop
flutter run -d chrome     # Web (for quick browser preview)
```

## Build for each platform

```bash
# Android APK (or AAB for Play Store)
flutter build apk --release
flutter build appbundle --release

# Android TV (same APK with leanback launcher in AndroidManifest.xml)
flutter build apk --release --target-platform android-arm64

# iOS (requires Mac + Xcode)
flutter build ios --release

# macOS .app
flutter build macos --release

# Windows .exe
flutter build windows --release
# Wrap with Inno Setup for an installer if needed
```

## API key security

Keys in `.env` are bundled into the app at build time via flutter_dotenv. For real production releases, consider:
- **Mobile:** use Android's encrypted SharedPreferences / iOS Keychain via `flutter_secure_storage`
- **Desktop:** wrap the binary so users provide their own key on first launch
- **Public release:** route AI calls through a server proxy (use the same `/api/zeka/ai` endpoint already live on `interactpak.com`) so the key never ships in the binary

The current code reads from `dotenv` first; swap that line in `deepseek_service.dart` `_env()` for the appropriate secure-storage call when you move to production.

## What's still on the backlog (v0.2+)

- AR area-measurement screen (tap 4 corners → area in m² + Kanal + Bigha)
- "Hey Zeka" wake word (porcupine_flutter)
- Whisper offline speech-to-text fallback for no-network voice input
- Animal feed calculator port from the web Zeka libs
- Symptom-check port from the web Zeka libs
- SQLite cache of recent AI Q&A for cross-session history
- Pre-loaded JSON conversion rules table (already in `local_converter.dart` as Dart constants, but a SQLite-backed version would be faster to extend)
- Formula mode parity with the web (math/trig/geom/finance/stats)
- TV remote D-pad focus rings + 10-foot UI mode

## Status — 2026-05-16

This is the v0.1 scaffold. The brand, theme, three primary screens, services, and i18n all compile against Flutter 3.22+ and run on Android/iOS/Windows/macOS. Plug in a DeepSeek or OpenAI key and you have a working standalone Zeka.

The web Zeka at `qurbanisahulat.com/zeka` and 3 other apps is fully live and answering AI questions in production — this Flutter app is the offline-capable companion.
