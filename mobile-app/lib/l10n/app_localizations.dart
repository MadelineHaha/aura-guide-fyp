import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'strings_en.dart';
import 'strings_ms.dart';
import 'strings_zh.dart';

class AppLocalizations {
  AppLocalizations(this.languageCode);

  final String languageCode;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('ms'),
    Locale('zh'),
  ];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(localizations != null, 'AppLocalizations not found in context');
    return localizations!;
  }

  static AppLocalizations? maybeOf(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  Map<String, String> get _strings {
    switch (languageCode) {
      case 'ms':
        return stringsMs;
      case 'zh':
        return stringsZh;
      default:
        return stringsEn;
    }
  }

  String t(String key, [Map<String, Object?> params = const {}]) {
    var value = _strings[key] ?? stringsEn[key] ?? key;
    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value?.toString() ?? '');
    }
    return value;
  }

  /// Localized strings using a language code (for services without [BuildContext]).
  static String translate(
    String languageCode,
    String key, [
    Map<String, Object?> params = const {},
  ]) {
    return AppLocalizations(languageCode).t(key, params);
  }
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale.languageCode));
  }

  @override
  bool shouldReload(covariant AppLocalizationsDelegate old) => true;
}

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
