import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/categories/presentation/screens/categories_screen.dart';
import '../../features/categories/presentation/screens/category_form_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/profile/presentation/screens/change_password_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/transactions/presentation/screens/transaction_form_screen.dart';
import '../../features/transactions/presentation/screens/transaction_search_screen.dart';
import '../../features/transactions/presentation/screens/transactions_screen.dart';
import '../../shared/models/enums.dart';
import '../../shared/models/transaction.dart';
import '../../shared/providers/core_providers.dart';
import '../widgets/app_shell.dart';
import 'app_routes.dart';

/// The app's router.
///
/// Two design points worth naming:
///
/// **Redirect owns the auth gate.** Rather than each screen checking whether a
/// user exists, `redirect` runs before every navigation and is the single
/// place that decides. A screen can therefore assume it is only ever built for
/// a valid state.
///
/// **`refreshListenable` bridges Riverpod to go_router.** go_router needs a
/// `Listenable` to know when to re-evaluate `redirect`; [_RouterRefresh] turns
/// the auth provider into one, so signing out redirects instantly from
/// wherever the user happens to be.
final routerProvider = Provider<GoRouter>((Ref ref) {
  final _RouterRefresh refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final AsyncValue<AuthState> auth = ref.read(authProvider);

      // Still restoring the session: hold on the splash screen rather than
      // flashing login and then bouncing to the dashboard.
      if (auth.isLoading || auth.value is AuthUnknown) return null;

      final bool isAuthenticated = auth.value?.isAuthenticated ?? false;
      final bool onboardingSeen = ref.read(preferencesServiceProvider).onboardingSeen;
      final String location = state.matchedLocation;
      final bool isPublic = AppRoutes.publicRoutes.contains(location);

      if (!isAuthenticated) {
        if (location == AppRoutes.splash) {
          return onboardingSeen ? AppRoutes.login : AppRoutes.onboarding;
        }
        return isPublic ? null : AppRoutes.login;
      }

      // Signed in: never leave the user sitting on an auth screen.
      if (isPublic) return AppRoutes.dashboard;
      return null;
    },
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.onboarding, builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: AppRoutes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: AppRoutes.otp,
        builder: (_, GoRouterState state) => OtpScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, GoRouterState state) =>
            ResetPasswordScreen(email: state.uri.queryParameters['email'] ?? '', code: state.uri.queryParameters['code'] ?? ''),
      ),

      // ── Tabbed shell ────────────────────────────────────────────────────────
      // StatefulShellRoute keeps a separate Navigator per tab, so each tab
      // remembers its own scroll position and push stack — the behaviour users
      // expect from a bottom nav bar.
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell shell) => AppShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (_, _) => const DashboardScreen(),
                routes: <RouteBase>[_transactionFormRoute('tx-form-dashboard')],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.transactions,
                builder: (_, _) => const TransactionsScreen(),
                routes: <RouteBase>[
                  _transactionFormRoute('tx-form-list'),
                  GoRoute(path: AppRoutes.search, name: AppRoutes.search, builder: (_, _) => const TransactionSearchScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: AppRoutes.reports, builder: (_, _) => const ReportsScreen())],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.profile,
                builder: (_, _) => const ProfileScreen(),
                routes: <RouteBase>[
                  GoRoute(path: AppRoutes.editProfile, name: AppRoutes.editProfile, builder: (_, _) => const EditProfileScreen()),
                  GoRoute(path: AppRoutes.changePassword, name: AppRoutes.changePassword, builder: (_, _) => const ChangePasswordScreen()),
                  GoRoute(
                    path: AppRoutes.settings,
                    name: AppRoutes.settings,
                    builder: (_, _) => const SettingsScreen(),
                    routes: <RouteBase>[GoRoute(path: AppRoutes.about, name: AppRoutes.about, builder: (_, _) => const AboutScreen())],
                  ),
                  GoRoute(
                    path: AppRoutes.categories,
                    name: AppRoutes.categories,
                    builder: (_, _) => const CategoriesScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: AppRoutes.categoryForm,
                        name: AppRoutes.categoryForm,
                        builder: (_, GoRouterState state) => CategoryFormScreen(categoryId: state.extra as String?),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
}, name: 'router');

/// The add/edit transaction form, registered under both tabs that can open it.
///
/// A shared factory rather than a duplicated literal: the form must live
/// *inside* a branch so it pushes onto that tab's navigator and keeps the nav
/// bar visible.
/// [name] must be unique per registration — go_router rejects duplicates.
GoRoute _transactionFormRoute(String name) => GoRoute(
  path: AppRoutes.transactionForm,
  name: name,
  builder: (_, GoRouterState state) {
    Transaction? existing;
    TransactionType? initialType;

    if (state.extra is Transaction) {
      existing = state.extra as Transaction;
    } else if (state.extra is TransactionType) {
      initialType = state.extra as TransactionType;
    } else if (state.uri.queryParameters.containsKey('type')) {
      final String? typeName = state.uri.queryParameters['type'];
      for (final TransactionType t in TransactionType.values) {
        if (t.name == typeName) {
          initialType = t;
          break;
        }
      }
    }

    return TransactionFormScreen(existing: existing, initialType: initialType);
  },
);

/// Adapts Riverpod's auth state to the `Listenable` go_router expects.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _subscription = _ref.listen<AsyncValue<AuthState>>(authProvider, (_, _) => notifyListeners(), fireImmediately: false);
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<AuthState>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
