import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Theme mode, persisted.
///
/// Replaces the in-memory notifier from the foundation step: [build] now reads
/// the saved value so the choice survives a restart, and every write goes
/// through `PreferencesService`.
class PersistedThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(preferencesServiceProvider).themeMode;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesServiceProvider).setThemeMode(mode);
  }
}

final persistedThemeModeProvider = NotifierProvider<PersistedThemeModeNotifier, ThemeMode>(
  PersistedThemeModeNotifier.new,
  name: 'persistedThemeMode',
);

/// Selected app language.
class LanguageNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(preferencesServiceProvider).languageCode;

  Future<void> setLanguage(String code) async {
    state = code;
    await ref.read(preferencesServiceProvider).setLanguageCode(code);
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, String>(LanguageNotifier.new, name: 'language');

/// Languages the app ships translations for.
const List<({String code, String label})> kSupportedLanguages = <({String code, String label})>[
  (code: 'en', label: 'English'),
  (code: 'my', label: 'မြန်မာ'),
];

/// Notification preference.
class NotificationsNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(preferencesServiceProvider).notificationsEnabled;

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    await ref.read(preferencesServiceProvider).setNotificationsEnabled(value: enabled);
  }
}

final notificationsEnabledProvider = NotifierProvider<NotificationsNotifier, bool>(NotificationsNotifier.new, name: 'notificationsEnabled');

/// Backup and restore.
///
/// The backup is a single JSON document containing both the preferences and
/// every transaction. Keeping it self-describing (with a `version` field)
/// means a future schema change can migrate old backups rather than reject
/// them.
class BackupService {
  const BackupService(this._ref);

  final Ref _ref;

  static const int formatVersion = 1;

  Future<Result<File>> export() => guard(() async {
    final result = await _ref.read(transactionRepositoryProvider).exportAll();
    final List<Transaction> transactions = result.getOrThrow();

    final Map<String, Object?> payload = <String, Object?>{
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': jsonDecode(_ref.read(preferencesServiceProvider).exportJson()),
      'transactions': transactions.map((Transaction t) => t.toJson()).toList(),
    };

    final Directory directory = await getTemporaryDirectory();
    final File file = File(
      '${directory.path}/pocketpilot-backup-'
      '${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(payload));
    return file;
  });

  Future<Result<int>> restore(String raw) => guard(() async {
    final Map<String, dynamic> payload = jsonDecode(raw) as Map<String, dynamic>;

    final int version = payload['version'] as int? ?? 0;
    if (version > formatVersion) {
      throw const ValidationFailure('This backup was made by a newer version of PocketPilot');
    }

    final preferences = payload['preferences'];
    if (preferences != null) {
      await _ref.read(preferencesServiceProvider).importJson(jsonEncode(preferences));
    }

    final List<dynamic> rows = payload['transactions'] as List<dynamic>? ?? const <dynamic>[];
    final List<Transaction> transactions = rows.map((dynamic row) => Transaction.fromJson(row as Map<String, dynamic>)).toList();

    final imported = await _ref.read(transactionRepositoryProvider).importAll(transactions);
    return imported.getOrThrow();
  });
}

final backupServiceProvider = Provider<BackupService>(BackupService.new, name: 'backupService');
