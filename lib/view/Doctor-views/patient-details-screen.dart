
import 'package:flutter/material.dart';

import '../../res/color.dart';

class PatientDetailView extends StatelessWidget {
  final String name;
  final String date;
  final String status;
  final String address;
  final String phone;
  final String time;

   PatientDetailView({
    super.key,
    required this.name,
    required this.date,
    required this.status,
    required this.address,
    required this.phone,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Detail',style: TextStyle(color: AppColors.whiteColor),
        ),
        iconTheme: const IconThemeData(color: AppColors.whiteColor), // Change back arrow color to white
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: $name', style: const TextStyle(fontSize: 18, color: AppColors.blackColor)),
            const SizedBox(height: 10),
            Text('Date: $date', style: const TextStyle(fontSize: 18, color: AppColors.blackColor)),
            const SizedBox(height: 10),
            Text('Status: $status', style: const TextStyle(fontSize: 18, color: AppColors.blackColor)),
            Text('Address: $address', style: const TextStyle(fontSize: 18, color: AppColors.blackColor)),
            Text('Phone No:: $phone', style: const TextStyle(fontSize: 18, color: AppColors.blackColor)),
            Text('Time:: $time', style: const TextStyle(fontSize: 18, color: AppColors.blackColor)),
          ],
        ),
      ),
    );
  }
}
