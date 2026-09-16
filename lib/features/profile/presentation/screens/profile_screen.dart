import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/providers/sync_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Account hub: identity, shortcuts, sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(currentUserProvider);
    final int pending = ref.watch(pendingSyncCountProvider).value ?? 0;

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverAppBar(floating: true, titleSpacing: AppSpacing.page, title: Text('Profile')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 120),
            sliver: SliverList.list(
              children: <Widget>[
                _ProfileHeader(user: user),
                AppSpacing.xxl.gapH,

                _Section(
                  title: 'Account',
                  tiles: <Widget>[
                    _Tile(
                      icon: Icons.person_outline_rounded,
                      title: 'Edit profile',
                      subtitle: 'Name, avatar and currency',
                      onTap: () => context.pushNamed(AppRoutes.editProfile),
                    ),
                    _Tile(icon: Icons.lock_outline_rounded, title: 'Change password', onTap: () => context.pushNamed(AppRoutes.changePassword)),
                    _Tile(
                      icon: Icons.category_outlined,
                      title: 'Categories',
                      subtitle: 'Add, edit and organise',
                      onTap: () => context.pushNamed(AppRoutes.categories),
                    ),
                  ],
                ),
                AppSpacing.xl.gapH,

                _Section(
                  title: 'App',
                  tiles: <Widget>[
                    _Tile(
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      subtitle: 'Theme, language, backup',
                      onTap: () => context.pushNamed(AppRoutes.settings),
                    ),
                    _SyncTile(pending: pending),
                  ],
                ),
                AppSpacing.xxl.gapH,

                const _SignOutButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        children: <Widget>[
          UserAvatar(avatarUrl: user?.avatarUrl, name: user?.name, radius: 32, heroTag: 'profile-avatar'),
          AppSpacing.lg.gapW,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(user?.name ?? 'Signed out', style: context.text.titleMedium, overflow: TextOverflow.ellipsis),
                AppSpacing.xxs.gapH,
                Text(
                  user?.email ?? '',
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                if (user?.createdAt != null) ...<Widget>[
                  AppSpacing.sm.gapH,
                  Text(
                    'Member since ${user!.createdAt!.monthYear}',
                    style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(title, style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[if (i > 0) const Divider(height: 1), tiles[i]],
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.onTap, this.subtitle, this.trailing});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }
}

/// Manual sync with a live pending count.
class _SyncTile extends ConsumerStatefulWidget {
  const _SyncTile({required this.pending});

  final int pending;

  @override
  ConsumerState<_SyncTile> createState() => _SyncTileState();
}

class _SyncTileState extends ConsumerState<_SyncTile> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final report = await ref.read(syncCoordinatorProvider.notifier).syncNow();
    ref.invalidate(pendingSyncCountProvider);

    if (!mounted) return;
    setState(() => _syncing = false);

    if (report.isSuccess) {
      AppFeedback.success(
        context,
        report.pushed == 0
            ? 'Everything is already up to date'
            : 'Synced ${report.pushed} change'
                  '${report.pushed == 1 ? '' : 's'}',
      );
    } else {
      AppFeedback.warning(
        context,
        '${report.failed} change${report.failed == 1 ? '' : 's'} '
        'could not sync — we will retry',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? last = ref.read(syncCoordinatorProvider.notifier).lastSyncAt;

    return _Tile(
      icon: Icons.sync_rounded,
      title: 'Sync now',
      subtitle: widget.pending > 0
          ? '${widget.pending} pending change'
                '${widget.pending == 1 ? '' : 's'}'
          : last == null
          ? 'Never synced'
          : 'Last synced ${last.formattedWithTime}',
      onTap: _syncing ? () {} : _sync,
      trailing: _syncing
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Badge(isLabelVisible: widget.pending > 0, label: Text('${widget.pending}'), child: const Icon(Icons.chevron_right_rounded, size: 20)),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        final bool confirmed = await AppFeedback.confirm(
          context,
          title: 'Sign out?',
          message:
              'Your data stays on this device and will be here when '
              'you sign back in.',
          confirmLabel: 'Sign out',
        );
        if (!confirmed) return;

        // No navigation here: the router's redirect reacts to the auth state
        // change and takes the user to login.
        await ref.read(authProvider.notifier).logout();
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.error,
        side: BorderSide(color: context.colors.error.withValues(alpha: 0.4)),
      ),
      icon: const Icon(Icons.logout_rounded, size: 18),
      label: const Text('Sign out'),
    );
  }
}
