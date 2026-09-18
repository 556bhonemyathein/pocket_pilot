import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/providers/app_config_provider.dart';

/// App identity, version and credits.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: Text('about'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  height: 88,
                  width: 88,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: context.finance.balanceGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: const Icon(
                    Icons.savings_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                AppSpacing.lg.gapH,
                Text(
                  AppConstants.appName,
                  style: context.text.headlineSmall,
                ),
                AppSpacing.xs.gapH,
                Text(
                  AppConstants.appTagline,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08),
          ),
          AppSpacing.xxxl.gapH,

          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: <Widget>[
                _InfoRow(label: 'version'.tr(), value: '1.0.0 (1)'),
                const Divider(height: 1),
                _InfoRow(label: 'build'.tr(), value: config.flavor.label),
                const Divider(height: 1),
                _InfoRow(
                  label: 'backend'.tr(),
                  value: config.useLocalBackend
                      ? 'on_device'.tr()
                      : config.apiBaseUrl,
                ),
                const Divider(height: 1),
                _InfoRow(
                  label: 'support'.tr(),
                  value: AppConstants.supportEmail,
                ),
              ],
            ),
          ),
          AppSpacing.xl.gapH,

          Text(
            'built_with_flutter_riverpod_and_isar_your_data_l'.tr(),
            textAlign: TextAlign.center,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: context.text.bodyMedium),
      trailing: Text(
        value,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
