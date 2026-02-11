
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../res/color.dart';
import '../../../res/components/round_button.dart';
import '../../../utils/routes/routes_name.dart';
import '../../../utils/utils.dart';
import '../../Doctor-views/doctor-home-screen.dart';
import '../../selection_view.dart';
import '../../google_signin.dart';

class DoctorLoginView extends StatefulWidget {
  const DoctorLoginView({super.key});

  @override
  State<DoctorLoginView> createState() => _DoctorLoginViewState();
}
class _DoctorLoginViewState extends State<DoctorLoginView> {
  final ValueNotifier<bool> _obscurePassword = ValueNotifier<bool>(true);
  TextEditingController emailCon = TextEditingController();
  TextEditingController passCon = TextEditingController();

  FocusNode emailFocusNode = FocusNode();
  FocusNode passwordFocusNode = FocusNode();
  bool isLoading=true;
  @override
  void dispose() {
    super.dispose();
    emailCon.dispose();
    passCon.dispose();
    emailFocusNode.dispose();
    passwordFocusNode.dispose();
    _obscurePassword.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login', style: TextStyle(color: AppColors.whiteColor)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,color: AppColors.whiteColor,),
          onPressed: (){
            Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (context)=>const SelectionView() ));
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
                style: TextStyle(color: AppColors.blackColor,fontWeight: FontWeight.bold),
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
                    prefixIcon: const Icon(Icons.alternate_email, color: AppColors.blackColor),
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: AppColors.blackColor),
                    filled: true,
                    fillColor: Colors.transparent,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: emailFocusNode.hasFocus ? AppColors.blueAccent : AppColors.redColor,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: emailFocusNode.hasFocus ? AppColors.blueAccent : AppColors.redColor,
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
                      cursorColor: AppColors.blackColor,
                      focusNode: passwordFocusNode,
                      style: const TextStyle(color: AppColors.blackColor),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: AppColors.blackColor),
                        prefixIcon: const Icon(Icons.lock_open_outlined, color: AppColors.blackColor),
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: AppColors.blackColor),
                        filled: true,
                        fillColor: Colors.transparent,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: passwordFocusNode.hasFocus ? AppColors.blueAccent : AppColors.redColor,
                          ),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: passwordFocusNode.hasFocus ? AppColors.blueAccent : AppColors.redColor,
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
                            color: AppColors.blackColor,
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
                title: 'Login',
                onPress: ()async {
                  if (emailCon.text.isEmpty) {
                    Utils.flushBarErrorMessagas('Please Enter Email', context);
                  } else if (passCon.text.isEmpty) {
                    Utils.flushBarErrorMessagas('Please Enter Password', context);
                  } else if (passCon.text.length < 6) {
                    Utils.flushBarErrorMessagas('Password must be at least six characters', context);
                  } else {
                    setState(() {
                      isLoading=false;
                    });
                    //Navigator.pushNamed(context, RoutesName.home);
                    await FirebaseAuth.instance.signInWithEmailAndPassword(
                        email: emailCon.text.trim(), password: passCon.text.trim()).then((onValue)
                    {
                      Utils.snackBar('Login Successfully', context);
                      Navigator.pushReplacement(context, CupertinoPageRoute(builder: (context)=>const DoctorHomeScreen()));
                    }).onError((error,handleError){
                      setState(() {
                        isLoading=true;
                      });
                      Utils.flushBarErrorMessagas(error.toString(), context);
                    });
                    /*Map data = {
                      'email': emailCon.text.toString(),
                      'password': passCon.text.toString(),
                    };*/
                  }
                },
              ):const CupertinoActivityIndicator(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 15.0, top: 7, bottom: 7),
                    child: InkWell(
                      onTap: (){
                        Navigator.pushNamed(context, RoutesName.forgetPasswordView);
                      },
                        child: const Text('Forget Password?', style: TextStyle(color: AppColors.blueAccent))),
                  ),
                ],
              ),
              SizedBox(height: height * .02),
              Padding(
                padding: const EdgeInsets.only(left: 50, right: 50),
                child: Row(
                  children: [
                    const Text("Don't have an account?", style: TextStyle(color: AppColors.blackColor)),
                    const SizedBox(width: 5.0),
                    InkWell(
                      onTap: () {
                        //Navigator.pushNamed(context, RoutesName.doctor_signUp);
                        //Navigator.push(context, CupertinoPageRoute(builder: (context)=>DoctorSignupView()));
                      },
                      child: const Text("Sign Up Now!", style: TextStyle(color: AppColors.blackColor)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: height * .02),
              const Text('Or Continue With', style: TextStyle(color: AppColors.blackColor, fontWeight: FontWeight.bold)),
              SizedBox(height: height * .02),
              // Google Sign In Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: GoogleSignInButton(
                  userType: 'doctor',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
