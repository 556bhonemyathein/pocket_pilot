import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../constants/storage_keys.dart';

/// Typed façade over `SharedPreferences`.
///
/// Features never touch raw string keys or untyped `get` calls; they call
/// intention-revealing methods here. That keeps the "what is stored where"
/// question answerable from a single file, and makes the whole thing trivially
/// fakeable in tests.
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  static const Set<String> _supportedLanguageCodes = <String>{'en', 'es', 'fr', 'de', 'id', 'ar'};

  static Future<PreferencesService> create() async => PreferencesService(await SharedPreferences.getInstance());

  // ── Onboarding / session ────────────────────────────────────────────────────

  bool get onboardingSeen => _prefs.getBool(StorageKeys.onboardingSeen) ?? false;

  Future<void> setOnboardingSeen({required bool value}) => _prefs.setBool(StorageKeys.onboardingSeen, value);

  bool get rememberMe => _prefs.getBool(StorageKeys.rememberMe) ?? true;

  Future<void> setRememberMe({required bool value}) => _prefs.setBool(StorageKeys.rememberMe, value);

  // ── Appearance ──────────────────────────────────────────────────────────────

  ThemeMode get themeMode {
    final String? raw = _prefs.getString(StorageKeys.themeMode);
    return ThemeMode.values.firstWhere((ThemeMode m) => m.name == raw, orElse: () => ThemeMode.system);
  }

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(StorageKeys.themeMode, mode.name);

  String get languageCode {
    final String code = _prefs.getString(StorageKeys.locale) ?? 'en';
    return _supportedLanguageCodes.contains(code) ? code : 'en';
  }

  Future<void> setLanguageCode(String code) async {
    final String normalized = _supportedLanguageCodes.contains(code) ? code : 'en';
    await _prefs.setString(StorageKeys.locale, normalized);
  }

  String get currencyCode => _prefs.getString(StorageKeys.currencyCode) ?? 'USD';

  Future<void> setCurrencyCode(String code) => _prefs.setString(StorageKeys.currencyCode, code);

  bool get notificationsEnabled => _prefs.getBool(StorageKeys.notificationsEnabled) ?? true;

  Future<void> setNotificationsEnabled({required bool value}) => _prefs.setBool(StorageKeys.notificationsEnabled, value);

  // ── Search history ──────────────────────────────────────────────────────────

  List<String> get searchHistory => _prefs.getStringList(StorageKeys.searchHistory) ?? const <String>[];

  /// Most-recent-first, de-duplicated, capped. Keeping the trimming logic here
  /// means the search UI never has to think about it.
  Future<void> pushSearchTerm(String term) async {
    final String trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final List<String> history = <String>[
      trimmed,
      ...searchHistory.where((String t) => t.toLowerCase() != trimmed.toLowerCase()),
    ].take(AppConstants.searchHistoryLimit).toList();
    await _prefs.setStringList(StorageKeys.searchHistory, history);
  }

  Future<void> clearSearchHistory() => _prefs.remove(StorageKeys.searchHistory);

  // ── Backup / restore ────────────────────────────────────────────────────────

  /// Serialises every preference so "Backup" can bundle settings alongside the
  /// Isar rows.
  String exportJson() => jsonEncode(<String, Object?>{
    StorageKeys.themeMode: themeMode.name,
    StorageKeys.locale: languageCode,
    StorageKeys.currencyCode: currencyCode,
    StorageKeys.notificationsEnabled: notificationsEnabled,
    StorageKeys.onboardingSeen: onboardingSeen,
  });

  Future<void> importJson(String raw) async {
    final Map<String, dynamic> map = jsonDecode(raw) as Map<String, dynamic>;
    for (final MapEntry<String, dynamic> entry in map.entries) {
      final Object? value = entry.value;
      if (value is bool) {
        await _prefs.setBool(entry.key, value);
      } else if (value is String) {
        await _prefs.setString(entry.key, value);
      } else if (value is int) {
        await _prefs.setInt(entry.key, value);
      }
    }
  }

  Future<void> clear() => _prefs.clear();
}
