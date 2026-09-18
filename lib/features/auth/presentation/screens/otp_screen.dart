import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../shared/providers/app_config_provider.dart';
import '../providers/auth_providers.dart';

/// Step 2 of password recovery: verify the six-digit code.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({required this.email, super.key});

  final String email;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  /// One controller and one focus node per box.
  final List<TextEditingController> _controllers = List<TextEditingController>
      .generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List<FocusNode>.generate(6, (_) => FocusNode());

  bool _submitting = false;
  String? _error;

  /// Resend cooldown, counted down by a timer.
  int _cooldown = 30;
  Timer? _timer;

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _startCooldown();

    // The local backend has no inbox, so the code arrives as a query
    // parameter and is pre-filled — the flow stays completable in a demo.
    final String? devCode =
        GoRouterState.of(context).uri.queryParameters['devCode'];
    if (devCode != null && devCode.length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fill(devCode));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    for (final FocusNode n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  void _fill(String code) {
    for (int i = 0; i < code.length && i < 6; i++) {
      _controllers[i].text = code[i];
    }
    setState(() {});
  }

  /// Advances focus as digits are entered and retreats on delete, which is
  /// what makes a segmented code field feel like one input rather than six.
  void _onDigitChanged(int index, String value) {
    setState(() => _error = null);

    if (value.length > 1) {
      // A paste landed in one box — distribute it across the row.
      _fill(value.replaceAll(RegExp(r'\D'), ''));
      _nodes.last.requestFocus();
      return;
    }
    if (value.isNotEmpty && index < 5) {
      _nodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }

    if (_code.length == 6) _submit();
  }

  Future<void> _submit() async {
    if (_code.length != 6) {
      setState(() => _error = 'enter_all_six_digits'.tr());
      return;
    }
    context.unfocus();
    setState(() => _submitting = true);

    final Failure? failure = await ref
        .read(passwordResetControllerProvider.notifier)
        .verify(email: widget.email, code: _code);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = failure?.message;
    });

    if (failure == null) {
      // Fire-and-forget: the pushed route's result is not needed here.
      unawaited(
        context.push(
          '${AppRoutes.resetPassword}?email=${widget.email}&code=$_code',
        ),
      );
    }
  }

  Future<void> _resend() async {
    final result = await ref
        .read(passwordResetControllerProvider.notifier)
        .requestCode(widget.email);

    if (!mounted) return;
    if (result.failure != null) {
      AppFeedback.error(context, result.failure!);
      return;
    }

    _startCooldown();
    if (ref.read(appConfigProvider).useLocalBackend &&
        result.devCode != null) {
      _fill(result.devCode!);
    }
    if (mounted) AppFeedback.info(context, 'a_new_code_is_on_its_way'.tr());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('verify_code'.tr())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('check_your_inbox'.tr(), style: context.text.headlineSmall),
                AppSpacing.sm.gapH,
                Text.rich(
                  TextSpan(
                    text: 'we_sent_a_six_digit_code_to'.tr(),
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                    children: <InlineSpan>[
                      TextSpan(
                        text: widget.email,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: context.colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.xxxl.gapH,

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    for (int i = 0; i < 6; i++)
                      _OtpBox(
                        controller: _controllers[i],
                        focusNode: _nodes[i],
                        hasError: _error != null,
                        onChanged: (String value) => _onDigitChanged(i, value),
                      ),
                  ],
                ),

                if (_error != null) ...<Widget>[
                  AppSpacing.md.gapH,
                  Text(
                    _error!,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ],
                AppSpacing.xxl.gapH,

                AppButton(
                  label: 'verify'.tr(),
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
                AppSpacing.lg.gapH,

                Center(
                  child: _cooldown > 0
                      ? Text(
                          'resend_code_in_cooldown_s'.tr(namedArgs: <String, String>{'_cooldown': '$_cooldown'}),
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        )
                      : TextButton(
                          onPressed: _resend,
                          child: Text('resend_code'.tr()),
                        ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool filled = controller.text.isNotEmpty;

    return AnimatedContainer(
      duration: 180.ms,
      height: 58,
      width: 48,
      decoration: BoxDecoration(
        color: context.theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: hasError
              ? context.colors.error
              : filled
              ? context.colors.primary
              : context.colors.outlineVariant,
          width: filled || hasError ? 1.6 : 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          style: context.text.headlineSmall,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
