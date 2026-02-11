import 'package:flutter/material.dart';

import '../color.dart';

Widget buildDialogButton(String text, VoidCallback onPressed) {
  return InkWell(
    onTap: onPressed,
    child: Container(
      height: 40,
      width: 110,
      decoration: BoxDecoration(
        color: AppColors.appColor,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Center(
        child: Text(text, style: const TextStyle(color: AppColors.whiteColor)),
      ),
    ),
  );
}
