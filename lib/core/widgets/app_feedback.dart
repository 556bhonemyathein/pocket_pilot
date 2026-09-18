import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../errors/failure.dart';
import '../extensions/extensions.dart';
import '../theme/app_dimens.dart';
import 'app_button.dart';

/// Snackbars, dialogs and bottom sheets in one consistent voice.
///
/// Every transient message in the app goes through here. That is what stops
/// one screen showing a red banner, another a grey toast and a third an
/// `AlertDialog` for the same class of event.
abstract final class AppFeedback {
  // ── Snackbars ───────────────────────────────────────────────────────────────

  static void success(BuildContext context, String message) =>
      _show(context, message, icon: Icons.check_circle_outline_rounded,
          color: context.finance.income);

  static void info(BuildContext context, String message) =>
      _show(context, message, icon: Icons.info_outline_rounded,
          color: context.colors.primary);

  static void warning(BuildContext context, String message) =>
      _show(context, message, icon: Icons.warning_amber_rounded,
          color: context.finance.savings);

  /// Renders a [Failure]'s user-safe message — never the debug detail.
  static void error(BuildContext context, Failure failure) => _show(
    context,
    failure.message,
    icon: Icons.error_outline_rounded,
    color: context.colors.error,
  );

  /// Confirmation with an Undo affordance.
  ///
  /// Undo is what makes swipe-to-delete safe: the row is tombstoned
  /// immediately (so the list feels instant) and [onUndo] restores it inside
  /// the window.
  static void undo(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        duration: AppConstants.undoWindow,
        content: Text(message),
        action: SnackBarAction(label: 'undo'.tr(), onPressed: onUndo),
      ),
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              Icon(icon, color: color, size: 20),
              AppSpacing.md.gapW,
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  /// Returns `true` only if the user explicitly confirmed.
  ///
  /// Defaulting to `false` on dismiss is deliberate: tapping the scrim must
  /// never be read as consent for a destructive action.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDestructive = false,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel ?? 'cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: dialogContext.colors.error,
                    foregroundColor: dialogContext.colors.onError,
                  )
                : null,
            child: Text(confirmLabel ?? 'confirm'.tr()),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Bottom sheets ───────────────────────────────────────────────────────────

  /// Scroll-safe, keyboard-aware modal sheet.
  ///
  /// `isScrollControlled` plus the view-inset padding is what stops a sheet
  /// containing a text field from being swallowed by the keyboard — the single
  /// most common bottom-sheet bug in Flutter apps.
  static Future<T?> sheet<T>(
    BuildContext context, {
    required Widget child,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: sheetContext.keyboardInset),
        child: child,
      ),
    );
  }
}

/// Standard sheet chrome: title, optional action, and a body.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    required this.title,
    required this.child,
    super.key,
    this.actionLabel,
    this.onAction,
    this.isActionLoading = false,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isActionLoading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.page,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: context.text.titleLarge),
            AppSpacing.lg.gapH,
            Flexible(child: SingleChildScrollView(child: child)),
            if (actionLabel != null) ...<Widget>[
              AppSpacing.xl.gapH,
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                isLoading: isActionLoading,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
