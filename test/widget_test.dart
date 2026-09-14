import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/app.dart';
import 'package:pocket_pilot/core/errors/failure.dart';
import 'package:pocket_pilot/core/theme/app_theme.dart';
import 'package:pocket_pilot/core/widgets/app_button.dart';
import 'package:pocket_pilot/core/widgets/app_state_views.dart';
import 'package:pocket_pilot/core/widgets/app_text_field.dart';

/// Widget tests for the shared component library.
///
/// These target the reusable widgets rather than whole screens: they are the
/// pieces every feature depends on, so a regression here breaks the app
/// everywhere at once. Screens are covered by the provider-level tests, which
/// run far faster than pumping a full navigator.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  group('PocketPilotApp', () {
    test('falls back to English for unsupported locale codes', () {
      expect(PocketPilotApp.resolveLocaleCode('en'), 'en');
      expect(PocketPilotApp.resolveLocaleCode('my'), 'my');
      expect(PocketPilotApp.resolveLocaleCode('pt'), 'en');
      expect(PocketPilotApp.resolveLocaleCode(null), 'en');
    });
  });

  group('AppButton', () {
    testWidgets('invokes onPressed when enabled', (WidgetTester tester) async {
      var taps = 0;
      await pump(tester, AppButton(label: 'Save', onPressed: () => taps++));

      await tester.tap(find.text('Save'));
      expect(taps, 1);
    });

    testWidgets('swaps the label for a spinner while loading', (WidgetTester tester) async {
      var taps = 0;
      await pump(tester, AppButton(label: 'Save', isLoading: true, onPressed: () => taps++));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('blocks taps while loading so a submit cannot double-fire', (WidgetTester tester) async {
      var taps = 0;
      await pump(tester, AppButton(label: 'Save', isLoading: true, onPressed: () => taps++));

      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
    });

    testWidgets('is disabled when onPressed is null', (WidgetTester tester) async {
      await pump(tester, const AppButton(label: 'Save', onPressed: null));

      final FilledButton button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('AppTextField', () {
    testWidgets('obscures a password and toggles visibility', (WidgetTester tester) async {
      await pump(tester, AppTextField(controller: TextEditingController(), label: 'Password', obscureText: true));

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
    });

    testWidgets('amount field rejects letters and extra decimals', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      await pump(tester, AppTextField.amount(controller: controller));

      await tester.enterText(find.byType(TextField), '12ab.999');
      expect(controller.text, '12.99');
    });

    testWidgets('renders a server-side error', (WidgetTester tester) async {
      await pump(tester, AppTextField(controller: TextEditingController(), errorText: 'That email is already registered'));

      expect(find.text('That email is already registered'), findsOneWidget);
    });
  });

  group('AppErrorState', () {
    testWidgets('offers retry for a retryable failure', (WidgetTester tester) async {
      await pump(tester, AppErrorState(failure: const NetworkFailure(), onRetry: () {}));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Try again'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('hides retry for a failure that cannot be retried', (WidgetTester tester) async {
      await pump(tester, AppErrorState(failure: const ValidationFailure('Enter an amount'), onRetry: () {}));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Try again'), findsNothing);
      expect(find.text('Enter an amount'), findsOneWidget);
    });
  });

  group('AppEmptyState', () {
    testWidgets('renders its call to action', (WidgetTester tester) async {
      var tapped = false;
      await pump(
        tester,
        AppEmptyState(
          title: 'Nothing here yet',
          message: 'Add your first transaction.',
          actionLabel: 'Add transaction',
          onAction: () => tapped = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Add transaction'));
      expect(tapped, isTrue);
    });
  });
}
