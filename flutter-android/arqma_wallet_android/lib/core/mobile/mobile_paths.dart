import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../desktop/arqma_paths.dart';

/// Application support paths for iOS/Android (no system-wide `~/.arqma`).
class MobileArqmaPaths {
  MobileArqmaPaths._(this._paths);

  final ArqmaPaths _paths;
  static ArqmaPaths? _cached;

  ArqmaPaths get paths => _paths;

  static Future<ArqmaPaths> resolve() async {
    if (_cached != null) {
      return _cached!;
    }
    if (Platform.isIOS || Platform.isAndroid) {
      final Directory docs = await getApplicationDocumentsDirectory();
      final String base = docs.path;
      _cached = ArqmaPaths(
        configDir: '$base/.arqma',
        walletDir: '$base/arqma',
      );
      return _cached!;
    }
    _cached = ArqmaPaths.defaultForPlatform();
    return _cached!;
  }
}
