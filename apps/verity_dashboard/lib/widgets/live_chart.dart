import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../charts/chart_math.dart';
import '../models/time_series_buffer.dart';

/// A time-anchored line chart. Unlike a naive "append and trim" chart, the
/// x-axis here is always real elapsed seconds (negative = seconds ago, 0 =
/// now), so it never collapses or collides as old points are dropped, and
/// it stays meaningful across different [ChartTimeframe] selections.
class LiveChart extends StatelessWidget {
  final List<FlSpot> spots;
  final String title;
  final Color color;
  final ChartTimeframe timeframe;
  final ChartAxisRange? yRange;
  final String? unit;
  final double? height;

  const LiveChart({
    super.key,
    required this.spots,
    required this.title,
    required this.timeframe,
    this.color = Colors.redAccent,
    this.yRange,
    this.unit,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final chartHeight = height ??
            (constraints.maxWidth * (isWide ? 0.28 : 0.45)).clamp(140.0, 260.0);
        final windowSeconds = timeframe.window.inSeconds.toDouble();
        final xInterval = liveXInterval(windowSeconds);
        final last = spots.isEmpty ? null : spots.last.y;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (last != null) ...[
                      _LeanValueChip(value: last, unit: unit, color: color),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'last ${formatWindowLabel(timeframe.window)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: chartHeight,
                  child: spots.isEmpty
                      ? const Center(child: Text('Waiting for data...'))
                      : LineChart(
                          duration: Duration.zero,
                          LineChartData(
                            minX: -windowSeconds,
                            maxX: 0,
                            minY: yRange?.min,
                            maxY: yRange?.max,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: yRange?.interval,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: Colors.white.withValues(alpha: 0.06),
                                strokeWidth: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 44,
                                  interval: yRange?.interval,
                                  getTitlesWidget: (value, meta) {
                                    if (yRange != null &&
                                        !_onTick(value, yRange!.interval)) {
                                      return const SizedBox.shrink();
                                    }
                                    return SideTitleWidget(
                                      axisSide: meta.axisSide,
                                      space: 6,
                                      child: Text(
                                        formatAxisTick(value),
                                        maxLines: 1,
                                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 22,
                                  interval: xInterval,
                                  getTitlesWidget: (value, meta) {
                                    if (!_onTick(value, xInterval) &&
                                        value > meta.min + 0.01 &&
                                        value < meta.max - 0.01) {
                                      return const SizedBox.shrink();
                                    }
                                    return SideTitleWidget(
                                      axisSide: meta.axisSide,
                                      space: 4,
                                      child: Text(
                                        formatLiveAgo(value),
                                        maxLines: 1,
                                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineTouchData: LineTouchData(
                              enabled: true,
                              handleBuiltInTouches: true,
                              touchTooltipData: LineTouchTooltipData(
                                maxContentWidth: 220,
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                tooltipRoundedRadius: 8,
                                getTooltipColor: (_) =>
                                    color.withValues(alpha: 0.92),
                                getTooltipItems: (touched) => [
                                  for (final t in touched)
                                    LineTooltipItem(
                                      formatTouchTooltip(
                                        y: t.y,
                                        unit: unit,
                                        when: formatLiveAgo(t.x),
                                      ),
                                      const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: spots,
                                isCurved: true,
                                color: color,
                                barWidth: 2.5,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: color.withValues(alpha: 0.15),
                                ),
                              ),
                            ],
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

bool _onTick(double value, double interval) {
  if (interval <= 0 || !value.isFinite) return true;
  final n = (value / interval).roundToDouble();
  return (value - n * interval).abs() < interval * 0.02 + 1e-6;
}

class _LeanValueChip extends StatelessWidget {
  final double value;
  final String? unit;
  final Color color;

  const _LeanValueChip({
    required this.value,
    required this.color,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final label = unit == null || unit!.isEmpty
        ? formatLeanValue(value)
        : '${formatLeanValue(value)} $unit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
