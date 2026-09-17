import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/features/reports/presentation/widgets/charts.dart';

void main() {
  group('ChartAxisHelper', () {
    test('returns empty set for 0 points', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 0,
        availableWidth: 320,
      );
      expect(indices, isEmpty);
    });

    test('returns single index 0 for 1 point', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 1,
        availableWidth: 320,
      );
      expect(indices, equals(<int>{0}));
    });

    test('weekly: displays all 7 days on standard phone screen', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 7,
        availableWidth: 300,
      );
      expect(indices, equals(<int>{0, 1, 2, 3, 4, 5, 6}));
    });

    test('monthly (30 days): produces milestone days 1, 5, 10, 15, 20, 25, 30', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 30,
        availableWidth: 300, // standard phone plot width
      );

      // In 0-based indices: 0 (day 1), 4 (day 5), 9 (day 10), 14 (day 15), 19 (day 20), 24 (day 25), 29 (day 30)
      expect(indices, equals(<int>{0, 4, 9, 14, 19, 24, 29}));
    });

    test('monthly (31 days): produces milestone days 1, 5, 10, 15, 20, 25, 31', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 31,
        availableWidth: 300,
      );

      expect(indices, equals(<int>{0, 4, 9, 14, 19, 24, 30}));
    });

    test('monthly (28 days): produces milestone days 1, 5, 10, 15, 20, 25, 28', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 28,
        availableWidth: 300,
      );

      expect(indices, equals(<int>{0, 4, 9, 14, 19, 24, 27}));
    });

    test('tablet width: scales gracefully to display more milestone points', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 30,
        availableWidth: 700, // tablet plot width
      );

      // On tablet width, maxLabels >= 12, so step = 3
      expect(indices.contains(0), isTrue); // First
      expect(indices.contains(29), isTrue); // Last
      expect(indices.length, greaterThanOrEqualTo(9));
    });

    test('yearly (12 months): spaces labels evenly without overlapping', () {
      final Set<int> indices = ChartAxisHelper.getVisibleIndices(
        totalPoints: 12,
        availableWidth: 280, // tight phone viewport
      );

      expect(indices.contains(0), isTrue); // First month (Jan)
      expect(indices.contains(11), isTrue); // Last month (Dec)
      expect(indices.length, lessThanOrEqualTo(8));
    });
  });

  group('Chart Widgets Rendering', () {
    testWidgets('IncomeExpenseBarChart renders milestones and suppresses overlapping intermediate days', (
      WidgetTester tester,
    ) async {
      final List<SeriesPoint> monthlyPoints = <SeriesPoint>[
        for (int i = 1; i <= 30; i++)
          (label: '$i', income: i * 10.0, expense: i * 5.0),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 250,
              child: IncomeExpenseBarChart(
                points: monthlyPoints,
                currencyCode: 'USD',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Milestones 1, 5, 10, 15, 20, 25, 30 must be found
      expect(find.text('1'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);

      // Intermediate numbers that previously stacked must NOT be rendered on the axis
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
      expect(find.text('4'), findsNothing);
      expect(find.text('6'), findsNothing);
      expect(find.text('7'), findsNothing);
      expect(find.text('8'), findsNothing);
      expect(find.text('9'), findsNothing);
      expect(find.text('11'), findsNothing);
      expect(find.text('12'), findsNothing);
      expect(find.text('29'), findsNothing);
    });

    testWidgets('BalanceLineChart renders cleanly with milestone labels', (
      WidgetTester tester,
    ) async {
      final List<SeriesPoint> monthlyPoints = <SeriesPoint>[
        for (int i = 1; i <= 30; i++)
          (label: '$i', income: 100.0, expense: 50.0),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 250,
              child: BalanceLineChart(
                points: monthlyPoints,
                currencyCode: 'USD',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Milestones must be present
      expect(find.text('1'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);

      // Intermediate colliding numbers are absent
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
    });
  });
}
