const Set<String> _bridgeSensitiveKeys = <String>{
  'password',
  'old_password',
  'new_password',
  'mnemonic',
  'seed',
  'viewkey',
  'view_key',
  'spend_key',
  'secret',
  'private_key',
  'private_keys',
  'keys',
};

/// Redact wallet secrets before logging bridge / RPC argument maps.
Map<String, dynamic> redactBridgeArgs(Map<String, dynamic>? args) {
  if (args == null || args.isEmpty) {
    return <String, dynamic>{};
  }
  final Map<String, dynamic> out = <String, dynamic>{};
  for (final MapEntry<String, dynamic> e in args.entries) {
    final String key = e.key;
    if (_bridgeSensitiveKeys.contains(key.toLowerCase())) {
      out[key] = '***';
    } else {
      out[key] = e.value;
    }
  }
  return out;
}

String truncateLogText(String text, {int max = 240}) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max)}…(${text.length} chars)';
}
