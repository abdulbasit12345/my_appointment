import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../res/color.dart';
import '../../../utils/date_utils.dart';
import '../dialog_screen.dart';

/// "More Dates Available Now" dialog. Tapping a date closes it and calls
/// [onDateSelected] with this dialog's context and the tapped date.
void showAvailableDatesListDialog({
  required BuildContext context,
  required List<String> filteredDates,
  required void Function(BuildContext dialogContext, String date)
      onDateSelected,
}) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppColors.whiteColor,
        title: const Text(
          'More Dates Available Now',
          style: TextStyle(color: AppColors.blackColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: filteredDates
              .map((date) => ListTile(
                    title: Text(date),
                    onTap: () {
                      Navigator.of(context).pop();
                      onDateSelected(context, date);
                    },
                  ))
              .toList(),
        ),
        actions: <Widget>[
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
            },
            child: Container(
              height: 40,
              width: 110,
              decoration: BoxDecoration(
                  color: AppColors.appColor,
                  borderRadius: BorderRadius.circular(40)),
              child: const Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.whiteColor),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// "Select Appointment to Reschedule" dialog. Tapping an appointment opens
/// [UpdateAppointmentScreen] for it with [selectedAvailableDate].
void showSelectAppointmentToRescheduleDialog({
  required BuildContext context,
  required List<DocumentSnapshot> userAppointments,
  required String selectedAvailableDate,
  required User? Function() currentUser,
}) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppColors.whiteColor,
        title: const Text(
          'Select Appointment to Reschedule',
          style: TextStyle(color: AppColors.blackColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: userAppointments.map((doc) {
            String appointmentDate = doc['date'];
            // Stored as 'dd-MM-yyyy' (DateTime.parse threw on it)
            final parsedDate = Date_Utils.tryParseDateStrict(appointmentDate);
            return ListTile(
              title: Text(parsedDate != null
                  ? Date_Utils.formatDate(parsedDate)
                  : appointmentDate), // Format the date
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UpdateAppointmentScreen(
                      selectedAvailableDate: selectedAvailableDate,
                      currentAppointmentId: doc.id,
                      user: currentUser(),
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ),
        actions: <Widget>[
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
            },
            child: Container(
              height: 40,
              width: 110,
              decoration: BoxDecoration(
                  color: AppColors.appColor,
                  borderRadius: BorderRadius.circular(40)),
              child: const Center(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.whiteColor),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
