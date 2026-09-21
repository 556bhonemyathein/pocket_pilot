import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../providers/settings_providers.dart';

/// Display label for a language code, falling back to the first entry.
String languageLabel(String code) =>
    kSupportedLanguages.firstWhere((({String code, String label}) l) => l.code == code, orElse: () => kSupportedLanguages.first).label;

/// Opens the language sheet and, on a pick, persists the preference and
/// switches the live locale so every screen re-renders in the new language.
///
/// Shared by the Settings and Profile screens so both entry points behave
/// identically.
Future<void> pickLanguage(BuildContext context, WidgetRef ref) async {
  final String current = ref.read(languageProvider);
  final String? picked = await AppFeedback.sheet<String>(
    context,
    child: AppBottomSheet(
      title: 'language'.tr(),
      child: Column(
        children: <Widget>[
          for (final ({String code, String label}) language in kSupportedLanguages)
            ListTile(
              title: Text(language.label),
              trailing: language.code == current ? Icon(Icons.check_circle_rounded, color: context.colors.primary) : null,
              onTap: () => Navigator.of(context).pop(language.code),
            ),
        ],
      ),
    ),
  );

  if (picked == null || picked == current) return;

  // Cover the UI with the splash before the locale flips so the re-render
  // happens behind it, then hold it long enough to read as a deliberate
  // transition rather than a flicker.
  final LanguageSwitchingNotifier overlay = ref.read(languageSwitchingProvider.notifier);
  overlay.switching = true;
  await Future<void>.delayed(_splashFadeIn);

  await ref.read(languageProvider.notifier).setLanguage(picked);
  if (context.mounted) {
    await context.setLocale(Locale(picked));
  }
  await Future<void>.delayed(_splashHold);
  overlay.switching = false;

  if (context.mounted) {
    AppFeedback.info(context, 'language_updated'.tr());
  }
}

/// Time for the overlay to fade in before the locale changes underneath it.
const Duration _splashFadeIn = Duration(milliseconds: 350);

/// How long the splash stays up after the locale has switched.
const Duration _splashHold = Duration(milliseconds: 900);
