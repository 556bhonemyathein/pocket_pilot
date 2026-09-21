import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'features/settings/presentation/providers/settings_providers.dart';
import 'shared/providers/app_config_provider.dart';

class PocketPilotApp extends ConsumerWidget {
  const PocketPilotApp({super.key});

  static const Set<String> _supportedLocaleCodes = <String>{'en', 'my'};

  static String resolveLocaleCode(String? code) => _supportedLocaleCodes.contains(code) ? code! : 'en';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(persistedThemeModeProvider);

    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // EasyLocalization owns the live locale; the persisted preference is
      // pushed into it by the settings screen and on first frame in main.dart.
      locale: context.locale,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      localeResolutionCallback: (Locale? locale, Iterable<Locale> supported) {
        if (locale == null) return const Locale('en');
        final String resolved = resolveLocaleCode(locale.languageCode);
        return Locale(resolved);
      },
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
          child: _LanguageSwitchOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Lays the splash over the whole app while a language switch is in flight.
///
/// It sits above the router in `MaterialApp.builder`, so it covers every
/// screen, sheet and the navigation shell while they re-translate.
class _LanguageSwitchOverlay extends ConsumerWidget {
  const _LanguageSwitchOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool switching = ref.watch(languageSwitchingProvider);

    return Stack(
      children: <Widget>[
        child,
        // Absorb taps while covered so nothing underneath reacts mid-switch.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !switching,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: switching ? const SplashScreen(key: ValueKey<String>('language-splash')) : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}
