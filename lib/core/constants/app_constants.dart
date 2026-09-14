/// App-wide, flavor-independent constants.
///
/// Anything that varies per environment belongs in `AppConfig`, not here.
abstract final class AppConstants {
  static const String appName = 'PocketPilot';
  static const String appTagline = 'Fly through your finances.';

  /// Default page size used by every paginated list (transactions, search…).
  static const int pageSize = 20;

  /// Debounce applied to realtime search fields.
  static const Duration searchDebounce = Duration(milliseconds: 350);

  /// How long an "Undo" snackbar stays on screen after a swipe-delete.
  static const Duration undoWindow = Duration(seconds: 5);

  /// Standard motion durations. Using a shared scale keeps the whole app
  /// feeling like one product instead of a collection of screens.
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);

  /// Maximum number of remembered search terms.
  static const int searchHistoryLimit = 10;

  /// Number of automatic retries for idempotent network calls.
  static const int maxNetworkRetries = 3;

  static const String privacyPolicyUrl = 'https://github.com/556bhonemyathein/-Privacy-Policy-url';
  static const String supportEmail = 'support@pocketpilot.app';
}
