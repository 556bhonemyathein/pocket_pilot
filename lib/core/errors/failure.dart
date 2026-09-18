import 'package:easy_localization/easy_localization.dart';

import 'app_exception.dart';

/// A *presentation-safe* error.
///
/// Repositories never let an [AppException] escape to the UI: they map it to a
/// [Failure] carrying a message that is safe and friendly to show a user.
/// Modelled as a sealed class so `switch` over failures is exhaustive — the
/// compiler tells us when a new failure type needs UI handling.
///
/// Implements `Exception` so a repository can rethrow a failure it received
/// from a nested call without unwrapping and re-wrapping it.
sealed class Failure implements Exception {
  const Failure(this.rawMessage, {this.debugMessage});

  /// Either a translation key (the built-in failures) or literal text handed
  /// in by a caller. Kept raw so the constructors can stay `const`.
  final String rawMessage;

  /// User-facing, already-friendly text in the active locale. A literal
  /// message that is not a key passes through unchanged.
  String get message => rawMessage.tr();

  /// Technical detail: logged and reported, never rendered.
  final String? debugMessage;

  /// Whether offering a "Retry" button makes sense for this failure.
  bool get isRetryable => switch (this) {
    NetworkFailure() || TimeoutFailure() || ServerFailure() => true,
    _ => false,
  };

  @override
  String toString() => '$runtimeType($message)';
}

class NetworkFailure extends Failure {
  const NetworkFailure({
    String message = 'failure_offline',
    super.debugMessage,
  }) : super(message);
}

class TimeoutFailure extends Failure {
  const TimeoutFailure({
    String message = 'failure_timeout',
    super.debugMessage,
  }) : super(message);
}

class ServerFailure extends Failure {
  const ServerFailure({
    String message = 'failure_server',
    super.debugMessage,
  }) : super(message);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({
    String message = 'failure_unauthorized',
    super.debugMessage,
  }) : super(message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(
    super.message, {
    this.fieldErrors = const {},
    super.debugMessage,
  });

  /// Field name → messages, ready to bind to form fields.
  final Map<String, List<String>> fieldErrors;

  /// First message for [field], if the backend rejected it.
  String? errorFor(String field) => fieldErrors[field]?.firstOrNull;
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({
    String message = 'failure_not_found',
    super.debugMessage,
  }) : super(message);
}

class CacheFailure extends Failure {
  const CacheFailure({
    String message = 'failure_cache',
    super.debugMessage,
  }) : super(message);
}

class CancelledFailure extends Failure {
  const CancelledFailure({
    String message = 'failure_cancelled',
    super.debugMessage,
  }) : super(message);
}

class UnknownFailure extends Failure {
  const UnknownFailure({
    String message = 'failure_unknown',
    super.debugMessage,
  }) : super(message);
}

/// Single place that translates data-layer exceptions into UI failures.
///
/// One mapper (instead of a bespoke `try/catch` per repository method) is what
/// keeps error handling consistent across every feature.
abstract final class FailureMapper {
  static Failure from(Object error, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    if (error is AppException) {
      final String debug = error.toString();
      return switch (error) {
        NetworkException() => NetworkFailure(debugMessage: debug),
        TimeoutException() => TimeoutFailure(debugMessage: debug),
        UnauthorizedException() => UnauthorizedFailure(debugMessage: debug),
        ValidationException(:final message, :final fieldErrors) =>
          ValidationFailure(
            message,
            fieldErrors: fieldErrors,
            debugMessage: debug,
          ),
        NotFoundException() => NotFoundFailure(debugMessage: debug),
        ServerException() => ServerFailure(debugMessage: debug),
        CacheException() => CacheFailure(debugMessage: debug),
        CancelledException() => CancelledFailure(debugMessage: debug),
        UnknownException() => UnknownFailure(debugMessage: debug),
      };
    }

    return UnknownFailure(debugMessage: '$error\n$stackTrace');
  }
}
