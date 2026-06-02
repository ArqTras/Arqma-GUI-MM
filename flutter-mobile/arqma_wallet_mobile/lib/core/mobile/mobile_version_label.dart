import 'package:package_info_plus/package_info_plus.dart';

/// `pubspec.yaml` version + build number for footer and about dialogs.
Future<String> mobileVersionLabel() async {
  final PackageInfo info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}
