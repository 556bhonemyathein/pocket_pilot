/// Relative REST paths. They are appended to `AppConfig.apiBaseUrl` by Dio,
/// so no endpoint here should ever contain a host.
abstract final class ApiEndpoints {
  // ── Auth ────────────────────────────────────────────────────────────────────
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String forgotPassword = '/auth/forgot-password';
  static const String verifyOtp = '/auth/verify-otp';
  static const String resetPassword = '/auth/reset-password';
  static const String changePassword = '/auth/change-password';

  // ── Profile ─────────────────────────────────────────────────────────────────
  static const String me = '/users/me';
  static const String avatar = '/users/me/avatar';
  static const String deleteAccount = '/users/me';

  // ── Transactions ────────────────────────────────────────────────────────────
  static const String transactions = '/transactions';
  static String transaction(String id) => '/transactions/$id';

  // ── Categories ──────────────────────────────────────────────────────────────
  static const String categories = '/categories';
  static String category(String id) => '/categories/$id';

  // ── Reports ─────────────────────────────────────────────────────────────────
  static const String summary = '/reports/summary';
  static const String reports = '/reports';

  // ── Devices / notifications ─────────────────────────────────────────────────
  static const String registerDevice = '/devices';
}
