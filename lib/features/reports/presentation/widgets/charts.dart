import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';

/// Chart building blocks shared by the dashboard and the reports screen.
///
/// They take plain data and no providers, which keeps them trivially
/// previewable and testable, and lets both screens style them identically.

/// One slice of the category breakdown.
typedef CategorySlice = ({String label, double value, Color color});

/// One day/period in a time series.
typedef SeriesPoint = ({String label, double income, double expense});

/// Income vs expense over time, as grouped bars.
///
/// Bars beat a line for discrete periods: they say "this week" rather than
/// implying a continuous quantity between the points.
/// Chart axis and milestone badge helper for responsive date/time-series.
class ChartAxisHelper {
  const ChartAxisHelper._();

  /// Computes which indices in [0, totalPoints - 1] should display an X-axis badge
  /// given the available chart width [availableWidth].
  static Set<int> getVisibleIndices({required int totalPoints, required double availableWidth}) {
    if (totalPoints <= 0) return const <int>{};
    if (totalPoints == 1) return const <int>{0};

    // Each badge needs roughly 38-42px minimum horizontal clearance.
    final int maxLabels = (availableWidth / 40).floor().clamp(3, 14);

    if (totalPoints <= maxLabels) {
      return Set<int>.from(List<int>.generate(totalPoints, (int i) => i));
    }

    // For a standard month range (28 to 31 days)
    if (totalPoints >= 28 && totalPoints <= 31) {
      final Set<int> indices = <int>{};
      indices.add(0); // Day 1
      final int step = maxLabels >= 12 ? 3 : (maxLabels >= 6 ? 5 : 10);
      for (int day = step; day < totalPoints; day += step) {
        if (totalPoints - day >= 2) {
          indices.add(day - 1);
        }
      }
      indices.add(totalPoints - 1); // Last day (Day 28, 30, or 31)
      return indices;
    }

    // Generic adaptive step for arbitrary number of points
    final Set<int> indices = <int>{};
    indices.add(0);
    final int step = ((totalPoints - 1) / (maxLabels - 1)).ceil().clamp(1, totalPoints);
    for (int i = step; i < totalPoints - 1; i += step) {
      if ((totalPoints - 1) - i >= (step * 0.6).round()) {
        indices.add(i);
      }
    }
    indices.add(totalPoints - 1);
    return indices;
  }

  /// Builds a modern, stylized milestone date badge.
  static Widget buildMilestoneBadge({
    required BuildContext context,
    required String label,
    required bool isMilestone,
    required bool isBoundary,
    required bool isDateNumber,
  }) {
    if (!isDateNumber) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Center(
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 11),
          ),
        ),
      );
    }

    final ColorScheme colors = context.colors;
    final Color badgeBg = isBoundary
        ? colors.primary.withValues(alpha: 0.12)
        : (isMilestone ? colors.surfaceContainerHighest.withValues(alpha: 0.55) : Colors.transparent);

    final Color textColor = isBoundary ? colors.primary : (isMilestone ? colors.onSurface : colors.onSurfaceVariant);

    final Border? border = isBoundary
        ? Border.all(color: colors.primary.withValues(alpha: 0.35), width: 1)
        : (isMilestone ? Border.all(color: colors.outlineVariant.withValues(alpha: 0.45), width: 1) : null);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(6), border: border),
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: isBoundary || isMilestone ? FontWeight.w700 : FontWeight.w500,
              color: textColor,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Income vs expense over time, as grouped bars.
///
/// Bars beat a line for discrete periods: they say "this week" rather than
/// implying a continuous quantity between the points.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({required this.points, required this.currencyCode, super.key, this.height = 220});

  final List<SeriesPoint> points;
  final String currencyCode;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return SizedBox(height: height);

    final double maxValue = points
        .map((SeriesPoint p) => p.income > p.expense ? p.income : p.expense)
        .fold<double>(0, (double a, double b) => a > b ? a : b);
    // A flat-zero chart would divide by zero on the axis interval.
    final double top = maxValue <= 0 ? 100 : maxValue * 1.25;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availablePlotWidth = (constraints.maxWidth - 56).clamp(100.0, 2000.0);
        final double groupSlot = availablePlotWidth / points.length;

        // Dynamic bar width and space based on slot width
        final double barWidth = (groupSlot * 0.32).clamp(2.5, 10.0);
        final double barsSpace = (groupSlot * 0.12).clamp(1.0, 4.0);

        final Set<int> visibleIndices = ChartAxisHelper.getVisibleIndices(totalPoints: points.length, availableWidth: availablePlotWidth);

        return SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: top,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: top / 4,
                getDrawingHorizontalLine: (double value) => FlLine(color: context.colors.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: top / 4,
                    getTitlesWidget: (double value, TitleMeta meta) => Text(
                      value.toCompactCurrency(currencyCode: currencyCode),
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant, fontSize: 9),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      if ((value - index).abs() > 0.1) {
                        return const SizedBox.shrink();
                      }
                      if (!visibleIndices.contains(index)) {
                        return const SizedBox.shrink();
                      }

                      final bool isDateNumber = int.tryParse(points[index].label) != null;
                      final bool isBoundary = index == 0 || index == points.length - 1;
                      final bool isMilestone = isBoundary || (index + 1) % 5 == 0;

                      return ChartAxisHelper.buildMilestoneBadge(
                        context: context,
                        label: points[index].label,
                        isMilestone: isMilestone,
                        isBoundary: isBoundary,
                        isDateNumber: isDateNumber,
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => context.colors.inverseSurface,
                  getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
                    final int idx = group.x.toInt();
                    final String dayLabel = (idx >= 0 && idx < points.length) ? points[idx].label : '';
                    final bool isIncome = rodIndex == 0;
                    final String type = isIncome ? 'Income' : 'Expense';
                    final String formattedVal = rod.toY.toCurrency(currencyCode: currencyCode);

                    return BarTooltipItem(
                      dayLabel.isNotEmpty ? '$dayLabel\n' : '',
                      context.text.labelSmall!.copyWith(color: context.colors.onInverseSurface.withValues(alpha: 0.7), fontWeight: FontWeight.normal),
                      children: <TextSpan>[
                        TextSpan(
                          text: '$type: $formattedVal',
                          style: context.text.labelMedium!.copyWith(
                            color: isIncome ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              barGroups: <BarChartGroupData>[
                for (int i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: barsSpace,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: points[i].income,
                        width: barWidth,
                        color: context.finance.income,
                        borderRadius: BorderRadius.circular(barWidth / 2),
                      ),
                      BarChartRodData(
                        toY: points[i].expense,
                        width: barWidth,
                        color: context.finance.expense,
                        borderRadius: BorderRadius.circular(barWidth / 2),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Cumulative balance over time.
class BalanceLineChart extends StatelessWidget {
  const BalanceLineChart({required this.points, required this.currencyCode, super.key, this.height = 200});

  final List<SeriesPoint> points;
  final String currencyCode;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return SizedBox(height: height);

    // Running total, so the line shows where the balance actually went rather
    // than a series of disconnected daily deltas.
    double running = 0;
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), running += points[i].income - points[i].expense),
    ];

    final double minBal = spots.map((FlSpot s) => s.y).fold<double>(0, (double a, double b) => a < b ? a : b);
    final double maxBal = spots.map((FlSpot s) => s.y).fold<double>(0, (double a, double b) => a > b ? a : b);
    final double balanceSpread = (maxBal - minBal).abs();
    final double lineTop = balanceSpread == 0 ? 100 : (maxBal > 0 ? maxBal * 1.25 : 10);
    final double lineBottom = balanceSpread == 0 ? 0 : (minBal < 0 ? minBal * 1.25 : 0);
    final double lineInterval = ((lineTop - lineBottom) / 4).clamp(1.0, double.infinity);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availablePlotWidth = (constraints.maxWidth - 56).clamp(100.0, 2000.0);
        final Set<int> visibleIndices = ChartAxisHelper.getVisibleIndices(totalPoints: points.length, availableWidth: availablePlotWidth);

        return SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: lineBottom,
              maxY: lineTop,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: lineInterval,
                getDrawingHorizontalLine: (double value) => FlLine(color: context.colors.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: lineInterval,
                    getTitlesWidget: (double value, TitleMeta meta) => Text(
                      value.toCompactCurrency(currencyCode: currencyCode),
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant, fontSize: 9),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final int index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      if ((value - index).abs() > 0.1) {
                        return const SizedBox.shrink();
                      }
                      if (!visibleIndices.contains(index)) {
                        return const SizedBox.shrink();
                      }

                      final bool isDateNumber = int.tryParse(points[index].label) != null;
                      final bool isBoundary = index == 0 || index == points.length - 1;
                      final bool isMilestone = isBoundary || (index + 1) % 5 == 0;

                      return ChartAxisHelper.buildMilestoneBadge(
                        context: context,
                        label: points[index].label,
                        isMilestone: isMilestone,
                        isBoundary: isBoundary,
                        isDateNumber: isDateNumber,
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => context.colors.inverseSurface,
                  getTooltipItems: (List<LineBarSpot> spots) => spots.map((LineBarSpot spot) {
                    final int index = spot.x.toInt();
                    final String label = (index >= 0 && index < points.length) ? points[index].label : '';
                    return LineTooltipItem(
                      label.isNotEmpty ? '$label\n' : '',
                      context.text.labelSmall!.copyWith(color: context.colors.onInverseSurface.withValues(alpha: 0.7)),
                      children: <TextSpan>[
                        TextSpan(
                          text: spot.y.toSignedCurrency(currencyCode: currencyCode),
                          style: context.text.labelMedium!.copyWith(
                            color: spot.y >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: <LineChartBarData>[
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  barWidth: 3,
                  color: context.colors.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[context.colors.primary.withValues(alpha: 0.28), context.colors.primary.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Category breakdown as a donut with an inline legend.
///
/// A donut rather than a pie: the hole carries the total, which is the number
/// people actually look for first.
class CategoryDonutChart extends StatefulWidget {
  const CategoryDonutChart({required this.slices, required this.currencyCode, super.key});

  final List<CategorySlice> slices;
  final String currencyCode;

  @override
  State<CategoryDonutChart> createState() => _CategoryDonutChartState();
}

class _CategoryDonutChartState extends State<CategoryDonutChart> {
  /// Which slice is under the finger — pure presentation state.
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final double total = widget.slices.fold<double>(0, (double sum, CategorySlice s) => sum + s.value);
    if (total <= 0) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        SizedBox(
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 62,
                  startDegreeOffset: -90,
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                      setState(() {
                        _touched = response?.touchedSection?.touchedSectionIndex ?? -1;
                      });
                    },
                  ),
                  sections: <PieChartSectionData>[
                    for (int i = 0; i < widget.slices.length; i++)
                      PieChartSectionData(
                        value: widget.slices[i].value,
                        color: widget.slices[i].color,
                        radius: _touched == i ? 30 : 24,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              _DonutCentre(slices: widget.slices, touched: _touched, total: total, currencyCode: widget.currencyCode),
            ],
          ),
        ),
        AppSpacing.lg.gapH,
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (int i = 0; i < widget.slices.length; i++)
              _LegendChip(slice: widget.slices[i], share: widget.slices[i].value / total, isActive: _touched == i),
          ],
        ),
      ],
    );
  }
}

class _DonutCentre extends StatelessWidget {
  const _DonutCentre({required this.slices, required this.touched, required this.total, required this.currencyCode});

  final List<CategorySlice> slices;
  final int touched;
  final double total;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final bool hasSelection = touched >= 0 && touched < slices.length;
    final String label = hasSelection ? slices[touched].label : 'Total';
    final double value = hasSelection ? slices[touched].value : total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        AppSpacing.xxs.gapH,
        Text(value.toCompactCurrency(currencyCode: currencyCode), style: context.text.titleLarge),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.slice, required this.share, required this.isActive});

  final CategorySlice slice;
  final double share;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(color: slice.color, borderRadius: BorderRadius.circular(3)),
        ),
        AppSpacing.sm.gapW,
        Text(
          '${slice.label} · ${share.toPercent()}',
          style: context.text.labelSmall?.copyWith(fontWeight: isActive ? FontWeight.w700 : FontWeight.w500),
        ),
      ],
    );
  }
}
