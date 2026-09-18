import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../providers/auth_providers.dart';

/// Step 3 of password recovery: choose a new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({
    required this.email,
    required this.code,
    super.key,
  });

  final String email;
  final String code;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState
    extends ConsumerState<ResetPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.unfocus();
    setState(() => _submitting = true);

    final Failure? failure = await ref
        .read(passwordResetControllerProvider.notifier)
        .reset(
          email: widget.email,
          code: widget.code,
          newPassword: _password.text,
        );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (failure != null) {
      AppFeedback.error(context, failure);
      return;
    }

    AppFeedback.success(context, 'password_updated_sign_in_to_continue'.tr());
    // `go` rather than `push`: the recovery stack is finished and must not be
    // reachable with the back button.
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('new_password'.tr())),
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
                  Text(
                    'choose_a_new_password'.tr(),
                    style: context.text.headlineSmall,
                  ),
                  AppSpacing.sm.gapH,
                  Text(
                    'make_it_something_you_have_not_used_before'.tr(),
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.xxxl.gapH,

                  AppTextField(
                    controller: _password,
                    label: 'new_password'.tr(),
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: true,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    validator: (String? value) =>
                        (value ?? '').isStrongPassword
                        ? null
                        : 'use_8_characters_with_a_letter_and_a_number'.tr(),
                  ),
                  AppSpacing.lg.gapH,

                  AppTextField(
                    controller: _confirm,
                    label: 'confirm_password'.tr(),
                    prefixIcon: Icons.lock_reset_rounded,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    validator: (String? value) => value == _password.text
                        ? null
                        : 'passwords_do_not_match'.tr(),
                  ),
                  AppSpacing.xxl.gapH,

                  AppButton(
                    label: 'update_password'.tr(),
                    isLoading: _submitting,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),
        ),
      ),
    );
  }
}
