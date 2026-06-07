import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the platform browser (parity with Tauri/Electron `shell.openExternal`).
Future<bool> openExternalUrl(String url) async {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final Uri? uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return false;
  }
  if (Platform.isIOS || Platform.isAndroid) {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      debugPrint('[openExternalUrl] launchUrl failed: $e\n$st');
      return false;
    }
  }
  if (Platform.isMacOS) {
    final ProcessResult r = await Process.run('open', <String>[trimmed]);
    return r.exitCode == 0;
  }
  if (Platform.isLinux) {
    final ProcessResult r = await Process.run('xdg-open', <String>[trimmed]);
    return r.exitCode == 0;
  }
  if (Platform.isWindows) {
    final ProcessResult r =
        await Process.run('cmd', <String>['/c', 'start', '', trimmed]);
    return r.exitCode == 0;
  }
  return false;
}
