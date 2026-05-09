import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// PRNG + 8×8 grid — port of `components/identicon.vue` (`seedrand` / `rand` / `createImageData` / colors).
class IdenticonRand {
  IdenticonRand(String seed) : _s = <int>[0, 0, 0, 0] {
    for (int b = 0; b < seed.length; b++) {
      final int i = b % 4;
      _s[i] = _toInt32((_s[i] << 5) - _s[i] + seed.codeUnitAt(b));
    }
  }

  final List<int> _s;

  static int _toInt32(int x) {
    int v = x & 0xFFFFFFFF;
    if (v & 0x80000000 != 0) {
      v = v - 0x100000000;
    }
    return v;
  }

  double next() {
    final int t = _toInt32(_s[0] ^ (_s[0] << 11));
    _s[0] = _s[1];
    _s[1] = _s[2];
    _s[2] = _s[3];
    _s[3] = _toInt32(_s[3] ^ (_s[3] >> 19) ^ t ^ (t >> 8));
    return (_s[3] & 0xFFFFFFFF) / 2147483648.0;
  }

  Color nextHslColor() {
    final double h = (next() * 360).floorToDouble();
    final double s = next() * 60 + 40;
    final double l = (next() + next() + next() + next()) * 25;
    return HSLColor.fromAHSL(1, h, (s / 100).clamp(0, 1), (l / 100).clamp(0, 1)).toColor();
  }

  List<int> createImageData(int gridSize) {
    final int dataWidth = (gridSize / 2).ceil();
    final int mirrorWidth = gridSize - dataWidth;
    final List<int> data = <int>[];
    for (int y = 0; y < gridSize; y++) {
      final List<int> row = <int>[];
      for (int x = 0; x < dataWidth; x++) {
        row.add((next() * 2.3).floor().clamp(0, 2));
      }
      final List<int> mirror = row.sublist(0, mirrorWidth).reversed.toList();
      row.addAll(mirror);
      data.addAll(row);
    }
    return data;
  }
}

/// Same prefix/length checks as Vue `isAddressValid` + typical CryptoNote lengths for Arqma-style addresses.
bool identiconSeedLooksValid(String input) {
  if (input.isEmpty || !RegExp(r'^[0-9A-Za-z]+$').hasMatch(input)) {
    return false;
  }
  if (input.length >= 95 && input.length <= 110) {
    return true;
  }
  final int prefixLen = input.length >= 4 ? 4 : input.length;
  switch (input.substring(0, prefixLen)) {
    case 'Sumo':
    case 'RYoL':
    case 'Suto':
    case 'RYoT':
      return input.length == 99;
    case 'Subo':
    case 'Suso':
      return input.length == 98;
    case 'RYoS':
    case 'RYoU':
      return input.length == 99;
    case 'Sumi':
    case 'RYoN':
    case 'Suti':
    case 'RYoE':
      return input.length == 110;
    case 'RYoK':
    case 'RYoH':
      return input.length == 55;
    default:
      return false;
  }
}

/// Paints identicon into [canvas] with top-left at (0,0), size [side]×[side].
void paintIdenticon(Canvas canvas, String seed, double side, {int gridSize = 8}) {
  final IdenticonRand r = IdenticonRand(seed);
  final Color bg = r.nextHslColor();
  final Color fg = r.nextHslColor();
  final Color spot = r.nextHslColor();
  final List<int> cells = r.createImageData(gridSize);
  final double cell = side / gridSize;
  final int w = gridSize;
  final Paint paint = Paint();
  canvas.drawRect(Rect.fromLTWH(0, 0, side, side), paint..color = bg);
  for (int i = 0; i < cells.length; i++) {
    final int v = cells[i];
    if (v == 0) {
      continue;
    }
    final int row = i ~/ w;
    final int col = i % w;
    paint.color = v == 1 ? fg : spot;
    canvas.drawRect(Rect.fromLTWH(col * cell, row * cell, cell, cell), paint);
  }
}

/// Rasterizes identicon for tests / optional export (Vue `save_png`).
Future<ui.Image> rasterizeIdenticon(String seed, {int gridSize = 8, int pixelSide = 64}) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final Canvas c = Canvas(rec);
  paintIdenticon(c, seed, pixelSide.toDouble(), gridSize: gridSize);
  final ui.Picture pic = rec.endRecording();
  return pic.toImage(pixelSide, pixelSide);
}
