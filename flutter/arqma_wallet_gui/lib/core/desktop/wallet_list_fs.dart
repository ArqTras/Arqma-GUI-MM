import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Same rules as `wallet_list_fs::list_wallet_files` (`rust/tauri-app/src-tauri/src/wallet_list_fs.rs`).
Map<String, dynamic> listWalletFiles(String walletDirPath) {
  final Directory dir = Directory(walletDirPath);
  if (!dir.existsSync()) {
    return <String, dynamic>{'list': <dynamic>[], 'directories': <dynamic>[], 'legacy': <dynamic>[]};
  }
  final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
  final List<String> directories = <String>[];
  const Set<String> skipNames = <String>{
    '.DS_Store',
    '.DS_Store?',
    '._.DS_Store',
    '.Spotlight-V100',
    '.Trashes',
    'Thumbs.db',
    'ehthumbs.db',
    'old-gui',
  };
  try {
    for (final FileSystemEntity ent in dir.listSync(followLinks: false)) {
      final String name = ent.path.split(Platform.pathSeparator).last;
      if (skipNames.contains(name)) {
        continue;
      }
      if (ent is Directory) {
        final File wfile = File('${ent.path}${Platform.pathSeparator}$name');
        final File keyf = File('${wfile.path}.keys');
        if (wfile.existsSync() && keyf.existsSync()) {
          directories.add(name);
        }
        continue;
      }
      if (ent is! File) {
        continue;
      }
      if (name.contains('.')) {
        continue;
      }
      final Map<String, dynamic> walletData = <String, dynamic>{
        'name': name,
        'address': null,
        'password_protected': null,
      };
      final File meta = File('${dir.path}${Platform.pathSeparator}$name.meta.json');
      if (meta.existsSync()) {
        try {
          final dynamic m = jsonDecode(meta.readAsStringSync());
          if (m is Map) {
            final Map<String, dynamic> mm = Map<String, dynamic>.from(m);
            if (mm.containsKey('address')) {
              walletData['address'] = mm['address'];
            }
            if (mm.containsKey('password_protected')) {
              walletData['password_protected'] = mm['password_protected'];
            }
          }
        } catch (e) {
          debugPrint('[wallet_list_fs] meta $name: $e');
        }
      }
      final File addrf = File('${dir.path}${Platform.pathSeparator}$name.address.txt');
      if (addrf.existsSync()) {
        final String s = addrf.readAsStringSync().trim();
        if (s.isNotEmpty) {
          walletData['address'] = s;
        }
      }
      list.add(walletData);
    }
  } catch (e, st) {
    debugPrint('[wallet_list_fs] $e\n$st');
    return <String, dynamic>{'list': <dynamic>[], 'directories': <dynamic>[], 'legacy': <dynamic>[]};
  }
  return <String, dynamic>{'list': list, 'directories': directories, 'legacy': <dynamic>[]};
}
