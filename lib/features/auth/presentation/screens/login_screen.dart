import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../providers/auth_providers.dart';

/// Sign-in.
///
/// Note what this screen does *not* do: it never navigates on success. The
/// router's redirect reacts to the auth state changing and moves the user to
/// the dashboard. That keeps a single source of truth for "where should the
/// user be", instead of every screen pushing routes imperatively.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _rememberMe = true;
  bool _submitting = false;

  /// Field-level errors returned by the backend, cleared on the next attempt.
  Map<String, List<String>> _fieldErrors = <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    // Pre-fill the remembered email so returning users only type a password.
    ref.read(rememberedEmailProvider.future).then((String? email) {
      if (email != null && mounted) _email.text = email;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
        .login(
          email: _email.text.trim(),
          password: _password.text,
          rememberMe: _rememberMe,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (failure is ValidationFailure) _fieldErrors = failure.fieldErrors;
    });

    if (failure != null && failure is! ValidationFailure) {
      AppFeedback.error(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A reason is set when the user was signed out involuntarily.
    final AuthState? state = ref.watch(authProvider).value;
    final String? reason = state is Unauthenticated ? state.reason : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppSpacing.xxl.gapH,
                    Text('welcome_back'.tr(), style: context.text.displaySmall),
                    AppSpacing.sm.gapH,
                    Text(
                      'sign_in_to_keep_flying_through_your_finances'.tr(),
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (reason != null) ...<Widget>[
                      AppSpacing.lg.gapH,
                      _Notice(message: reason),
                    ],
                    AppSpacing.xxxl.gapH,

                    AppTextField(
                      controller: _email,
                      label: 'email'.tr(),
                      hint: 'you@example.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                      errorText: _fieldErrors['email']?.firstOrNull,
                      validator: (String? value) =>
                          (value ?? '').isValidEmail
                          ? null
                          : 'enter_a_valid_email_address'.tr(),
                    ),
                    AppSpacing.lg.gapH,

                    AppTextField(
                      controller: _password,
                      label: 'password'.tr(),
                      hint: '••••••••',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      errorText: _fieldErrors['password']?.firstOrNull,
                      onSubmitted: (_) => _submit(),
                      validator: (String? value) =>
                          (value ?? '').isNotEmpty
                          ? null
                          : 'enter_your_password'.tr(),
                    ),
                    AppSpacing.sm.gapH,

                    Row(
                      children: <Widget>[
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (bool? value) =>
                              setState(() => _rememberMe = value ?? false),
                        ),
                        Text('remember_me'.tr()),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              context.push(AppRoutes.forgotPassword),
                          child: Text('forgot_password'.tr()),
                        ),
                      ],
                    ),
                    AppSpacing.lg.gapH,

                    AppButton(
                      label: 'sign_in'.tr(),
                      isLoading: _submitting,
                      onPressed: _submit,
                    ),
                    AppSpacing.xl.gapH,

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "Don't have an account?",
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push(AppRoutes.register),
                          child: Text('create_one'.tr()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: AppConstants.durationMedium).slideY(
            begin: 0.05,
            curve: Curves.easeOut,
          ),
        ),
      ),
    );
  }
}

/// Inline explanation shown when the user was signed out involuntarily.
class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.finance.savings.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: context.finance.savings,
          ),
          AppSpacing.sm.gapW,
          Expanded(child: Text(message, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}
