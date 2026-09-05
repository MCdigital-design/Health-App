import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../charts/chart_math.dart';

/// Pinch-to-zoom / drag-to-pan line chart with a real elapsed-time X axis
/// and an adaptive Y axis that follows the visible window.
class InteractiveTimeChart extends StatefulWidget {
  final String title;
  final String? unit;
  final Color color;
  final List<TimeValue> points;
  final String emptyLabel;
  final double height;

  const InteractiveTimeChart({
    super.key,
    required this.title,
    required this.points,
    required this.color,
    this.unit,
    this.emptyLabel = 'No data',
    this.height = 240,
  });

  @override
  State<InteractiveTimeChart> createState() => _InteractiveTimeChartState();
}

class _InteractiveTimeChartState extends State<InteractiveTimeChart> {
  double? _viewMin;
  double? _viewMax;
  double _gestureMin = 0;
  double _gestureMax = 1;

  static const _maxDrawnPoints = 800;
  static const _minWindowSeconds = 2.0;

  double get _dataMin => widget.points.isEmpty ? 0 : widget.points.first.seconds;
  double get _dataMax => widget.points.isEmpty ? 1 : widget.points.last.seconds;
  double get _fullSpan => (_dataMax - _dataMin).clamp(1.0, double.infinity);
  double get _minX => _viewMin ?? _dataMin;
  double get _maxX => _viewMax ?? _dataMax;

  List<TimeValue> get _visible {
    if (widget.points.isEmpty) return const [];
    final lo = _minX;
    final hi = _maxX;
    final inWindow = widget.points.where((p) => p.seconds >= lo && p.seconds <= hi).toList();
    if (inWindow.length >= 2) return downsampleMinMax(inWindow, _maxDrawnPoints);
    // Zoomed into a gap: include nearest neighbours so the line does not vanish.
    final around = widget.points.where((p) {
      return p.seconds >= lo - (hi - lo) && p.seconds <= hi + (hi - lo);
    }).toList();
    return downsampleMinMax(around.isEmpty ? widget.points : around, _maxDrawnPoints);
  }

  void _resetView() {
    setState(() {
      _viewMin = null;
      _viewMax = null;
    });
  }

  void _setView(double min, double max) {
    var lo = min;
    var hi = max;
    if (hi - lo < _minWindowSeconds) {
      final mid = (lo + hi) / 2;
      lo = mid - _minWindowSeconds / 2;
      hi = mid + _minWindowSeconds / 2;
    }
    if (hi - lo > _fullSpan) {
      lo = _dataMin;
      hi = _dataMax;
    } else {
      if (lo < _dataMin) {
        hi += _dataMin - lo;
        lo = _dataMin;
      }
      if (hi > _dataMax) {
        lo -= hi - _dataMax;
        hi = _dataMax;
        if (lo < _dataMin) lo = _dataMin;
      }
    }
    setState(() {
      _viewMin = lo;
      _viewMax = hi;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureMin = _minX;
    _gestureMax = _maxX;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final startSpan = (_gestureMax - _gestureMin).clamp(_minWindowSeconds, _fullSpan);
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width <= 0) return;

    // Left titles consume ~52 px; treat the rest as the plot.
    const leftAxis = 52.0;
    final plotWidth = (box.size.width - leftAxis).clamp(1.0, double.infinity);
    final local = box.globalToLocal(details.focalPoint);
    final focalT = ((local.dx - leftAxis) / plotWidth).clamp(0.0, 1.0);
    final focalX = _gestureMin + startSpan * focalT;

    if (details.pointerCount >= 2) {
      final newSpan = (startSpan / details.scale).clamp(_minWindowSeconds, _fullSpan);
      final newMin = focalX - newSpan * focalT;
      _setView(newMin, newMin + newSpan);
      return;
    }

    final dxSeconds = -details.focalPointDelta.dx / plotWidth * startSpan;
    _gestureMin += dxSeconds;
    _gestureMax += dxSeconds;
    _setView(_gestureMin, _gestureMax);
  }

  void _nudgeZoom(double factor) {
    final span = _maxX - _minX;
    final mid = (_minX + _maxX) / 2;
    final next = (span * factor).clamp(_minWindowSeconds, _fullSpan);
    _setView(mid - next / 2, mid + next / 2);
  }

  @override
  void didUpdateWidget(covariant InteractiveTimeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points) {
      _viewMin = null;
      _viewMax = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final yValues = visible.map((p) => p.value);
    final yRange = paddedRange(yValues);
    final ticks = niceTicks(yRange.$1, yRange.$2);
    final yInterval = ticks.length >= 2 ? (ticks[1] - ticks[0]).abs() : null;
    final xSpan = (_maxX - _minX).clamp(0.001, double.infinity);
    final xInterval = niceStep(xSpan, tickCount: 4);
    final spots = [for (final p in visible) FlSpot(p.seconds, p.value)];
    final zoomed = _viewMin != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (widget.unit != null)
                  Text(widget.unit!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              zoomed
                  ? '${formatElapsed(_minX)} – ${formatElapsed(_maxX)}  ·  pinch or drag  ·  double-tap to reset'
                  : 'Pinch to zoom, drag to pan, or use + / −',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: widget.height,
              child: widget.points.isEmpty
                  ? Center(child: Text(widget.emptyLabel))
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _resetView,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: LineChart(
                        duration: Duration.zero,
                        LineChartData(
                          minX: _minX,
                          maxX: _maxX,
                          minY: yRange.$1,
                          maxY: yRange.$2,
                          clipData: const FlClipData.all(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            horizontalInterval: yInterval,
                            verticalInterval: xInterval,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: Colors.white.withValues(alpha: 0.06),
                              strokeWidth: 1,
                            ),
                            getDrawingVerticalLine: (_) => FlLine(
                              color: Colors.white.withValues(alpha: 0.04),
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
                                interval: yInterval,
                                getTitlesWidget: (value, meta) {
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    space: 6,
                                    child: Text(
                                      formatAxisNumber(value),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
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
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    space: 4,
                                    child: Text(
                                      formatElapsed(value),
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipItems: (touched) => [
                                for (final t in touched)
                                  LineTooltipItem(
                                    '${formatElapsed(t.x)}  ${formatAxisNumber(t.y)}${widget.unit != null ? ' ${widget.unit}' : ''}',
                                    const TextStyle(fontSize: 12, color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: false,
                              color: widget.color,
                              barWidth: 2,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: widget.color.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (widget.points.isNotEmpty)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: () => _nudgeZoom(1.6),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: () => _nudgeZoom(0.6),
                    icon: const Icon(Icons.add),
                  ),
                  TextButton(
                    onPressed: zoomed ? _resetView : null,
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.points.length} samples',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
