import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/core_providers.dart';
import '../../shared/providers/sync_providers.dart';
import '../config/app_routes.dart';
import '../extensions/extensions.dart';
import '../theme/app_dimens.dart';
import 'app_state_views.dart';
import 'glass_panel.dart';

/// The persistent app frame: bottom navigation, offline banner, and FAB.
///
/// It wraps `StatefulNavigationShell`, so each tab keeps its own navigation
/// stack and scroll position across switches.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  /// The shell sits outside the tab navigators, so a locale change does not
  /// reach it through route rebuilds. Translating with `context` registers a
  /// dependency on the app's `Localizations`, which makes the tab labels and
  /// FAB text re-render the moment the language switches.
  static List<_NavItem> _items(BuildContext context) => <_NavItem>[
    _NavItem(
      label: 'home'.tr(context: context),
      icon: Icons.space_dashboard_outlined,
      activeIcon: Icons.space_dashboard_rounded,
    ),
    _NavItem(
      label: 'activity'.tr(context: context),
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
    ),
    _NavItem(
      label: 'reports'.tr(context: context),
      icon: Icons.insights_outlined,
      activeIcon: Icons.insights_rounded,
    ),
    _NavItem(
      label: 'profile'.tr(context: context),
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isOnline = ref.watch(isOnlineProvider);
    final int pending = ref.watch(pendingSyncCountProvider).value ?? 0;

    // Wide screens get a rail instead of a bottom bar — thumbs cannot reach
    // the bottom of a tablet held in landscape.
    final bool useRail = !context.isMobile;

    return Scaffold(
      body: Column(
        children: <Widget>[
          if (!isOnline) OfflineBanner(pendingCount: pending),
          Expanded(
            child: useRail
                ? Row(
                    children: <Widget>[
                      _NavRail(shell: shell, items: _items(context)),
                      const VerticalDivider(width: 1),
                      Expanded(child: shell),
                    ],
                  )
                : shell,
          ),
        ],
      ),
      bottomNavigationBar: useRail ? null : _GlassNavBar(shell: shell, items: _items(context)),
      floatingActionButton: _shouldShowFab(context)
          ? FloatingActionButton.extended(
              heroTag: 'add-transaction',
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_rounded),
              label: Text('add'.tr(context: context)),
            ).animate().scaleXY(
              begin: 0.7,
              duration: 260.ms,
              curve: Curves.easeOutBack,
            )
          : null,
    );
  }

  /// The FAB belongs to the two tabs where "add a transaction" is the obvious
  /// next action; on reports and profile it would be noise. It is also hidden
  /// while the transaction form itself is open — an "add" button on top of the
  /// add screen is redundant and covers the form's own submit button.
  bool _shouldShowFab(BuildContext context) {
    final bool onAddTab = shell.currentIndex == 0 || shell.currentIndex == 1;
    if (!onAddTab) return false;
    final String location = GoRouterState.of(context).uri.path;
    return !location.contains(AppRoutes.transactionForm);
  }

  void _openForm(BuildContext context) {
    final String base = shell.currentIndex == 0
        ? AppRoutes.dashboard
        : AppRoutes.transactions;
    context.go('$base/${AppRoutes.transactionForm}');
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Floating frosted navigation bar.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.shell, required this.items});

  final StatefulNavigationShell shell;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: GlassPanel(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                // Loose `Flexible` rather than `Expanded`: the buttons keep
                // hugging their content where there is room, but can never
                // demand more than their quarter of a narrow bar.
                Flexible(
                  child: _NavButton(
                    item: items[i],
                    isSelected: shell.currentIndex == i,
                    // `initialLocation: true` on a re-tap pops the tab back to
                    // its root — the standard "tap the active tab to go home".
                    onTap: () => shell.goBranch(
                      i,
                      initialLocation: i == shell.currentIndex,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected
        ? context.colors.primary
        : context.colors.onSurfaceVariant;

    return Semantics(
      selected: isSelected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: 220.ms,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? context.colors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedSwitcher(
                duration: 200.ms,
                child: Icon(
                  isSelected ? item.activeIcon : item.icon,
                  key: ValueKey<bool>(isSelected),
                  size: 22,
                  color: color,
                ),
              ),
              AppSpacing.xxs.gapH,
              // Scales the label down instead of overflowing when the user
              // has bumped their system text size.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  style: context.text.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tablet/desktop navigation.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.shell, required this.items});

  final StatefulNavigationShell shell;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (int index) => shell.goBranch(
        index,
        initialLocation: index == shell.currentIndex,
      ),
      labelType: NavigationRailLabelType.all,
      destinations: <NavigationRailDestination>[
        for (final _NavItem item in items)
          NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.activeIcon),
            label: Text(item.label),
          ),
      ],
    );
  }
}
