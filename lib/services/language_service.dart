import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Languages supported in the Zeka app surface. Adding more is a
/// matter of dropping new entries into [_strings] below and adding
/// the enum value here. Speech recognition + TTS automatically pick
/// up the matching locale (see [speechLocale] / [ttsLocale]).
enum ZekaLang { en, ur, ar, tr, ru, es }

extension ZekaLangX on ZekaLang {
  String get code => name;

  /// Right-to-left? Drives Flutter's Directionality wrapping.
  bool get isRtl => this == ZekaLang.ur || this == ZekaLang.ar;

  /// Native display name (used in the picker).
  String get nativeName {
    switch (this) {
      case ZekaLang.en: return 'English';
      case ZekaLang.ur: return 'اردو';
      case ZekaLang.ar: return 'العربية';
      case ZekaLang.tr: return 'Türkçe';
      case ZekaLang.ru: return 'Русский';
      case ZekaLang.es: return 'Español';
    }
  }

  /// English display name (used as a sublabel in the picker so RTL
  /// users can still identify which language is which).
  String get englishName {
    switch (this) {
      case ZekaLang.en: return 'English';
      case ZekaLang.ur: return 'Urdu';
      case ZekaLang.ar: return 'Arabic';
      case ZekaLang.tr: return 'Turkish';
      case ZekaLang.ru: return 'Russian';
      case ZekaLang.es: return 'Spanish';
    }
  }

  /// Flag emoji — works on every modern platform that has emoji fonts.
  /// Cleaner than shipping country PNGs.
  String get flag {
    switch (this) {
      case ZekaLang.en: return '🇬🇧';
      case ZekaLang.ur: return '🇵🇰';
      case ZekaLang.ar: return '🇸🇦';
      case ZekaLang.tr: return '🇹🇷';
      case ZekaLang.ru: return '🇷🇺';
      case ZekaLang.es: return '🇪🇸';
    }
  }

  /// BCP-47 locale tag for speech_to_text + flutter_tts.
  String get speechLocale {
    switch (this) {
      case ZekaLang.en: return 'en-US';
      case ZekaLang.ur: return 'ur-PK';
      case ZekaLang.ar: return 'ar-SA';
      case ZekaLang.tr: return 'tr-TR';
      case ZekaLang.ru: return 'ru-RU';
      case ZekaLang.es: return 'es-ES';
    }
  }

  /// Short two-letter pill for compact UI.
  String get pillLabel {
    switch (this) {
      case ZekaLang.en: return 'EN';
      case ZekaLang.ur: return 'اردو';
      case ZekaLang.ar: return 'AR';
      case ZekaLang.tr: return 'TR';
      case ZekaLang.ru: return 'RU';
      case ZekaLang.es: return 'ES';
    }
  }
}

class LanguageNotifier extends StateNotifier<ZekaLang> {
  LanguageNotifier() : super(ZekaLang.en) {
    _restore();
  }

  static const _key = 'zeka.lang';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null) return;
    for (final l in ZekaLang.values) {
      if (l.code == saved) {
        state = l;
        return;
      }
    }
  }

  Future<void> set(ZekaLang lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang.code);
  }
}

final languageProvider =
    StateNotifierProvider<LanguageNotifier, ZekaLang>((ref) => LanguageNotifier());

/// In-app translation dictionary. Same key vocabulary as the web Zeka
/// (src/lib/zeka-i18n.ts). Missing translations fall back to English
/// so adding a new language can ship incrementally — just fill in the
/// keys you have ready and the rest stay in English until translated.
const Map<String, Map<ZekaLang, String>> _strings = {
  'brand': {
    ZekaLang.en: 'Zeka',
    ZekaLang.ur: 'زیکا',
    ZekaLang.ar: 'زيكا',
    ZekaLang.tr: 'Zeka',
    ZekaLang.ru: 'Зека',
    ZekaLang.es: 'Zeka',
  },
  'brandSub': {
    ZekaLang.en: 'Calculator · Converter · AI',
    ZekaLang.ur: 'کیلکولیٹر · کنورٹر · AI',
    ZekaLang.ar: 'حاسبة · محول · ذكاء',
    ZekaLang.tr: 'Hesap · Çevirici · YZ',
    ZekaLang.ru: 'Калькулятор · Конвертер · ИИ',
    ZekaLang.es: 'Calculadora · Convertidor · IA',
  },
  'calculator': {
    ZekaLang.en: 'Calculator',
    ZekaLang.ur: 'کیلکولیٹر',
    ZekaLang.ar: 'حاسبة',
    ZekaLang.tr: 'Hesap makinesi',
    ZekaLang.ru: 'Калькулятор',
    ZekaLang.es: 'Calculadora',
  },
  'converter': {
    ZekaLang.en: 'Unit converter',
    ZekaLang.ur: 'یونٹ کنورٹر',
    ZekaLang.ar: 'محول الوحدات',
    ZekaLang.tr: 'Birim çevirici',
    ZekaLang.ru: 'Конвертер единиц',
    ZekaLang.es: 'Convertidor de unidades',
  },
  'ai': {
    ZekaLang.en: 'AI',
    ZekaLang.ur: 'AI',
    ZekaLang.ar: 'ذكاء',
    ZekaLang.tr: 'YZ',
    ZekaLang.ru: 'ИИ',
    ZekaLang.es: 'IA',
  },
  'beta': {
    ZekaLang.en: 'beta',
    ZekaLang.ur: 'بیٹا',
    ZekaLang.ar: 'تجريبي',
    ZekaLang.tr: 'beta',
    ZekaLang.ru: 'бета',
    ZekaLang.es: 'beta',
  },
  'askZeka': {
    ZekaLang.en: 'Ask Zeka',
    ZekaLang.ur: 'زیکا سے پوچھیں',
    ZekaLang.ar: 'اسأل زيكا',
    ZekaLang.tr: 'Zeka’ya sor',
    ZekaLang.ru: 'Спросить Зеку',
    ZekaLang.es: 'Pregunta a Zeka',
  },
  'goodMorning': {
    ZekaLang.en: 'Good morning',
    ZekaLang.ur: 'صبح بخیر',
    ZekaLang.ar: 'صباح الخير',
    ZekaLang.tr: 'Günaydın',
    ZekaLang.ru: 'Доброе утро',
    ZekaLang.es: 'Buenos días',
  },
  'goodAfternoon': {
    ZekaLang.en: 'Good afternoon',
    ZekaLang.ur: 'دوپہر بخیر',
    ZekaLang.ar: 'مساء الخير',
    ZekaLang.tr: 'İyi günler',
    ZekaLang.ru: 'Добрый день',
    ZekaLang.es: 'Buenas tardes',
  },
  'goodEvening': {
    ZekaLang.en: 'Good evening',
    ZekaLang.ur: 'شام بخیر',
    ZekaLang.ar: 'مساء الخير',
    ZekaLang.tr: 'İyi akşamlar',
    ZekaLang.ru: 'Добрый вечер',
    ZekaLang.es: 'Buenas noches',
  },
  'welcomeToZeka': {
    ZekaLang.en: 'Welcome to Zeka',
    ZekaLang.ur: 'زیکا میں خوش آمدید',
    ZekaLang.ar: 'مرحبا بك في زيكا',
    ZekaLang.tr: 'Zeka’ya hoş geldin',
    ZekaLang.ru: 'Добро пожаловать в Зеку',
    ZekaLang.es: 'Bienvenido a Zeka',
  },
  'solve': {
    ZekaLang.en: 'Solve',
    ZekaLang.ur: 'حل کریں',
    ZekaLang.ar: 'حل',
    ZekaLang.tr: 'Çöz',
    ZekaLang.ru: 'Решить',
    ZekaLang.es: 'Resolver',
  },
  'thinking': {
    ZekaLang.en: 'Thinking…',
    ZekaLang.ur: 'سوچ رہا ہے…',
    ZekaLang.ar: 'يفكر…',
    ZekaLang.tr: 'Düşünüyor…',
    ZekaLang.ru: 'Думаю…',
    ZekaLang.es: 'Pensando…',
  },
  'from': {
    ZekaLang.en: 'From',
    ZekaLang.ur: 'سے',
    ZekaLang.ar: 'من',
    ZekaLang.tr: 'Birim',
    ZekaLang.ru: 'Из',
    ZekaLang.es: 'De',
  },
  'to': {
    ZekaLang.en: 'To',
    ZekaLang.ur: 'تک',
    ZekaLang.ar: 'إلى',
    ZekaLang.tr: 'Hedef',
    ZekaLang.ru: 'В',
    ZekaLang.es: 'A',
  },
  'home': {
    ZekaLang.en: 'Home',
    ZekaLang.ur: 'ہوم',
    ZekaLang.ar: 'الرئيسية',
    ZekaLang.tr: 'Ana sayfa',
    ZekaLang.ru: 'Главная',
    ZekaLang.es: 'Inicio',
  },
  'history': {
    ZekaLang.en: 'History',
    ZekaLang.ur: 'ہسٹری',
    ZekaLang.ar: 'السجل',
    ZekaLang.tr: 'Geçmiş',
    ZekaLang.ru: 'История',
    ZekaLang.es: 'Historial',
  },
  'historySub': {
    ZekaLang.en: 'Recent calculations',
    ZekaLang.ur: 'حالیہ حساب کتاب',
    ZekaLang.ar: 'الحسابات الأخيرة',
    ZekaLang.tr: 'Son hesaplamalar',
    ZekaLang.ru: 'Последние вычисления',
    ZekaLang.es: 'Cálculos recientes',
  },
  'localContext': {
    ZekaLang.en: 'Local context',
    ZekaLang.ur: 'مقامی سیاق و سباق',
    ZekaLang.ar: 'السياق المحلي',
    ZekaLang.tr: 'Yerel bağlam',
    ZekaLang.ru: 'Местный контекст',
    ZekaLang.es: 'Contexto local',
  },
  'voiceHint': {
    ZekaLang.en: 'Tap mic — or say "Hey Zeka"',
    ZekaLang.ur: 'مائیک پر ٹیپ کریں — یا کہیں "ہے زیکا"',
    ZekaLang.ar: 'انقر على الميكروفون — أو قل "Hey Zeka"',
    ZekaLang.tr: 'Mikrofona dokunun — veya "Hey Zeka" deyin',
    ZekaLang.ru: 'Нажмите микрофон — или скажите "Hey Zeka"',
    ZekaLang.es: 'Toca el micrófono — o di "Hey Zeka"',
  },
  'cameraHint': {
    ZekaLang.en: 'Take a photo of the problem',
    ZekaLang.ur: 'مسئلے کی تصویر لیں',
    ZekaLang.ar: 'التقط صورة للسؤال',
    ZekaLang.tr: 'Sorunun fotoğrafını çek',
    ZekaLang.ru: 'Сфотографируйте задачу',
    ZekaLang.es: 'Toma una foto del problema',
  },
  'offline': {
    ZekaLang.en: 'Offline',
    ZekaLang.ur: 'آفلائن',
    ZekaLang.ar: 'دون اتصال',
    ZekaLang.tr: 'Çevrimdışı',
    ZekaLang.ru: 'Не в сети',
    ZekaLang.es: 'Sin conexión',
  },
  'online': {
    ZekaLang.en: 'Online',
    ZekaLang.ur: 'آن لائن',
    ZekaLang.ar: 'متصل',
    ZekaLang.tr: 'Çevrimiçi',
    ZekaLang.ru: 'В сети',
    ZekaLang.es: 'En línea',
  },
  'offlineAi': {
    ZekaLang.en: "You're offline. Calculator + converter still work; AI needs internet.",
    ZekaLang.ur: 'آپ آفلائن ہیں۔ کیلکولیٹر اور کنورٹر کام کر رہے ہیں؛ AI کے لیے انٹرنیٹ ضروری ہے۔',
    ZekaLang.ar: 'أنت غير متصل. الحاسبة والمحول يعملان؛ الذكاء يحتاج إنترنت.',
    ZekaLang.tr: 'Çevrimdışısın. Hesap makinesi ve çevirici çalışıyor; YZ internet gerektirir.',
    ZekaLang.ru: 'Вы не в сети. Калькулятор и конвертер работают; ИИ нужен интернет.',
    ZekaLang.es: 'Sin conexión. La calculadora y el convertidor funcionan; la IA necesita internet.',
  },
  'aiNotConfigured': {
    ZekaLang.en: 'AI key not configured. Set DEEPSEEK_API_KEY or OPENAI_API_KEY in .env.',
    ZekaLang.ur: 'AI کلید کنفیگر نہیں ہے۔ .env میں DEEPSEEK_API_KEY یا OPENAI_API_KEY سیٹ کریں۔',
    ZekaLang.ar: 'مفتاح الذكاء غير مهيأ. اضبط DEEPSEEK_API_KEY أو OPENAI_API_KEY في .env.',
    ZekaLang.tr: 'YZ anahtarı yok. .env içine DEEPSEEK_API_KEY veya OPENAI_API_KEY ekleyin.',
    ZekaLang.ru: 'Ключ ИИ не настроен. Добавьте DEEPSEEK_API_KEY или OPENAI_API_KEY в .env.',
    ZekaLang.es: 'Clave de IA no configurada. Define DEEPSEEK_API_KEY u OPENAI_API_KEY en .env.',
  },
  'noTextInImage': {
    ZekaLang.en: 'No readable text in image. Try a clearer photo.',
    ZekaLang.ur: 'تصویر میں متن نہیں ملا۔ صاف تصویر لیں۔',
    ZekaLang.ar: 'لا يوجد نص واضح في الصورة. جرّب صورة أوضح.',
    ZekaLang.tr: 'Görüntüde okunabilir metin yok. Daha net fotoğraf çekin.',
    ZekaLang.ru: 'В изображении нет читаемого текста. Попробуйте чёткое фото.',
    ZekaLang.es: 'No hay texto legible en la imagen. Prueba con una foto más clara.',
  },
  'language': {
    ZekaLang.en: 'Language',
    ZekaLang.ur: 'زبان',
    ZekaLang.ar: 'اللغة',
    ZekaLang.tr: 'Dil',
    ZekaLang.ru: 'Язык',
    ZekaLang.es: 'Idioma',
  },
  'selectLanguage': {
    ZekaLang.en: 'Select language',
    ZekaLang.ur: 'زبان منتخب کریں',
    ZekaLang.ar: 'اختر اللغة',
    ZekaLang.tr: 'Dil seçin',
    ZekaLang.ru: 'Выбрать язык',
    ZekaLang.es: 'Seleccionar idioma',
  },
};

/// Look up a translation. Falls back to English if the key is missing
/// in the target language (defensive — partial translations ship cleanly).
String tr(BuildContext context, WidgetRef ref, String key) {
  final lang = ref.read(languageProvider);
  return _strings[key]?[lang] ?? _strings[key]?[ZekaLang.en] ?? key;
}
