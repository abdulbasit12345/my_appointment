import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_appointment/res/color.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';

class DialogScreen extends StatefulWidget {
  const DialogScreen({super.key});

  @override
  State<DialogScreen> createState() => _DialogScreenState();
}

class _DialogScreenState extends State<DialogScreen> {
  // Change the date format
  final DateFormat dateFormat = DateFormat('dd-MM-yyyy');

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

class UpdateAppointmentScreen extends StatelessWidget {
  final String currentAppointmentId;
  final String selectedAvailableDate;
  final User? user;

  UpdateAppointmentScreen(
      {super.key,
      required this.currentAppointmentId,
      required this.selectedAvailableDate,
      required this.user});

  // Change the date format to dd-MM-yyyy
  final DateFormat dateFormat = DateFormat('dd-MM-yyyy');

  Future<void> updateAppointment() async {
    // Cancel the current appointment
    await FirebaseFirestore.instance
        .collection('Appointments')
        .doc(currentAppointmentId)
        .update({'status': 'cancelled'});

    // Create a new appointment with the available date in the new format
    await FirebaseFirestore.instance
        .collection('Appointments')
        .doc(selectedAvailableDate)
        .update({
      'date':
          selectedAvailableDate, // Assuming selectedAvailableDate is in the correct format
      'email': user?.email,
      'status': 'active',
      // Add other necessary fields here
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Appointment'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current Appointment ID: $currentAppointmentId',
                style: TextStyle(
                  color: AppColors.blackColor,
                )),
            Text('New Appointment Date: $selectedAvailableDate',
                style: TextStyle(
                  color: AppColors.blackColor,
                )),
            ElevatedButton(
              onPressed: () async {
                await updateAppointment();
                //Navigator.of(context).pop(); // Go back to the previous screen
                Navigator.of(context).pushReplacement(CupertinoPageRoute(
                    builder: (context) => const PatientHomeViewNew()));
              },
              child: const Text('Confirm Update',
                  style: TextStyle(
                    color: AppColors.blackColor,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
