import 'package:flutter/material.dart';

/// Shared layout breakpoints for iOS and Android wallet UI (phones, phablets, tablets).
abstract final class MobileResponsiveLayout {
  /// Stack tx-history filter fields vertically on narrow screens.
  static const double stackFiltersBreakpoint = 420;

  /// Extra-compact list padding and shorter txid labels.
  static const double compactBreakpoint = 360;

  /// Wider txid preview on tablets / unfolded phones.
  static const double expandedBreakpoint = 600;

  /// Staking pool list uses stacked cards instead of the wide tabular row.
  static const double stakingCompactBreakpoint = 900;

  static bool stackFilters(double width) => width < stackFiltersBreakpoint;

  static bool useCompactStakingPools(double width) =>
      width < stakingCompactBreakpoint;

  static bool isCompact(double width) => width < compactBreakpoint;

  static EdgeInsets listHorizontalPadding(double width) {
    if (width < compactBreakpoint) {
      return const EdgeInsets.symmetric(horizontal: 8);
    }
    if (width >= expandedBreakpoint) {
      return const EdgeInsets.symmetric(horizontal: 16);
    }
    return const EdgeInsets.symmetric(horizontal: 12);
  }

  /// Monospace txid for list rows — length scales with available width.
  static String txidListLabel(String txid, double layoutWidth) {
    final String t = txid.trim();
    if (t.isEmpty) {
      return t;
    }
    final int head;
    final int tail;
    if (layoutWidth >= expandedBreakpoint) {
      head = 22;
      tail = 14;
    } else if (layoutWidth >= stackFiltersBreakpoint) {
      head = 16;
      tail = 12;
    } else if (layoutWidth >= compactBreakpoint) {
      head = 14;
      tail = 10;
    } else {
      head = 10;
      tail = 8;
    }
    if (t.length <= head + tail + 1) {
      return t;
    }
    return '${t.substring(0, head)}…${t.substring(t.length - tail)}';
  }

  static double contentWidth(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    return mq.size.width - mq.padding.horizontal;
  }
}
