import 'package:qr/qr.dart';

/// Builds a minimal SVG for [data] (parity with Vue `qrcode` → `outerHTML` for `save_svg`).
String buildQrCodeSvg(
  String data, {
  double moduleSize = 4,
  int quietZone = 4,
}) {
  if (data.isEmpty) {
    return '<svg xmlns="http://www.w3.org/2000/svg"/>';
  }
  QrImage? image;
  for (int type = 1; type <= 40; type++) {
    try {
      final QrCode qr = QrCode(type, QrErrorCorrectLevel.L)..addData(data);
      image = QrImage(qr);
      break;
    } catch (_) {
      continue;
    }
  }
  if (image == null) {
    return '<svg xmlns="http://www.w3.org/2000/svg"/>';
  }
  final int n = image.moduleCount;
  final double size = (n + 2 * quietZone) * moduleSize;
  final StringBuffer b = StringBuffer()
    ..write(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="$size" height="$size">',
    )
    ..write('<rect width="100%" height="100%" fill="#ffffff"/>');
  for (int y = 0; y < n; y++) {
    for (int x = 0; x < n; x++) {
      if (image.isDark(y, x)) {
        final double px = (x + quietZone) * moduleSize;
        final double py = (y + quietZone) * moduleSize;
        b.write(
          '<rect x="$px" y="$py" width="$moduleSize" height="$moduleSize" fill="#000000"/>',
        );
      }
    }
  }
  b.write('</svg>');
  return b.toString();
}
