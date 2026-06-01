import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/arqma_colors.dart';

/// One wallet main navigation tab (route + label + icon).
class WalletMainTabItem {
  const WalletMainTabItem({
    required this.route,
    required this.label,
    required this.icon,
  });

  final String route;
  final String label;
  final IconData icon;
}

/// Horizontally scrollable wallet tabs with smooth centering of the active tab.
class WalletMainTabBar extends StatefulWidget {
  const WalletMainTabBar({
    super.key,
    required this.activePath,
    required this.tabs,
    required this.onTabTap,
    this.trailing,
  });

  final String activePath;
  final List<WalletMainTabItem> tabs;
  final ValueChanged<String> onTabTap;

  /// Pinned outside the scroll area (e.g. wallet settings menu).
  final Widget? trailing;

  @override
  State<WalletMainTabBar> createState() => _WalletMainTabBarState();
}

class _WalletMainTabBarState extends State<WalletMainTabBar> {
  static const Duration _scrollDuration = Duration(milliseconds: 180);
  static const Curve _scrollCurve = Curves.easeOutCubic;

  final List<GlobalKey> _tabKeys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _syncKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerActiveTab());
  }

  @override
  void didUpdateWidget(WalletMainTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _syncKeys();
    }
    if (oldWidget.activePath != widget.activePath) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerActiveTab());
    }
  }

  void _syncKeys() {
    while (_tabKeys.length < widget.tabs.length) {
      _tabKeys.add(GlobalKey());
    }
    while (_tabKeys.length > widget.tabs.length) {
      _tabKeys.removeLast();
    }
  }

  Future<void> _centerActiveTab({bool animate = true}) async {
    if (!mounted) {
      return;
    }
    final int index =
        widget.tabs.indexWhere((WalletMainTabItem t) => t.route == widget.activePath);
    if (index < 0 || index >= _tabKeys.length) {
      return;
    }
    final BuildContext? tabContext = _tabKeys[index].currentContext;
    if (tabContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      tabContext,
      alignment: 0.5,
      duration: animate ? _scrollDuration : Duration.zero,
      curve: _scrollCurve,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _handleTabTap(String route) {
    widget.onTabTap(route);
    // Tab chip is already under the finger — skip scroll animation to avoid jank.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_centerActiveTab(animate: false));
    });
  }

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight + stretch: wallet settings menu (account name) aligns
    // vertically with tab chips, not floated to the top-right of the row.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              clipBehavior: Clip.none,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < widget.tabs.length; i++)
                    KeyedSubtree(
                      key: _tabKeys[i],
                      child: WalletMainTabButton(
                        label: widget.tabs[i].label,
                        icon: widget.tabs[i].icon,
                        active: widget.tabs[i].route == widget.activePath,
                        onTap: () => _handleTabTap(widget.tabs[i].route),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
              child: Center(
                child: widget.trailing!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Single tab chip — styling matches legacy [WalletMainLayout] nav buttons.
class WalletMainTabButton extends StatelessWidget {
  const WalletMainTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: active
                    ? ArqmaColors.arqmaGreenSolid
                    : const Color(0xFF161410),
                border: Border.all(
                  color: active
                      ? ArqmaColors.outlineBright
                      : ArqmaColors.arqmaGreenSolid.withValues(alpha: 0.42),
                  width: active ? 1.4 : 1,
                ),
                boxShadow: active
                    ? <BoxShadow>[
                        BoxShadow(
                          color: ArqmaColors.arqmaGreenSolid
                              .withValues(alpha: 0.22),
                          blurRadius: 10,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF14110A)
                            : ArqmaColors.arqmaGreenSolid
                                .withValues(alpha: 0.88),
                      ),
                      child: Icon(icon, size: 18),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF14110A)
                            : ArqmaColors.arqmaGreenSolid
                                .withValues(alpha: 0.92),
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 11.5,
                        height: 1.15,
                      ),
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Detects predominantly horizontal swipes to switch wallet tabs (does not steal vertical scroll).
class WalletMainTabSwipeNavigator extends StatefulWidget {
  const WalletMainTabSwipeNavigator({
    super.key,
    required this.tabRoutes,
    required this.activePath,
    required this.onTabChange,
    required this.child,
  });

  final List<String> tabRoutes;
  final String activePath;
  final ValueChanged<String> onTabChange;
  final Widget child;

  @override
  State<WalletMainTabSwipeNavigator> createState() =>
      _WalletMainTabSwipeNavigatorState();
}

class _WalletMainTabSwipeNavigatorState extends State<WalletMainTabSwipeNavigator> {
  static const double _minHorizontalDelta = 56;
  static const double _horizontalDominanceRatio = 1.35;

  double _accumDx = 0;
  double _accumDy = 0;

  void _resetAccumulators() {
    _accumDx = 0;
    _accumDy = 0;
  }

  void _onPanEnd(DragEndDetails details) {
    final double vx = details.velocity.pixelsPerSecond.dx;
    final bool byDistance = _accumDx.abs() >= _minHorizontalDelta &&
        _accumDx.abs() > _accumDy.abs() * _horizontalDominanceRatio;
    final bool byVelocity = vx.abs() >= 520 &&
        vx.abs() > details.velocity.pixelsPerSecond.dy.abs();
    if (!byDistance && !byVelocity) {
      _resetAccumulators();
      return;
    }

    final int index = widget.tabRoutes.indexOf(widget.activePath);
    if (index < 0) {
      _resetAccumulators();
      return;
    }

    final double direction = byVelocity ? vx : _accumDx;
    if (direction > 0 && index > 0) {
      widget.onTabChange(widget.tabRoutes[index - 1]);
    } else if (direction < 0 && index < widget.tabRoutes.length - 1) {
      widget.onTabChange(widget.tabRoutes[index + 1]);
    }
    _resetAccumulators();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onPanStart: (_) => _resetAccumulators(),
      onPanUpdate: (DragUpdateDetails d) {
        _accumDx += d.delta.dx;
        _accumDy += d.delta.dy.abs();
      },
      onPanEnd: _onPanEnd,
      onPanCancel: _resetAccumulators,
      child: widget.child,
    );
  }
}
