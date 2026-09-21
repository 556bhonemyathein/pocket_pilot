import 'package:easy_localization/easy_localization.dart';
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
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../settings/presentation/widgets/language_picker.dart';

/// Account hub: identity, shortcuts, sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(currentUserProvider);
    final String language = ref.watch(languageProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(floating: true, titleSpacing: AppSpacing.page, title: Text('profile'.tr())),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 120),
            sliver: SliverList.list(
              children: <Widget>[
                _ProfileHeader(user: user),
                AppSpacing.xxl.gapH,

                _Section(
                  title: 'account'.tr(),
                  tiles: <Widget>[
                    _Tile(
                      icon: Icons.person_outline_rounded,
                      title: 'edit_profile'.tr(),
                      subtitle: 'name_avatar_and_currency'.tr(),
                      onTap: () => context.pushNamed(AppRoutes.editProfile),
                    ),
                    _Tile(icon: Icons.lock_outline_rounded, title: 'change_password'.tr(), onTap: () => context.pushNamed(AppRoutes.changePassword)),
                    _Tile(
                      icon: Icons.category_outlined,
                      title: 'categories'.tr(),
                      subtitle: 'add_edit_and_organise'.tr(),
                      onTap: () => context.pushNamed(AppRoutes.categories),
                    ),
                  ],
                ),
                AppSpacing.xl.gapH,

                _Section(
                  title: 'app'.tr(),
                  tiles: <Widget>[
                    _Tile(
                      icon: Icons.settings_outlined,
                      title: 'settings'.tr(),
                      subtitle: 'theme_language_backup'.tr(),
                      onTap: () => context.pushNamed(AppRoutes.settings),
                    ),
                    _Tile(
                      icon: Icons.language_rounded,
                      title: 'language'.tr(),
                      subtitle: languageLabel(language),
                      onTap: () => pickLanguage(context, ref),
                    ),
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
                Text(user?.name ?? 'signed_out'.tr(), style: context.text.titleMedium, overflow: TextOverflow.ellipsis),
                AppSpacing.xxs.gapH,
                Text(
                  user?.email ?? '',
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
                if (user?.createdAt != null) ...<Widget>[
                  AppSpacing.sm.gapH,
                  Text(
                    'member_since_monthyear'.tr(namedArgs: <String, String>{'monthYear': user!.createdAt!.monthYear}),
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
  const _Tile({required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
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
          title: 'sign_out'.tr(),
          message:
              'your_data_stays_on_this_device_and_will_be_here'.tr(),
          confirmLabel: 'sign_out_2'.tr(),
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
      label: Text('sign_out_2'.tr()),
    );
  }
}
