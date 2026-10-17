import 'package:flutter/material.dart';

import '../../../res/color.dart';
import '../../../res/components/status_badge.dart';
import '../../../utils/date_utils.dart';

/// One appointment row in the patient home list (date, time, status badge
/// and a cancel icon that calls [onCancelPressed]).
///
/// The document fields are read by the list (see appointment_list.dart) so
/// a malformed document fails in the same place it did before the split.
class PatientAppointmentCard extends StatelessWidget {
  final DateTime parsedDate;
  final String appointmentTime;
  final String appointmentStatus;
  final VoidCallback onCancelPressed;

  const PatientAppointmentCard({
    super.key,
    required this.parsedDate,
    required this.appointmentTime,
    required this.appointmentStatus,
    required this.onCancelPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        color: Colors.grey.withOpacity(0.2),
        child: ListTile(
          title: Text(
            'Appointment Date: ${Date_Utils.formatDate(parsedDate)}',
            style: const TextStyle(
                color: AppColors.blueAccent, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Time: $appointmentTime',
                  style: const TextStyle(
                      color: AppColors.blueAccent,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              StatusBadge(status: appointmentStatus),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.cancel, color: AppColors.redColor),
            onPressed: onCancelPressed,
          ),
        ),
      ),
    );
  }
}
