/// Deep-merge maps like `object-assign-deep` for nested objects.
/// Lists from [patch] replace the target key (Vue store often assigns arrays wholesale).
dynamic deepMergeMaps(dynamic base, dynamic patch) {
  if (patch is Map && base is Map) {
    final out = Map<String, dynamic>.from(base as Map<String, dynamic>);
    patch.forEach((Object? k, Object? v) {
      final key = k as String;
      final existing = out[key];
      if (v is Map && existing is Map) {
        out[key] = deepMergeMaps(existing, v);
      } else {
        out[key] = v;
      }
    });
    return out;
  }
  return patch;
}
