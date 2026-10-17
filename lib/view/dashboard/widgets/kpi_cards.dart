import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../utils/appointment_status.dart';

/// KPI Cards Section with real-time metrics
class KpiCardsSection extends StatelessWidget {
  final BoxConstraints constraints;

  /// All appointments stream (DashboardRepository.watchAllAppointments).
  final Stream<QuerySnapshot> stream;

  /// Tap on the "reallocated" card; receives the StreamBuilder's context.
  final void Function(BuildContext context) onReallocationsTap;

  const KpiCardsSection({
    super.key,
    required this.constraints,
    required this.stream,
    required this.onReallocationsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = constraints.maxWidth < 600;

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, appointmentsSnapshot) {
        if (appointmentsSnapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Could not load metrics: ${appointmentsSnapshot.error}',
              style: TextStyle(
                  color: Colors.red, fontSize: isSmallScreen ? 11 : 12),
            ),
          );
        }
        if (!appointmentsSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Calculate total cancellations dynamically from appointments
        int totalCancellations = 0;
        int totalReallocations = 0;
        int totalDaysMoved = 0;

        if (appointmentsSnapshot.hasData) {
          final appointments = appointmentsSnapshot.data!.docs;

          for (var doc in appointments) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? '';
            final statusLower = status.toLowerCase();
            final userResponse = data['userResponse'] as String?;

            // Count cancellations:
            // 1. any cancelled spelling ('cancelled', 'CANCELLED', 'canceled', ...)
            // 2. status is 'AVAILABLE'/'available' with userResponse 'Cancelled'
            if (AppointmentStatus.isCancelled(status) ||
                (statusLower == 'available' && userResponse == 'Cancelled')) {
              totalCancellations++;
            }

            // Count reallocations: reallocationStatus is 'Reallocated' (case-insensitive)
            final reallocationStatus = data['reallocationStatus'] as String?;
            if (reallocationStatus != null) {
              final reallocationStatusLower =
                  reallocationStatus.toLowerCase().trim();
              if (reallocationStatusLower == 'reallocated') {
                totalReallocations++;
              }
            }

            // Sum days moved (handle both int and string types)
            final daysMovedValue = data['daysMoved'];
            if (daysMovedValue != null) {
              int days = 0;
              // Handle different types: int, string, or double
              if (daysMovedValue is int) {
                days = daysMovedValue;
              } else if (daysMovedValue is double) {
                days = daysMovedValue.toInt();
              } else if (daysMovedValue is String) {
                days = int.tryParse(daysMovedValue) ?? 0;
              }

              // Only add positive days (negative or zero means no movement or moved later)
              if (days > 0) {
                totalDaysMoved += days;
              }
            }
          }
        }

        // Always use calculated values from appointments (real-time, most accurate)
        // The metrics document may not be updated, so we calculate directly from appointments
        // This ensures we always show the correct count

        // Stack cards vertically on small screens
        if (isSmallScreen) {
          return Column(
            children: [
              KpiCard(
                title: 'TOTAL APPOINTMENTS CANCELED',
                value: totalCancellations.toString(),
                color: Colors.orangeAccent,
                backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                constraints: constraints,
                animateCountUp: true,
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              KpiCard(
                title: 'TOTAL APPOINTMENTS REALLOCATED',
                value: totalReallocations.toString(),
                color: Colors.blueAccent,
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                constraints: constraints,
                onTap: () => onReallocationsTap(context),
                animateCountUp: true,
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              KpiCard(
                title: 'TOTAL DAYS MOVED (NET)',
                value: '$totalDaysMoved Days',
                color: Colors.greenAccent[700] ?? Colors.green,
                backgroundColor: Colors.greenAccent.withOpacity(0.1),
                constraints: constraints,
              ),
            ],
          );
        }

        return Wrap(
          spacing: isSmallScreen ? 8 : 12,
          runSpacing: isSmallScreen ? 10 : 12,
          children: [
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - (isSmallScreen ? 8 : 12)) / 2
                  : constraints.maxWidth,
              child: KpiCard(
                title: 'TOTAL APPOINTMENTS CANCELED',
                value: totalCancellations.toString(),
                color: Colors.orangeAccent,
                backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                constraints: constraints,
                animateCountUp: true,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - (isSmallScreen ? 8 : 12)) / 2
                  : constraints.maxWidth,
              child: KpiCard(
                title: 'TOTAL APPOINTMENTS REALLOCATED',
                value: totalReallocations.toString(),
                color: Colors.blueAccent,
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                constraints: constraints,
                onTap: () => onReallocationsTap(context),
                animateCountUp: true,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - (isSmallScreen ? 8 : 12)) / 2
                  : constraints.maxWidth,
              child: KpiCard(
                title: 'TOTAL DAYS MOVED (NET)',
                value: '$totalDaysMoved Days',
                color: Colors.greenAccent[700] ?? Colors.green,
                backgroundColor: Colors.greenAccent.withOpacity(0.1),
                constraints: constraints,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Individual KPI Card
class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final Color? backgroundColor;
  final BoxConstraints constraints;
  final VoidCallback? onTap;
  final bool animateCountUp;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    this.backgroundColor,
    required this.constraints,
    this.onTap,
    this.animateCountUp = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isMediumScreen = constraints.maxWidth < 900;
    final valueStyle = TextStyle(
      fontSize: isSmallScreen ? 18 : isMediumScreen ? 20 : 24,
      fontWeight: FontWeight.bold,
      color: color,
    );

    final endVal = double.tryParse(value);
    final valueWidget = endVal != null
        ? TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: endVal),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutExpo,
            builder: (context, animValue, child) => Text(
              animValue.toInt().toString(),
              style: valueStyle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : Text(
            value,
            style: valueStyle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

    final cardContent = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen
            ? 12.0
            : isMediumScreen
                ? 14.0
                : 18.0),
        decoration: BoxDecoration(
          color: backgroundColor ?? color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen
                    ? 11
                    : isMediumScreen
                        ? 12
                        : 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isSmallScreen ? 8 : 10),
            valueWidget,
          ],
        ),
      ),
    );

    // Wrap in InkWell if onTap is provided
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: cardContent,
      );
    }

    return cardContent;
  }
}
