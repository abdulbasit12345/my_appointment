import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/appointment_data.dart';

/// Priority Queue Card Section
class PriorityQueueCard extends StatelessWidget {
  final BoxConstraints constraints;

  /// Priority-queue appointments stream (DashboardRepository.watchPriorityQueue).
  final Stream<QuerySnapshot> stream;

  const PriorityQueueCard({
    super.key,
    required this.constraints,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = constraints.maxWidth < 600;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.trending_up, color: Color(0xFF1976D2), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Priority Queue',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A1A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.red, fontSize: isSmallScreen ? 11 : 12)),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator()));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No patients on priority list',
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                // Skip documents that fail to parse so one bad document
                // doesn't break the whole card.
                final priorityAppointments = <AppointmentData>[];
                for (final doc in snapshot.data!.docs) {
                  try {
                    priorityAppointments.add(AppointmentData.fromFirestore(doc));
                  } catch (e) {
                    debugPrint('Priority queue: skipping appointment ${doc.id}: $e');
                  }
                }
                // The query orders by the 'dd-MM-yyyy' string (day-of-month
                // order), so sort chronologically here.
                priorityAppointments.sort((a, b) =>
                    a.appointmentDateTime.compareTo(b.appointmentDateTime));
                if (priorityAppointments.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No patients on priority list',
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: priorityAppointments.map((appointment) {
                    String waitingInfo = 'Not available';
                    if (appointment.priorityJoinedAt != null) {
                      final d = DateTime.now().difference(appointment.priorityJoinedAt!);
                      if (d.inDays > 0) waitingInfo = '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} waiting';
                      else if (d.inHours > 0) waitingInfo = '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} waiting';
                      else waitingInfo = 'Joined just now';
                    }
                    return Padding(
                      padding: EdgeInsets.only(bottom: isSmallScreen ? 8 : 10),
                      child: Container(
                        padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.2), width: 1),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(appointment.name, style: TextStyle(fontSize: isSmallScreen ? 13 : 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                                  SizedBox(height: isSmallScreen ? 4 : 6),
                                  Text('Current: ${appointment.ukFormattedDate} @ ${appointment.formattedTime}', style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: Colors.grey[700])),
                                ],
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 10, vertical: isSmallScreen ? 4 : 6),
                              decoration: BoxDecoration(color: const Color(0xFF1976D2).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                              child: Text(waitingInfo, style: TextStyle(fontSize: isSmallScreen ? 11 : 12, fontWeight: FontWeight.w600, color: Color(0xFF1976D2)), textAlign: TextAlign.center),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
