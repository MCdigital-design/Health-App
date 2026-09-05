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
  final (double, double)? yRange;
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
                    const SizedBox(width: 8),
                    Text(
                      'last ${timeframe.window.inSeconds < 60 ? '${timeframe.window.inSeconds}s' : '${timeframe.window.inMinutes}m'}',
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
                            minY: yRange?.$1,
                            maxY: yRange?.$2,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: yRange != null
                                  ? ((yRange!.$2 - yRange!.$1) / 3).clamp(0.5, double.infinity)
                                  : null,
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
                                  reservedSize: 48,
                                  interval: yRange != null
                                      ? niceStep(yRange!.$2 - yRange!.$1, tickCount: 4)
                                      : null,
                                  getTitlesWidget: (value, meta) => SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    space: 6,
                                    child: Text(
                                      formatAxisNumber(value),
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 22,
                                  interval: windowSeconds / 3,
                                  getTitlesWidget: (value, meta) => SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    space: 4,
                                    child: Text(
                                      formatElapsed(value),
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
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
