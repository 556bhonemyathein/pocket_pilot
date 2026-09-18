import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/presentation/providers/settings_providers.dart';
import 'shared/providers/app_config_provider.dart';
import 'shared/providers/sync_providers.dart';

class PocketPilotApp extends ConsumerWidget {
  const PocketPilotApp({super.key});

  static const Set<String> _supportedLocaleCodes = <String>{'en', 'my'};

  static String resolveLocaleCode(String? code) => _supportedLocaleCodes.contains(code) ? code! : 'en';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final GoRouter router = ref.watch(routerProvider);
    final ThemeMode themeMode = ref.watch(persistedThemeModeProvider);

    ref.watch(syncCoordinatorProvider);

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
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
