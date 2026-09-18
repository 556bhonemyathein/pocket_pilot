import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../shared/providers/app_config_provider.dart';
import '../providers/auth_providers.dart';

/// Step 1 of password recovery: request a code.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends ConsumerState<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.unfocus();
    setState(() => _submitting = true);

    final String email = _email.text.trim();
    final result = await ref
        .read(passwordResetControllerProvider.notifier)
        .requestCode(email);

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.failure != null) {
      AppFeedback.error(context, result.failure!);
      return;
    }

    // With the local backend there is no inbox to check, so the code is
    // carried forward and shown on the OTP screen. Against a real API the
    // parameter is simply absent and the user reads it from their email.
    final bool isLocal = ref.read(appConfigProvider).useLocalBackend;
    final String query = isLocal && result.devCode != null
        ? '?email=$email&devCode=${result.devCode}'
        : '?email=$email';

    // Fire-and-forget: the pushed route's result is not needed here.
    unawaited(context.push('${AppRoutes.otp}$query'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('reset_password'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: context.colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(
                      Icons.lock_reset_rounded,
                      size: 34,
                      color: context.colors.primary,
                    ),
                  ),
                  AppSpacing.xl.gapH,
                  Text(
                    'forgot_your_password'.tr(),
                    style: context.text.headlineSmall,
                  ),
                  AppSpacing.sm.gapH,
                  Text(
                    "Enter the email you signed up with and we'll send a "
                    'six-digit verification code.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.xxxl.gapH,

                  AppTextField(
                    controller: _email,
                    label: 'email'.tr(),
                    hint: 'you@example.com',
                    prefixIcon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                    validator: (String? value) => (value ?? '').isValidEmail
                        ? null
                        : 'enter_a_valid_email_address'.tr(),
                  ),
                  AppSpacing.xxl.gapH,

                  AppButton(
                    label: 'send_code'.tr(),
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
        ),
      ),
    );
  }
}
