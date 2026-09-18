import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../providers/auth_providers.dart';

/// Account creation.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _submitting = false;
  Map<String, List<String>> _fieldErrors = <String, List<String>>{};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
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
        .register(name: _name.text.trim(), email: _email.text.trim(), password: _password.text);

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
    return Scaffold(
      appBar: AppBar(title: Text('create_account'.tr())),
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
                    Text('start_tracking_in_under_a_minute'.tr(), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                    AppSpacing.xxl.gapH,

                    AppTextField(
                      controller: _name,
                      label: 'full_name'.tr(),
                      hint: 'Ada Lovelace',
                      prefixIcon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.name],
                      errorText: _fieldErrors['name']?.firstOrNull,
                      validator: (String? value) => (value ?? '').trim().length >= 2 ? null : 'enter_your_name'.tr(),
                    ),
                    AppSpacing.lg.gapH,

                    AppTextField(
                      controller: _email,
                      label: 'email'.tr(),
                      hint: 'you@example.com',
                      prefixIcon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.email],
                      errorText: _fieldErrors['email']?.firstOrNull,
                      validator: (String? value) => (value ?? '').isValidEmail ? null : 'enter_a_valid_email_address'.tr(),
                    ),
                    AppSpacing.lg.gapH,

                    AppTextField(
                      controller: _password,
                      label: 'password'.tr(),
                      hint: 'at_least_8_characters'.tr(),
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const <String>[AutofillHints.newPassword],
                      errorText: _fieldErrors['password']?.firstOrNull,
                      onChanged: (_) => setState(() {}),
                      validator: (String? value) => (value ?? '').isStrongPassword ? null : 'use_8_characters_with_a_letter_and_a_number'.tr(),
                    ),
                    AppSpacing.sm.gapH,
                    _PasswordStrength(password: _password.text),
                    AppSpacing.lg.gapH,

                    AppTextField(
                      controller: _confirm,
                      label: 'confirm_password'.tr(),
                      prefixIcon: Icons.lock_reset_rounded,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      validator: (String? value) => value == _password.text ? null : 'passwords_do_not_match'.tr(),
                    ),
                    AppSpacing.xxl.gapH,

                    AppButton(label: 'create_account'.tr(), isLoading: _submitting, onPressed: _submit),
                    AppSpacing.lg.gapH,
                    Text.rich(
                      TextSpan(
                        text: 'by_continuing_you_agree_to_our_terms_and'.tr(),
                        style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                        children: <InlineSpan>[
                          TextSpan(
                            text: 'privacy_policy'.tr(),
                            style: TextStyle(color: context.colors.primary, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () async {
                                final Uri uri = Uri.parse(AppConstants.privacyPolicyUrl);
                                try {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } catch (_) {}
                              },
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),
        ),
      ),
    );
  }
}

/// Live strength meter.
///
/// Feedback while typing beats an error after submitting: the user can fix the
/// problem before they ever hit a validation message.
class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});

  final String password;

  int get _score {
    if (password.isEmpty) return 0;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score;
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final int score = _score;
    final (String label, Color color) = switch (score) {
      <= 1 => ('weak'.tr(), context.finance.expense),
      2 || 3 => ('fair'.tr(), context.finance.savings),
      _ => ('strong'.tr(), context.finance.income),
    };

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              duration: 250.ms,
              tween: Tween<double>(begin: 0, end: score / 5),
              builder: (BuildContext context, double value, _) =>
                  LinearProgressIndicator(value: value, minHeight: 5, color: color, backgroundColor: context.colors.outlineVariant),
            ),
          ),
        ),
        AppSpacing.md.gapW,
        Text(label, style: context.text.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}
