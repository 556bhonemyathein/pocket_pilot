/// Keys used by `SharedPreferences` and `FlutterSecureStorage`.
///
/// Centralising them prevents the classic bug where two features silently
/// disagree about a string literal.
abstract final class StorageKeys {
  // ── Secure storage (encrypted) ──────────────────────────────────────────────
  static const String accessToken = 'pp.secure.access_token';
  static const String refreshToken = 'pp.secure.refresh_token';
  static const String rememberedEmail = 'pp.secure.remembered_email';

  // ── Preferences (plain) ─────────────────────────────────────────────────────
  static const String themeMode = 'pp.pref.theme_mode';
  static const String locale = 'pp.pref.locale';
  static const String currencyCode = 'pp.pref.currency_code';
  static const String onboardingSeen = 'pp.pref.onboarding_seen';
  static const String rememberMe = 'pp.pref.remember_me';
  static const String notificationsEnabled = 'pp.pref.notifications_enabled';
  static const String searchHistory = 'pp.pref.search_history';
}
