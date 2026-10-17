import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:my_appointment/res/color.dart';
import 'package:my_appointment/view/authentication/patient_auth/patient_lgoin_view.dart';

import '../../../res/components/round_button.dart';
import '../../../utils/utils.dart';

class PatientSignupView extends StatefulWidget {
  const PatientSignupView({super.key});

  @override
  State<PatientSignupView> createState() => _PatientSignupViewState();
}

class _PatientSignupViewState extends State<PatientSignupView> {
  final ValueNotifier<bool> _obscurePassword = ValueNotifier<bool>(true);
  TextEditingController nameCon = TextEditingController();
  TextEditingController emailCon = TextEditingController();
  TextEditingController passCon = TextEditingController();
  TextEditingController conPassCon = TextEditingController();

  FocusNode nameFocusNode = FocusNode();
  FocusNode emailFocusNode = FocusNode();
  FocusNode passwordFocusNode = FocusNode();
  FocusNode conformPasswordFocusNode = FocusNode();
  bool isLoading=true;
  @override
  void dispose() {
    super.dispose();
    nameCon.dispose();
    emailCon.dispose();
    passCon.dispose();
    conPassCon.dispose();
    nameFocusNode.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    conformPasswordFocusNode.dispose();
    _obscurePassword.dispose();
  }

  Future<void> _signUp() async {
    String name = nameCon.text.trim();
    // Lowercase so the PatientData id matches however the email is typed at login
    String email = emailCon.text.trim().toLowerCase();
    String password = passCon.text.trim();
    String confirmPassword = conPassCon.text.trim();

    if (name.isEmpty) {
      Utils.flushBarErrorMessagas('Please Enter Name', context);
    } else if (email.isEmpty) {
      Utils.flushBarErrorMessagas('Please Enter Email', context);
    } else if (password.isEmpty) {
      Utils.flushBarErrorMessagas('Please Enter Password', context);
    } else if (confirmPassword.isEmpty) {
      Utils.flushBarErrorMessagas('Please re-enter Password', context);
    } else if (password != confirmPassword) {
      Utils.flushBarErrorMessagas('Passwords do not match', context);
    } else {
      try {
        setState(() {
          isLoading=false;
        });
        // Create the account first: if it fails (email already used, weak
        // password) nothing is written to PatientData
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Storing user data in Firestore
        try {
          await FirebaseFirestore.instance
              .collection('PatientData')
              .doc(email)
              .set({
            'name': name,
            'email': email,
          }, SetOptions(merge: true));
        } catch (e) {
          // Don't leave an account without a patient record behind
          await credential.user?.delete();
          rethrow;
        }


        //Utils.snackBar('Sign up successful', context);
        Utils.flushBarSuccessMessagas('Sign up successful', context);

        setState(() {
          isLoading=true;
        });

        Navigator.push(context, CupertinoPageRoute(builder: (context)=>const PatientLoginView()));
        // Navigate to login or home screen
         //Navigator.pushNamed(context, RoutesName.doctor_login);
      } on FirebaseAuthException catch (e) {
        setState(() {
          isLoading=true;
        });
        Utils.flushBarErrorMessagas(e.message ?? 'An error occurred:${e.message}', context);
      } catch (e) {
        setState(() {
          isLoading=true;
        });
        Utils.flushBarErrorMessagas('An error occurred:$e', context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up', style: TextStyle(color: Colors.white)),
        centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          leading:  IconButton(
            icon:const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () {
              Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (context)=> const PatientLoginView()));
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
                "Sign Up Information.",
                style: TextStyle(
                  color: AppColors.blackColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                ),
                textAlign: TextAlign.left,
              ),
              SizedBox(height: height * .01),
              const Text(
                "We are asking for your information to onboard you.",
                style: TextStyle(color: AppColors.blackColor,fontWeight: FontWeight.bold),
                textAlign: TextAlign.left,
              ),
              SizedBox(height: height * .03),
              Padding(
                padding: const EdgeInsets.only(left: 15, right: 15),
                child: TextFormField(
                  controller: nameCon,
                  keyboardType: TextInputType.text,
                  cursorColor: AppColors.blackColor,
                  focusNode: nameFocusNode,
                  style: const TextStyle(color: AppColors.blackColor),
                  decoration: InputDecoration(
                    hintText: 'Name',
                    hintStyle: const TextStyle(color: AppColors.blackColor),
                    prefixIcon: const Icon(Icons.person_2_outlined, color: AppColors.blueAccent),
                    labelText: 'Name',
                    labelStyle:const  TextStyle(color: AppColors.blackColor),
                    filled: true,
                    fillColor: Colors.transparent,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: nameFocusNode.hasFocus ? AppColors.blackColor : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: nameFocusNode.hasFocus ? AppColors.blackColor : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onFieldSubmitted: (value) {
                    Utils.fieldFocusChanged(context, nameFocusNode, emailFocusNode);
                  },
                ),
              ),
               const SizedBox(height: 20),
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
                    prefixIcon: const Icon(Icons.alternate_email, color: AppColors.blueAccent),
                    labelText: 'Email',
                    labelStyle:const  TextStyle(color: AppColors.blackColor),
                    filled: true,
                    fillColor: Colors.transparent,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: emailFocusNode.hasFocus ? AppColors.blackColor : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: emailFocusNode.hasFocus ? AppColors.blackColor : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onFieldSubmitted: (value) {
                    Utils.fieldFocusChanged(context, emailFocusNode, passwordFocusNode);
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
                      cursorColor: Colors.white,
                      focusNode: passwordFocusNode,
                      style: const TextStyle(color: AppColors.blackColor),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: AppColors.blackColor),
                        prefixIcon: const Icon(Icons.lock_open_outlined, color: AppColors.blueAccent),
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: AppColors.blackColor),
                        filled: true,
                        fillColor: Colors.transparent,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: passwordFocusNode.hasFocus ?AppColors.blackColor : AppColors.blueAccent,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: passwordFocusNode.hasFocus ? AppColors.blackColor : AppColors.blueAccent,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppColors.redColor),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppColors.redColor),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        suffixIcon: InkWell(
                          onTap: () {
                            _obscurePassword.value = !_obscurePassword.value;
                          },
                          child: Icon(
                            _obscurePassword.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.blueAccent,
                          ),
                        ),
                      ),
                      onFieldSubmitted: (value) {
                        Utils.fieldFocusChanged(context, passwordFocusNode, conformPasswordFocusNode);
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder(
                valueListenable: _obscurePassword,
                builder: (context, value, child) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 15, right: 15),
                    child: TextFormField(
                      controller: conPassCon,
                      obscuringCharacter: '*',
                      obscureText: _obscurePassword.value,
                      cursorColor: AppColors.blackColor,
                      focusNode: conformPasswordFocusNode,
                      style: const TextStyle(color: AppColors.blackColor),
                      decoration: InputDecoration(
                        hintText: 'Conform Password',
                        hintStyle: const TextStyle(color: AppColors.blackColor),
                        prefixIcon: const Icon(Icons.lock_open_outlined, color: AppColors.blueAccent),
                        labelText: 'Conform Password',
                        labelStyle: const TextStyle(color: Colors.black45),
                        filled: true,
                        fillColor: Colors.transparent,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: conformPasswordFocusNode.hasFocus ? AppColors.blackColor : AppColors.redColor,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: conformPasswordFocusNode.hasFocus ? AppColors.blackColor : AppColors.redColor,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppColors.redColor),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppColors.redColor),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        suffixIcon: InkWell(
                          onTap: () {
                            _obscurePassword.value = !_obscurePassword.value;
                          },
                          child: Icon(
                            _obscurePassword.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.blueAccent,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: height * .02),
              isLoading?
              RoundButton(
                title: 'Continue',
                onPress: _signUp,
              ):const CircularProgressIndicator(backgroundColor: Colors.black45,),
            ],
          ),
        ),
      ),
    );
  }
}
