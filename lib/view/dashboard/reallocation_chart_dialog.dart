import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/dashboard_repository.dart';

/// Show reallocation performance chart dialog
Future<void> showReallocationChart(BuildContext context) async {
  final repository = context.read<DashboardRepository>();

  // Show loading dialog first
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(),
    ),
  );

  try {
    // Fetch reallocation data for last 7 days
    final chartData = await repository.fetchWeeklyReallocationCounts();

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    // Show chart dialog
    await showDialog(
      context: context,
      builder: (ctx) => ReallocationChartDialog(chartData: chartData),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // Close loading dialog
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error loading chart data: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

/// Reallocation Performance Chart Dialog
class ReallocationChartDialog extends StatelessWidget {
  final Map<String, int> chartData;

  const ReallocationChartDialog({super.key, required this.chartData});

  @override
  Widget build(BuildContext context) {
    // Calculate total reallocations
    final totalReallocations = chartData.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );

    // Prepare bar chart data: one bar per calendar day, in the map's order
    // (oldest -> today). Keys look like 'Sat 17/10'.
    final dayKeys = chartData.keys.toList();
    final dayLabels =
        dayKeys.map((key) => key.replaceFirst(' ', '\n')).toList();
    final maxCount = chartData.values.isEmpty
        ? 0
        : chartData.values.reduce((a, b) => a > b ? a : b);
    final yInterval = reallocationChartInterval(maxCount);
    final barGroups = List.generate(dayKeys.length, (index) {
      final value = chartData[dayKeys[index]] ?? 0;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value.toDouble(),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1976D2), // Blue
                Color(0xFF42A5F5), // Light blue
              ],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 20,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(4),
            ),
          ),
        ],
      );
    });

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Reallocation Performance (Last 7 Days)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Chart
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  // Two intervals of padding at the top (was max + 2)
                  maxY: (((maxCount / yInterval).ceil() + 2) * yInterval)
                      .toDouble(),
                  minY: 0,
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < dayLabels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                dayLabels[value.toInt()],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 42,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: yInterval.toDouble(),
                        getTitlesWidget: (value, meta) {
                          if (value == meta.min || value == meta.max) {
                            return const Text('');
                          }
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval.toDouble(),
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color(0xFFE0E0E0),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Summary footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF1976D2).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF1976D2),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The system has successfully saved $totalReallocations appointment${totalReallocations != 1 ? 's' : ''} this week.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Integer y-axis step for the reallocation chart so labels aren't
/// duplicated (e.g. "1, 1, 0"): 1 up to 10, otherwise about 10 steps.
int reallocationChartInterval(int maxCount) {
  if (maxCount <= 10) return 1;
  return (maxCount / 10).ceil();
}
