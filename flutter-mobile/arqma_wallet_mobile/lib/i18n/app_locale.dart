import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Internal JSON asset tags (Vue parity) mapped to Flutter / intl BCP-47 codes.
String migrateLegacyLocaleTag(String? raw) {
  if (raw == null || raw.isEmpty) {
    return 'en-US';
  }
  final List<String> parts = raw.split('-');
  if (parts.length >= 2) {
    final String lang = parts[0].toLowerCase();
    final String region = parts[1].toUpperCase();
    switch ('$lang-$region') {
      case 'ua-UA':
        return 'ua-UA';
      case 'cn-CN':
        return 'cn-CN';
      case 'jp-JP':
        return 'jp-JP';
      default:
        return '$lang-$region';
    }
  }
  return raw;
}

/// [LocaleController] asset tag → [MaterialApp.locale].
Locale flutterLocaleFromAppTag(String tag) {
  final String normalized = migrateLegacyLocaleTag(tag);
  switch (normalized) {
    case 'ua-UA':
      return const Locale('uk', 'UA');
    case 'cn-CN':
      return const Locale('zh', 'CN');
    case 'jp-JP':
      return const Locale('ja', 'JP');
    default:
      final List<String> p = normalized.split('-');
      if (p.length >= 2) {
        return Locale(p[0].toLowerCase(), p[1].toUpperCase());
      }
      return Locale(p[0].toLowerCase());
  }
}

const List<Locale> kAppSupportedFlutterLocales = <Locale>[
  Locale('en', 'US'),
  Locale('de', 'DE'),
  Locale('fr', 'FR'),
  Locale('uk', 'UA'),
  Locale('pl', 'PL'),
  Locale('es', 'ES'),
  Locale('zh', 'CN'),
  Locale('ja', 'JP'),
  Locale('ms', 'MY'),
  Locale('ar', 'SA'),
  Locale('pt', 'BR'),
  Locale('ru', 'RU'),
];

void configureAppTimeago(String normalizedAssetTag) {
  timeago.setLocaleMessages('en', timeago.EnMessages());
  final String primary = normalizedAssetTag.split('-').first.toLowerCase();
  switch (primary) {
    case 'pl':
      timeago.setLocaleMessages('pl', timeago.PlMessages());
      break;
    case 'fr':
      timeago.setLocaleMessages('fr', timeago.FrMessages());
      break;
    case 'es':
      timeago.setLocaleMessages('es', timeago.EsMessages());
      break;
    case 'de':
      timeago.setLocaleMessages('de', timeago.DeMessages());
      break;
    case 'ru':
      timeago.setLocaleMessages('ru', timeago.RuMessages());
      break;
    case 'pt':
      timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
      break;
    case 'jp':
    case 'ja':
      timeago.setLocaleMessages('ja', timeago.JaMessages());
      break;
    case 'cn':
    case 'zh':
      timeago.setLocaleMessages('zh_CN', timeago.ZhCnMessages());
      break;
    case 'ua':
    case 'uk':
      timeago.setLocaleMessages('uk', timeago.UkMessages());
      break;
    default:
      break;
  }
}
