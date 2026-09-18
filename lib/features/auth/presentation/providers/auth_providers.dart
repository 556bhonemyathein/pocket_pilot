import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/providers/app_config_provider.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/auth_local_datasource.dart';
import '../../data/auth_remote_datasource.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/auth_repository.dart';

// ── Wiring ────────────────────────────────────────────────────────────────────

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>(
  (Ref ref) => AuthLocalDataSource(ref.watch(isarServiceProvider)),
  name: 'authLocalDataSource',
);

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (Ref ref) => AuthRemoteDataSource(ref.watch(dioProvider)),
  name: 'authRemoteDataSource',
);

/// The UI depends on the *interface*, never on the implementation. Swapping in
/// a fake in tests is one `overrideWithValue` away.
final authRepositoryProvider = Provider<AuthRepository>(
  (Ref ref) => AuthRepositoryImpl(
    local: ref.watch(authLocalDataSourceProvider),
    remote: ref.watch(authRemoteDataSourceProvider),
    secureStorage: ref.watch(secureStorageProvider),
    preferences: ref.watch(preferencesServiceProvider),
    config: ref.watch(appConfigProvider),
  ),
  name: 'authRepository',
);

// ── State ─────────────────────────────────────────────────────────────────────

/// Where the user stands with respect to authentication.
///
/// A sealed hierarchy rather than a bag of booleans (`isLoading`,
/// `isLoggedIn`, `hasError`) — those admit impossible combinations, this does
/// not, and `switch` over it is exhaustive.
sealed class AuthState {
  const AuthState();

  AppUser? get user => switch (this) {
    Authenticated(:final user) => user,
    _ => null,
  };

  bool get isAuthenticated => this is Authenticated;
}

/// Boot-time: we do not yet know whether a session exists.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class Unauthenticated extends AuthState {
  const Unauthenticated({this.reason});

  /// Set when the user was kicked out (expired refresh token) rather than
  /// having chosen to sign out — the login screen explains why.
  final String? reason;
}

class Authenticated extends AuthState {
  const Authenticated(this.user);

  @override
  final AppUser user;
}

/// Owns the session for the whole app.
///
/// [AsyncNotifier] is the right primitive: the initial state must be *loaded*
/// (secure storage + Isar are both async), and every command below is an async
/// operation whose loading/error state the UI needs. `AsyncValue` gives that
/// for free — no manual `isLoading` flags anywhere.
class AuthNotifier extends AsyncNotifier<AuthState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    // React to the interceptor giving up on token refresh.
    ref.listen<bool>(sessionExpiredProvider, (bool? previous, bool next) {
      if (next) {
        state = AsyncData<AuthState>(
          Unauthenticated(reason: 'your_session_expired_please_sign_in'.tr()),
        );
        ref.read(sessionExpiredProvider.notifier).acknowledge();
      }
    });

    final Result<AuthSession?> result = await _repository.restoreSession();
    return result.when(
      success: (AuthSession? session) => session == null
          ? const Unauthenticated()
          : Authenticated(session.user),
      failure: (Failure _) => const Unauthenticated(),
    );
  }

  /// Runs [action] with proper loading/error transitions and reports the
  /// failure (if any) back to the caller so the form can show field errors.
  ///
  /// Returning the `Failure` instead of throwing keeps the call site in the
  /// widget simple: `final failure = await notifier.login(...)`.
  Future<Failure?> _run(Future<Result<AuthState>> Function() action) async {
    state = const AsyncLoading<AuthState>();
    final Result<AuthState> result = await action();
    return result.when(
      success: (AuthState next) {
        state = AsyncData<AuthState>(next);
        return null;
      },
      failure: (Failure failure) {
        // Stay unauthenticated but keep the app usable — an auth error is a
        // form-level problem, not a screen-level crash.
        state = const AsyncData<AuthState>(Unauthenticated());
        return failure;
      },
    );
  }

  Future<Failure?> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) => _run(() async {
    final Result<AuthSession> result = await _repository.login(
      email: email,
      password: password,
      rememberMe: rememberMe,
    );
    return result.map<AuthState>(
      (AuthSession session) => Authenticated(session.user),
    );
  });

  Future<Failure?> register({
    required String name,
    required String email,
    required String password,
  }) => _run(() async {
    final Result<AuthSession> result = await _repository.register(
      name: name,
      email: email,
      password: password,
    );
    return result.map<AuthState>(
      (AuthSession session) => Authenticated(session.user),
    );
  });

  Future<Failure?> logout() => _run(() async {
    final Result<void> result = await _repository.logout();
    return result.map<AuthState>((_) => const Unauthenticated());
  });

  Future<Failure?> deleteAccount() => _run(() async {
    final Result<void> result = await _repository.deleteAccount();
    return result.map<AuthState>((_) => const Unauthenticated());
  });

  /// Profile edits keep the user signed in, so they bypass [_run].
  Future<Failure?> updateProfile(AppUser user) async {
    final Result<AppUser> result = await _repository.updateProfile(user);
    return result.when(
      success: (AppUser updated) {
        state = AsyncData<AuthState>(Authenticated(updated));
        return null;
      },
      failure: (Failure failure) => failure,
    );
  }

  Future<Failure?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final Result<void> result = await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    return result.failureOrNull;
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
  name: 'auth',
);

/// The signed-in user, or `null`. Most screens want this rather than the full
/// [AuthState], and watching it means they only rebuild when the *user*
/// changes — not on every loading transition.
final currentUserProvider = Provider<AppUser?>(
  (Ref ref) => ref.watch(authProvider).value?.user,
  name: 'currentUser',
);

/// The user's display currency, defaulting to the device preference.
final currencyCodeProvider = Provider<String>((Ref ref) {
  final AppUser? user = ref.watch(currentUserProvider);
  return user?.currencyCode ?? ref.watch(preferencesServiceProvider).currencyCode;
}, name: 'currencyCode');

/// Password-recovery providers — kept out of [AuthNotifier] because they are a
/// short-lived flow, not session state. `autoDispose` (the Riverpod 3 default)
/// means the pending email/code is dropped the moment the flow is left.
final passwordResetControllerProvider =
    AsyncNotifierProvider<PasswordResetController, String?>(
      PasswordResetController.new,
      name: 'passwordReset',
    );

/// Drives forgot-password → OTP → new password.
///
/// State is the email a code was sent to (`null` before the flow starts).
class PasswordResetController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  /// Returns the dev-visible OTP when the local backend issued one.
  Future<({Failure? failure, String? devCode})> requestCode(
    String email,
  ) async {
    state = const AsyncLoading<String?>();
    final Result<String> result = await ref
        .read(authRepositoryProvider)
        .requestPasswordReset(email);

    return result.when(
      success: (String code) {
        state = AsyncData<String?>(email);
        return (failure: null, devCode: code);
      },
      failure: (Failure failure) {
        state = const AsyncData<String?>(null);
        return (failure: failure, devCode: null);
      },
    );
  }

  Future<Failure?> verify({required String email, required String code}) async {
    final Result<bool> result = await ref
        .read(authRepositoryProvider)
        .verifyOtp(email: email, code: code);
    return result.failureOrNull;
  }

  Future<Failure?> reset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final Result<void> result = await ref
        .read(authRepositoryProvider)
        .resetPassword(email: email, code: code, newPassword: newPassword);
    return result.failureOrNull;
  }
}

/// Email pre-filled into the login form when "Remember me" was used.
/// A `FutureProvider` is exactly the right shape: read once, async, no writes.
final rememberedEmailProvider = FutureProvider<String?>(
  (Ref ref) => ref.watch(authRepositoryProvider).rememberedEmail(),
  name: 'rememberedEmail',
);
