import 'package:flutter/material.dart';
import 'package:my_appointment/utils/routes/routes_name.dart';

import '../../view/authentication/doctor_auth/doctor_login_view.dart';
import '../../view/authentication/patient_auth/patient_lgoin_view.dart';
import '../../view/authentication/patient_auth/patient_signup_view.dart';
import '../../view/dashboard/dashboard_screen.dart';




class Routes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      // case RoutesName.home:
      //   return MaterialPageRoute(
      //       builder: (BuildContext context) => const HomeScreen());
      case RoutesName.doctor_login:
        return MaterialPageRoute(
            builder: (BuildContext context) => const DoctorLoginView());
      case RoutesName.doctor_signUp:
        // return MaterialPageRoute(
        //     builder: (BuildContext context) => const DoctorSignupView());
      case RoutesName.patient_login:
        return MaterialPageRoute(
            builder: (BuildContext context) => const PatientLoginView());
      case RoutesName.patien_signUp:
        return MaterialPageRoute(
            builder: (BuildContext context) => const PatientSignupView());
      case RoutesName.dashboard:
        return MaterialPageRoute(
            builder: (BuildContext context) => const DashboardScreen());
      // case RoutesName.forgetPasswordView:
      //   return MaterialPageRoute(
      //       builder: (BuildContext context) => const ForgetPasswordView());
      // case RoutesName.google_signinView:
      //   return MaterialPageRoute(builder: (BuildContext context)=> const GoogleSigninView());

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
