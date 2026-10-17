import 'package:flutter/material.dart';
import 'package:my_appointment/utils/routes/routes_name.dart';

import '../../view/authentication/doctor_auth/doctor_login_view.dart';
import '../../view/authentication/patient_auth/patient_lgoin_view.dart';
import '../../view/authentication/patient_auth/patient_signup_view.dart';
import '../../view/dashboard/dashboard_screen.dart';
import '../../view/forget_password.dart';




class Routes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RoutesName.doctor_login:
        return MaterialPageRoute(
            builder: (BuildContext context) => const DoctorLoginView());
      case RoutesName.doctor_signUp:
        // Doctor email signup is disabled (there is no doctor signup screen);
        // send doctors to login, where Google sign-in creates the account.
        // Without this return the case fell through to patient login.
        return MaterialPageRoute(
            builder: (BuildContext context) => const DoctorLoginView());
      case RoutesName.patient_login:
        return MaterialPageRoute(
            builder: (BuildContext context) => const PatientLoginView());
      case RoutesName.patien_signUp:
        return MaterialPageRoute(
            builder: (BuildContext context) => const PatientSignupView());
      case RoutesName.dashboard:
        return MaterialPageRoute(
            builder: (BuildContext context) => const DashboardScreen());
      case RoutesName.forgetPasswordView:
        return MaterialPageRoute(
            builder: (BuildContext context) => const ForgetPasswordView());

      default:
        return MaterialPageRoute(builder: (_) {
          return const Scaffold(
            body: Center(
              child: Text('No routes defined'),
            ),
          );
        });
    }
  }
}
