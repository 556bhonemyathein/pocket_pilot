import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Change the account password from inside a session.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends ConsumerState<ChangePasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _submitting = false;
  Map<String, List<String>> _fieldErrors = <String, List<String>>{};

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.unfocus();

    setState(() {
      _submitting = true;
      _fieldErrors = <String, List<String>>{};
    });

    final Failure? failure = await ref
        .read(authProvider.notifier)
        .changePassword(
          currentPassword: _current.text,
          newPassword: _next.text,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (failure is ValidationFailure) _fieldErrors = failure.fieldErrors;
    });

    if (failure == null) {
      AppFeedback.success(context, 'password_changed'.tr());
      Navigator.of(context).pop();
    } else if (failure is! ValidationFailure) {
      AppFeedback.error(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('change_password'.tr())),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: <Widget>[
              AppTextField(
                controller: _current,
                label: 'current_password'.tr(),
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: true,
                autofocus: true,
                textInputAction: TextInputAction.next,
                errorText: _fieldErrors['currentPassword']?.firstOrNull,
                validator: (String? value) => (value ?? '').isNotEmpty
                    ? null
                    : 'enter_your_current_password'.tr(),
              ),
              AppSpacing.lg.gapH,

              AppTextField(
                controller: _next,
                label: 'new_password'.tr(),
                prefixIcon: Icons.lock_reset_rounded,
                obscureText: true,
                textInputAction: TextInputAction.next,
                errorText: _fieldErrors['newPassword']?.firstOrNull,
                validator: (String? value) {
                  final String password = value ?? '';
                  if (!password.isStrongPassword) {
                    return 'use_8_characters_with_a_letter_and_a_number'.tr();
                  }
                  if (password == _current.text) {
                    return 'choose_a_password_you_have_not_used_before'.tr();
                  }
                  return null;
                },
              ),
              AppSpacing.lg.gapH,

              AppTextField(
                controller: _confirm,
                label: 'confirm_new_password'.tr(),
                prefixIcon: Icons.check_circle_outline_rounded,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                validator: (String? value) =>
                    value == _next.text ? null : 'passwords_do_not_match'.tr(),
              ),
              AppSpacing.xxxl.gapH,

              AppButton(
                label: 'update_password'.tr(),
                isLoading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
