import 'dart:io';

import 'arqma_paths.dart';

/// Port of `wallet_copy_old_gui::run_copy_old_gui_wallets`.
List<String> runCopyOldGuiWallets(
    Map<String, dynamic> configData, List<dynamic> wallets) {
  final String? walletDir = walletFilesDir(configData);
  if (walletDir == null) {
    return <String>[];
  }
  final Directory oldGuiPath =
      Directory('$walletDir${Platform.pathSeparator}old-gui');
  final List<String> failed = <String>[];

  for (final Object? w in wallets) {
    if (w is! Map) {
      continue;
    }
    final Map<String, dynamic> wm = Map<String, dynamic>.from(w);
    final String typ = '${wm['type'] ?? 'mainnet'}';
    final String? directory = wm['directory'] as String?;
    if (directory == null || directory.isEmpty) {
      continue;
    }
    final Directory dirPath =
        Directory('$walletDir${Platform.pathSeparator}$directory');
    if (!dirPath.existsSync()) {
      continue;
    }

    final File walletFile =
        File('${dirPath.path}${Platform.pathSeparator}$directory');
    final File keyPath = File('${walletFile.path}.keys');

    if (!walletFile.existsSync() || !keyPath.existsSync()) {
      failed.add(directory);
      continue;
    }

    final String? destBase = walletFilesDirForNet(configData, typ);
    if (destBase == null) {
      failed.add(directory);
      continue;
    }
    Directory(destBase).createSync(recursive: true);

    final String newPathBase = '$destBase${Platform.pathSeparator}$directory';
    final File atom = File('$newPathBase.atom');
    final File atomKeys = File('$newPathBase.atom.keys');

    if (atom.existsSync() || atomKeys.existsSync()) {
      failed.add(directory);
      continue;
    }

    try {
      walletFile.copySync(atom.path);
      keyPath.copySync(atomKeys.path);
      oldGuiPath.createSync(recursive: true);
      final Directory destinationDir =
          Directory('${oldGuiPath.path}${Platform.pathSeparator}$directory');
      if (destinationDir.existsSync()) {
        destinationDir.deleteSync(recursive: true);
      }
      dirPath.renameSync(destinationDir.path);

      final File finalWallet = File(newPathBase);
      final File finalKeys = File('$newPathBase.keys');
      if (!finalWallet.existsSync() && !finalKeys.existsSync()) {
        atom.renameSync(finalWallet.path);
        atomKeys.renameSync(finalKeys.path);
      }
    } catch (_) {
      try {
        if (atom.existsSync()) {
          atom.deleteSync();
        }
      } catch (_) {}
      try {
        if (atomKeys.existsSync()) {
          atomKeys.deleteSync();
        }
      } catch (_) {}
      failed.add(directory);
    }
  }

  return failed;
}
