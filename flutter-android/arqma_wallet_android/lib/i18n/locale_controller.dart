import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the same JSON trees as `src/locales/*.json` (Vue i18n).
class LocaleController extends ChangeNotifier {
  LocaleController();

  static const String _prefKey = 'language';

  String _locale = 'en-US';
  Map<String, dynamic> _messages = <String, dynamic>{};

  String get locale => _locale;

  static String normalizeLocale(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'en-US';
    }
    final parts = raw.split('-');
    if (parts.length >= 2) {
      return '${parts[0].toLowerCase()}-${parts[1].toUpperCase()}';
    }
    return raw;
  }

  Future<void> loadSaved() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? s = p.getString(_prefKey);
    await setLocale(normalizeLocale(s));
  }

  Future<void> setLocale(String raw) async {
    final String next = normalizeLocale(raw);
    final String asset = 'assets/locales/$next.json';
    try {
      final String data = await rootBundle.loadString(asset);
      _messages = jsonDecode(data) as Map<String, dynamic>;
      _locale = next;
    } catch (e, st) {
      debugPrint('[LocaleController] failed to load $asset: $e\n$st');
      if (next != 'en-US') {
        await setLocale('en-US');
        return;
      }
      rethrow;
    }
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_prefKey, _locale);
    notifyListeners();
  }

  /// Nested key path `pages.init.connecting_to_backend` like vue-i18n.
  String tr(String key, {Map<String, String>? named}) {
    final List<String> parts = key.split('.');
    dynamic node = _messages;
    for (final String p in parts) {
      if (node is! Map) {
        return key;
      }
      node = (node as Map<String, dynamic>)[p];
      if (node == null) {
        return key;
      }
    }
    if (node is! String) {
      return key;
    }
    String out = node;
    named?.forEach((String k, String v) {
      out = out.replaceAll('{$k}', v);
    });
    return out;
  }
}
