import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:my_appointment/view/authentication/patient_auth/patient_signup_view.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';
import 'package:my_appointment/view/selection_view.dart';
import 'package:my_appointment/view/google_signin.dart';

import '../../../res/color.dart';
import '../../../res/components/round_button.dart';
import '../../../services/user_role_service.dart';
import '../../../utils/routes/routes_name.dart';
import '../../../utils/utils.dart';

class PatientLoginView extends StatefulWidget {
  const PatientLoginView({super.key});

  @override
  State<PatientLoginView> createState() => _PatientLoginViewState();
}

class _PatientLoginViewState extends State<PatientLoginView> {
  final ValueNotifier<bool> _obscurePassword = ValueNotifier<bool>(true);
  TextEditingController emailCon = TextEditingController();
  TextEditingController passCon = TextEditingController();

  FocusNode emailFocusNode = FocusNode();
  FocusNode passwordFocusNode = FocusNode();
  bool isLoading = true;
  @override
  void dispose() {
    super.dispose();
    emailCon.dispose();
    passCon.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    _obscurePassword.dispose();
  }

  Future<void> _login() async {
    String email = emailCon.text.trim();
    String password = passCon.text.trim();

    if (email.isEmpty) {
      Utils.flushBarErrorMessagas('Please Enter Email', context);
    } else if (password.isEmpty) {
      Utils.flushBarErrorMessagas('Please Enter Password', context);
    } else if (password.length < 6) {
      Utils.flushBarErrorMessagas(
          'Password must be at least six characters', context);
    } else {
      try {
        setState(() {
          isLoading = false;
        });
        // Check if the email exists in Firestore (as typed or lowercased, so
        // 'Ali@x.com' and 'ali@x.com' both find the same patient)
        final bool isPatient = await UserRoleService.isPatient(email);

        if (!isPatient) {
          Utils.flushBarErrorMessagas('Email not found', context);
          setState(() {
            isLoading = true;
          });
          return;
        }

        // Email exists in Firestore, proceed with Firebase Auth login
        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        if (credential.user != null) {
          await UserRoleService.cacheRole(credential.user!, UserRole.patient);
        }

        // Utils.snackBar('Login successful', context);
        Utils.flushBarSuccessMessagas('Login successful', context);
        // Navigate to PatientHomeView
        //Navigator.pushNamed(context, RoutesName)
        //Navigator.pushReplacement(context, CupertinoPageRoute(builder: (context)=> const PatientHomeView()));
        Navigator.pushReplacement(
            context,
            CupertinoPageRoute(
                builder: (context) => const PatientHomeViewNew()));
        //Navigator.pushNamed(context, RoutesName.patientHomeView);
      } on FirebaseAuthException catch (e) {
        setState(() {
          isLoading = true;
        });
        Utils.flushBarErrorMessagas(e.message ?? 'An error occurred', context);
      } catch (e) {
        setState(() {
          isLoading = true;
        });
        Utils.flushBarErrorMessagas('An error occurred', context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 1;
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Login', style: TextStyle(color: AppColors.whiteColor)),
        centerTitle: true,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new, color: AppColors.whiteColor),
          onPressed: () {
            Navigator.of(context).pushReplacement(CupertinoPageRoute(
                builder: (context) => const SelectionView()));
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: height * .01),
              const Text(
                "Let's sign you in.",
                style: TextStyle(
                  color: AppColors.blackColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                ),
                textAlign: TextAlign.left,
              ),
              SizedBox(height: height * .01),
              const Text(
                "Welcome to My Appointment App.",
                style: TextStyle(
                    color: AppColors.blackColor, fontWeight: FontWeight.bold),
                textAlign: TextAlign.left,
              ),
              SizedBox(height: height * .03),
              Padding(
                padding: const EdgeInsets.only(left: 15, right: 15),
                child: TextFormField(
                  controller: emailCon,
                  keyboardType: TextInputType.emailAddress,
                  cursorColor: AppColors.blackColor,
                  focusNode: emailFocusNode,
                  style: const TextStyle(color: AppColors.blackColor),
                  decoration: InputDecoration(
                    hintText: 'Email',
                    hintStyle: const TextStyle(color: AppColors.blackColor),
                    prefixIcon: const Icon(Icons.alternate_email,
                        color: AppColors.blueAccent),
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: AppColors.blackColor),
                    filled: true,
                    fillColor: Colors.transparent,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: emailFocusNode.hasFocus
                            ? AppColors.blueAccent
                            : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: emailFocusNode.hasFocus
                            ? AppColors.blueAccent
                            : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onFieldSubmitted: (value) {
                    Utils.fieldFocusChanged(
                        context, emailFocusNode, passwordFocusNode);
                  },
                ),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder(
                valueListenable: _obscurePassword,
                builder: (context, value, child) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 15, right: 15),
                    child: TextFormField(
                      controller: passCon,
                      obscuringCharacter: '*',
                      obscureText: _obscurePassword.value,
                      cursorColor: AppColors.blackColor,
                      focusNode: passwordFocusNode,
                      style: const TextStyle(color: AppColors.blackColor),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: AppColors.blackColor),
                        prefixIcon: const Icon(Icons.lock_open_outlined,
                            color: AppColors.blueAccent),
                        labelText: 'Password',
                        labelStyle:
                            const TextStyle(color: AppColors.blackColor),
                        filled: true,
                        fillColor: Colors.transparent,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: passwordFocusNode.hasFocus
                                ? AppColors.blueAccent
                                : AppColors.redColor,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: passwordFocusNode.hasFocus
                                ? AppColors.blueAccent
                                : AppColors.redColor,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: AppColors.redColor),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide:
                              const BorderSide(color: AppColors.redColor),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        suffixIcon: InkWell(
                          onTap: () {
                            _obscurePassword.value = !_obscurePassword.value;
                          },
                          child: Icon(
                            _obscurePassword.value
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.blueAccent,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: height * .02),
              isLoading
                  ? RoundButton(
                      title: 'Login',
                      onPress: _login,
                    )
                  : const CircularProgressIndicator(
                      backgroundColor: AppColors.blackColor,
                    ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(right: 15.0, top: 7, bottom: 7),
                    child: InkWell(
                      onTap: () {
                        Navigator.pushNamed(
                            context, RoutesName.forgetPasswordView);
                        //Navigator.pushAndRemoveUntil(context, newRoute, predicate)
                      },
                      child: const Text('Forget Password?',
                          style: TextStyle(color: AppColors.blueAccent)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: height * .02),
              Padding(
                padding: const EdgeInsets.only(left: 50, right: 50),
                child: Row(
                  children: [
                    const Text("Don't have an account?",
                        style: TextStyle(color: AppColors.blackColor)),
                    const SizedBox(width: 5.0),
                    InkWell(
                      onTap: () {
                        //Navigator.pushNamed(context, RoutesName.patien_signUp);
                        //Navigator.pushNamed(context, RoutesName.patient_login);
                        Navigator.pushReplacement(
                            context,
                            CupertinoPageRoute(
                                builder: (context) =>
                                    const PatientSignupView()));
                      },
                      child: const Text("Sign Up Now!",
                          style: TextStyle(color: AppColors.blueAccent)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: height * .02),
              const Text('Or Continue With',
                  style: TextStyle(
                      color: AppColors.blackColor,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: height * .02),
              // Google Sign In Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: GoogleSignInButton(
                  userType: 'patient',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
