import 'package:flutter/material.dart';

import '../color.dart';


class RoundButton extends StatelessWidget {
  final String title;
  final bool loading;
  final VoidCallback onPress;

  const RoundButton({super.key,
    required this.title,
    this.loading=false,
    required this.onPress,

  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPress,
      child: Container(
        height: 50,
        width: 350,
        decoration: BoxDecoration(
          color: AppColors.blueAccent,
          borderRadius: BorderRadius.circular(10)
        ),
        child: Center(child:loading? const CircularProgressIndicator(color: Colors.white,): Text(title,
           style: const TextStyle(color: AppColors.whiteColor,fontWeight: FontWeight.bold,fontSize: 22),
    )),
      ),
    );
  }
}
