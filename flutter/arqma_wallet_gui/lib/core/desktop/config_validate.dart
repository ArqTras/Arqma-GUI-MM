/// Parity with `rust/core/src/validate.rs` — same as Electron `Backend.validate_values` /
/// Tauri `validate_config_against_defaults` before persisting `config.json`.
bool _isObject(dynamic v) => v is Map;

dynamic validateValues(dynamic values, dynamic defaults) {
  if (!_isObject(values) || !_isObject(defaults)) {
    return values;
  }
  final Map<String, dynamic> m = Map<String, dynamic>.from(values as Map);
  final Map<String, dynamic> d = Map<String, dynamic>.from(defaults as Map);
  for (final String key in m.keys.toList()) {
    if (!d.containsKey(key)) {
      continue;
    }
    final dynamic defV = d[key];
    if (defV == null) {
      continue;
    }
    final dynamic val = m[key];
    if (_isObject(val) && _isObject(defV)) {
      m[key] = validateValues(val, defV);
    } else {
      final bool invalid = val == null ||
          (val is String && val.isEmpty) ||
          (val is double && val.isNaN);
      if (invalid) {
        m[key] = defV;
      }
    }
  }
  return m;
}

/// `validate_config_against_defaults` from `arqma_wallet_core::validate`.
Map<String, dynamic> validateConfigAgainstDefaults(
  Map<String, dynamic> configData,
  Map<String, dynamic> defaults,
) {
  if (!_isObject(configData) || !_isObject(defaults)) {
    return Map<String, dynamic>.from(configData);
  }
  final Map<String, dynamic> c = Map<String, dynamic>.from(configData);
  final Map<String, dynamic> d = Map<String, dynamic>.from(defaults);
  for (final MapEntry<String, dynamic> e in d.entries) {
    final String k = e.key;
    final dynamic defV = e.value;
    if (!c.containsKey(k)) {
      continue;
    }
    final dynamic a = c[k];
    if (_isObject(a) && _isObject(defV)) {
      c[k] = validateValues(a, defV);
    }
  }
  return c;
}

/// `rust/core/src/startup.rs` `strip_trusted_daemon_from_config` — remove legacy CLI keys from JSON.
void stripTrustedDaemonFromConfig(dynamic v) {
  if (v is Map) {
    v.remove('trusted-daemon');
    v.remove('trusted_daemon');
    v.remove('trustedDaemon');
    for (final Object? child in v.values) {
      stripTrustedDaemonFromConfig(child);
    }
  } else if (v is List) {
    for (final dynamic item in v) {
      stripTrustedDaemonFromConfig(item);
    }
  }
}
