import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../res/color.dart';
import '../../../utils/date_utils.dart';
import '../appointment_graph_screen.dart';
import 'appointment_card.dart';

/// The patient's upcoming appointments (from [stream]) followed by the
/// persistent bottom sheet for the last one. [onCancelPressed] receives the
/// tapped appointment's document id.
class PatientAppointmentList extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final void Function(String documentId) onCancelPressed;

  const PatientAppointmentList({
    super.key,
    required this.stream,
    required this.onCancelPressed,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Something went wrong',
              style: TextStyle(color: AppColors.redColor),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.blackColor),
          );
        }

        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No active appointments found',
              style: TextStyle(color: AppColors.blackColor),
            ),
          );
        }

        // Convert to AppointmentData and filter out past appointments
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        final futureAppointments = snapshot.data!.docs
            .map((doc) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                final dateString = data['date'] as String? ?? '';
                final parsedDate = Date_Utils.parseDate(dateString);
                final appointmentDateOnly = DateTime(
                  parsedDate.year,
                  parsedDate.month,
                  parsedDate.day,
                );
                // Only include appointments from today onwards
                if (!appointmentDateOnly.isBefore(today)) {
                  return doc;
                }
                return null;
              } catch (e) {
                return null;
              }
            })
            .where((doc) => doc != null)
            .cast<DocumentSnapshot>()
            .toList();

        if (futureAppointments.isEmpty) {
          return const Center(
            child: Text(
              'No upcoming appointments found',
              style: TextStyle(color: AppColors.blackColor),
            ),
          );
        }

        // Extract the last appointment's data for the bottom sheet
        DocumentSnapshot lastDocument = futureAppointments.last;
        Map<String, dynamic> lastAppointmentData =
            lastDocument.data()! as Map<String, dynamic>;
        String lastAppointmentDate = lastAppointmentData['date'];
        String lastAppointmentTime = lastAppointmentData['time'];
        String lastStatus = lastAppointmentData['status'];

        return Column(
          children: [
            ListView(
              shrinkWrap: true,
              children: futureAppointments.map((DocumentSnapshot document) {
                Map<String, dynamic> data =
                    document.data()! as Map<String, dynamic>;
                String appointmentDate = data['date']; // Get appointment date
                String appointmentTime = data['time']; // Get appointment time

                // Parse the appointment date using DateUtils
                DateTime parsedDate = Date_Utils.parseDate(appointmentDate);

                String appointmentStatus = data['status'] ?? 'active';

                return PatientAppointmentCard(
                  parsedDate: parsedDate,
                  appointmentTime: appointmentTime,
                  appointmentStatus: appointmentStatus,
                  onCancelPressed: () {
                    onCancelPressed(document.id);
                  },
                );
              }).toList(),
            ),
            // Add bottom sheet at the end with the latest appointment details
            buildPersistentBottomSheet(
              context,
              lastAppointmentDate, // Pass the appointment date
              lastAppointmentTime, // Pass the appointment time
              lastStatus, // Pass the appointment status
            ),
          ],
        );
      },
    );
  }
}
