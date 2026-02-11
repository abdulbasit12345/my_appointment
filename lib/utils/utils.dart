
import 'package:another_flushbar/flushbar.dart';
import 'package:another_flushbar/flushbar_route.dart';
import 'package:flutter/material.dart';
import 'package:my_appointment/res/color.dart';


class Utils {
  /*static toastMessage(String message){
    Fluttertoast.showToast(msg: message );
  }
*/
  static void flushBarErrorMessagas(String message, BuildContext context) {
    showFlushbar(
        context: context,
        flushbar: Flushbar(
          forwardAnimationCurve: Curves.decelerate,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          padding: const EdgeInsets.all(15),
          titleColor: Colors.white,

          borderRadius: BorderRadius.circular(10),
          reverseAnimationCurve: Curves.easeOut,
          backgroundColor: AppColors.blackColor,
          flushbarPosition: FlushbarPosition.TOP,
          positionOffset: 20,
          message: message,
          //title: 'SAD',
          messageColor: Colors.white,
          duration: const Duration(seconds: 3),
          icon: const Icon(
            Icons.error,
            size: 20,
            color: Colors.white,
          ),
        )..show(context));
  }



  static void flushBarSuccessMessagas(String message, BuildContext context) {
    showFlushbar(
        context: context,
        flushbar: Flushbar(
          forwardAnimationCurve: Curves.decelerate,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          padding: const EdgeInsets.all(15),
          titleColor: AppColors.whiteColor,

          borderRadius: BorderRadius.circular(10),
          reverseAnimationCurve: Curves.easeOut,
          backgroundColor: AppColors.blackColor,
          flushbarPosition: FlushbarPosition.TOP,
          positionOffset: 20,
          message: message,
          //title: 'SAD',
          messageColor: Colors.white,
          duration: const Duration(seconds: 3),
          icon: const Icon(
            Icons.error,
            size: 20,
            color: AppColors.whiteColor,
          ),
        )..show(context));
  }

  static snackBar(String message, BuildContext context) {
    return ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.blackColor,
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 28,
          ),
        )));
  }

  static void fieldFocusChanged(
      BuildContext context, FocusNode currentFocus, FocusNode nextFocus) {
    currentFocus.unfocus();
    FocusScope.of(context).requestFocus(nextFocus);
  }
}
