import 'package:flutter/material.dart';

import '../../../res/color.dart';

/// App bar of the patient home screen ("AAFIA App" + logout action).
AppBar buildPatientHomeAppBar({required VoidCallback onLogout}) {
  return AppBar(
    title: const Text(
      'AAFIA App',
      style: TextStyle(color: AppColors.whiteColor),
    ),
    centerTitle: true,
    automaticallyImplyLeading: false,
    actions: [
      IconButton(
        icon: const Icon(Icons.logout, color: AppColors.whiteColor),
        onPressed: onLogout,
      ),
    ],
  );
}
