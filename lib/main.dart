import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/isar_service.dart';
import 'core/storage/preferences_service.dart';
import 'core/utils/app_logger.dart';
import 'features/categories/presentation/providers/category_providers.dart';
import 'features/transactions/presentation/providers/transaction_providers.dart';
import 'shared/providers/app_config_provider.dart';
import 'shared/providers/core_providers.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await EasyLocalization.ensureInitialized();

      final AppConfig config = AppConfig.fromEnvironment();
      AppLogger.configure(enabled: config.enableLogging);
      AppLogger.i('Booting ${config.appName} (${config.flavor.label})');

      final IsarService isar = await IsarService.open();
      final PreferencesService preferences = await PreferencesService.create();

      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
      );

      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.e('FlutterError', details.exception, details.stack);
        FlutterError.presentError(details);
      };

      final ProviderContainer container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          isarServiceProvider.overrideWithValue(isar),
          preferencesServiceProvider.overrideWithValue(preferences),
        ],
        observers: config.enableLogging ? <ProviderObserver>[_LoggingProviderObserver()] : const <ProviderObserver>[],
      );

      await _runStartupTasks(container);

      final String startLanguage = PocketPilotApp.resolveLocaleCode(preferences.languageCode);

      runApp(
        EasyLocalization(
          supportedLocales: const <Locale>[Locale('en'), Locale('my')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: Locale(startLanguage),
          useOnlyLangCode: true,
          child: UncontrolledProviderScope(container: container, child: const PocketPilotApp()),
        ),
      );
    },
    (Object error, StackTrace stack) {
      AppLogger.e('Uncaught zone error', error, stack);
    },
  );
}

Future<void> _runStartupTasks(ProviderContainer container) async {
  try {
    await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();

    await container.read(transactionRepositoryProvider).materialiseRecurring();
  } catch (error, stackTrace) {
    AppLogger.e('Startup task failed', error, stackTrace);
  }
}

final class _LoggingProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) {
    AppLogger.d(
      '[riverpod] ${context.provider.name ?? context.provider.runtimeType} '
      '=> $newValue',
    );
  }

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) {
    AppLogger.e(
      '[riverpod] ${context.provider.name ?? context.provider.runtimeType} '
      'failed',
      error,
      stackTrace,
    );
  }
}
