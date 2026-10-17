import 'package:flutter/material.dart';

import '../../../res/color.dart';
import '../../../res/components/buildDialogButton.dart';
import '../../../utils/date_utils.dart';

/// "Cancelled Appointment Details" dialog shown from the cancel icon on an
/// appointment card. "Confirm" closes it and calls [onConfirm].
void showCancelledAppointmentDetailsDialog({
  required BuildContext context,
  required String date,
  required String email,
  required String name,
  required VoidCallback onConfirm,
}) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppColors.blueAccent,
        title: const Text(
          'Cancelled Appointment Details',
          style: TextStyle(color: AppColors.whiteColor),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Date: ${Date_Utils.formatDate(Date_Utils.parseDate(date))}', // Format the date properly
              style: const TextStyle(color: AppColors.whiteColor),
            ),
            Text('Email: $email',
                style: const TextStyle(color: AppColors.whiteColor)),
            Text('Name: $name',
                style: const TextStyle(color: AppColors.whiteColor)),
          ],
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
                  'Close',
                  style: TextStyle(color: AppColors.whiteColor),
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            child: Container(
              height: 40,
              width: 110,
              decoration: BoxDecoration(
                  color: AppColors.appColor,
                  borderRadius: BorderRadius.circular(40)),
              child: const Center(
                child: Text(
                  'Confirm',
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

/// "Confirm Cancellation" dialog. "Yes" closes it and, after 200ms, awaits
/// [onConfirmCancel].
void showConfirmCancelDialog({
  required BuildContext context,
  required Future<void> Function() onConfirmCancel,
}) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: AppColors.blueAccent,
        title: const Text(
          'Confirm Cancellation',
          style: TextStyle(color: AppColors.whiteColor),
        ),
        content: const Text(
          'Are you sure you want to cancel this appointment?',
          style: TextStyle(color: AppColors.whiteColor),
        ),
        actions: <Widget>[
          buildDialogButton('No', () {
            Navigator.of(context).pop(); // Close the dialog.
          }),
          buildDialogButton('Yes', () async {
            // Close the dialog first to avoid UI freeze.
            Navigator.of(context).pop();

            // Delay the cancel operation to ensure smooth dialog transition.
            Future.delayed(Duration(milliseconds: 200), () async {
              await onConfirmCancel();
            });
          }),
        ],
      );
    },
  );
}
