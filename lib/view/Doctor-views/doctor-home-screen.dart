import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_appointment/view/Doctor-views/patient-details-screen.dart';
import 'package:my_appointment/view/authentication/doctor_auth/doctor_login_view.dart';

import '../../res/color.dart';
import '../../res/components/status_badge.dart';
import '../../utils/appointment_status.dart';
import '../../utils/date_utils.dart';
import '../selection_view.dart';

class DoctorHomeScreen extends StatefulWidget {
  const DoctorHomeScreen({super.key,});

  @override
  State<DoctorHomeScreen> createState() => _DoctorHomeScreenState();
}

class _DoctorHomeScreenState extends State<DoctorHomeScreen> {
  @override
  void initState() {
    super.initState();
  }

  Stream<QuerySnapshot> _getAppointments() {
    return FirebaseFirestore.instance
        .collection('Appointments')
        .where('status', whereIn: AppointmentStatus.bookedValues) // All booked statuses (active, CONFIRMED, ...)
        .snapshots();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (context)=> const SelectionView()));

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Available Patients', style: TextStyle(color: AppColors.whiteColor)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,color: AppColors.whiteColor,),
          onPressed: () async {
            // Going back to the login screen ends the session, so the doctor
            // isn't silently logged back in on the next launch
            await FirebaseAuth.instance.signOut();
            if (!context.mounted) return;
            Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (context)=>const DoctorLoginView() ));
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout,color: AppColors.whiteColor,),
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Aligns the content to the start (left)
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.start, // Aligns the "Patients List" text to the left
              children: [
                 Text(
                  'Patients List',
                  style: TextStyle(fontSize: 18, color: AppColors.blackColor,fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getAppointments(),
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
                        'No appointments found',
                        style: TextStyle(color: AppColors.blackColor),
                      ),
                    );
                  }

                  final currentDate = DateTime.now();
                  final currentDateOnly = DateTime(currentDate.year, currentDate.month, currentDate.day);
                  
                  // Filter appointments with proper error handling
                  final List<DocumentSnapshot> validAppointments = [];
                  
                  for (final document in snapshot.data!.docs) {
                    try {
                      final Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
                      final dateString = data['date'] as String?;
                      
                      if (dateString == null || dateString.isEmpty) {
                        if (kDebugMode) {
                          print('Skipping appointment ${document.id}: date is null or empty');
                        }
                        continue; // Skip appointments without dates
                      }
                      
                      // Use Date_Utils to parse the date in 'dd-MM-yyyy' format
                      // This will throw FormatException if the date format is invalid
                      DateTime appointmentDate;
                      try {
                        appointmentDate = Date_Utils.parseDate(dateString);
                      } catch (parseError) {
                        if (kDebugMode) {
                          print('Error parsing date "$dateString" for appointment ${document.id}: $parseError');
                        }
                        continue; // Skip this appointment if date parsing fails
                      }
                      
                      final appointmentDateOnly = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day);
                      
                      // Only show appointments that are today or in the future
                      if (appointmentDateOnly.isAfter(currentDateOnly) || appointmentDateOnly.isAtSameMomentAs(currentDateOnly)) {
                        validAppointments.add(document);
                      }
                    } catch (e, stackTrace) {
                      // Catch any other unexpected errors
                      if (kDebugMode) {
                        print('Unexpected error processing appointment ${document.id}: $e');
                        print('Stack trace: $stackTrace');
                      }
                      // Skip this appointment and continue with others
                      continue;
                    }
                  }

                  if (validAppointments.isEmpty) {
                    return const Center(
                      child: Text(
                        'No valid appointments found',
                        style: TextStyle(color: AppColors.blackColor),
                      ),
                    );
                  }

                  return ListView(
                    children: validAppointments.map((DocumentSnapshot document) {
                      Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
                      String appointmentStatus = data['status']?.toString() ?? 'active';
                      
                      return Card(
                        color: Colors.grey,
                        child: ListTile(
                          title: Text(
                            'Patient Name: ${data['name']}',
                            style: const TextStyle(color: AppColors.redColor),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Date: ${data['date']}',
                                style: const TextStyle(color: AppColors.whiteColor),
                              ),
                              Text(
                                'Time: ${data['time']}',
                                style: const TextStyle(color: AppColors.whiteColor),
                              ),
                              const SizedBox(height: 4),
                              StatusBadge(status: appointmentStatus),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context, CupertinoPageRoute(builder: (context) => PatientDetailView(
                                  // Web/CSV bookings can have null fields
                                  name: data['name']?.toString() ?? '',
                                  date: data['date']?.toString() ?? '',
                                  status: appointmentStatus,
                                  address: data['address']?.toString() ?? '',
                                  phone: data['phone']?.toString() ?? '',
                                  time: data['time']?.toString() ?? '',
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),

      ),
    );
  }
}
