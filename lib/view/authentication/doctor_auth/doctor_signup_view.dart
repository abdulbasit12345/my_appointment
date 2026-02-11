//
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart';
//
//
// class DoctorSignupView extends StatefulWidget {
//   const DoctorSignupView({super.key});
//
//   @override
//   State<DoctorSignupView> createState() => _DoctorSignupViewState();
// }
//
// class _DoctorSignupViewState extends State<DoctorSignupView> {
//   bool isLoading=true;
//   ValueNotifier<bool> _obscurePassword = ValueNotifier<bool>(true);
//   TextEditingController nameCon = TextEditingController();
//   TextEditingController emailCon = TextEditingController();
//   TextEditingController passCon = TextEditingController();
//   TextEditingController conPassCon = TextEditingController();
//
//   FocusNode nameFocusNode = FocusNode();
//   FocusNode emailFocusNode = FocusNode();
//   FocusNode passwordFocusNode = FocusNode();
//   FocusNode conformPasswordFocusNode = FocusNode();
//
//   @override
//   void dispose() {
//     super.dispose();
//     nameCon.dispose();
//     emailCon.dispose();
//     passCon.dispose();
//     conPassCon.dispose();
//     nameFocusNode.dispose();
//     emailFocusNode.dispose();
//     passwordFocusNode.dispose();
//     conformPasswordFocusNode.dispose();
//     _obscurePassword.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final height = MediaQuery.of(context).size.height * 1;
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Sign Up', style: TextStyle(color: AppColors.whiteColor)),
//         centerTitle: true,
//       ),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           scrollDirection: Axis.vertical,
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             crossAxisAlignment: CrossAxisAlignment.center,
//             children: [
//               SizedBox(height: height * .01),
//               Text(
//                 "Sign Up Information.",
//                 style: TextStyle(
//                   color: AppColors.whiteColor,
//                   fontWeight: FontWeight.bold,
//                   fontSize: 30,
//                 ),
//                 textAlign: TextAlign.left,
//               ),
//               SizedBox(height: height * .01),
//               Text(
//                 "We are asking for your information to onboard you.",
//                 style: TextStyle(color: AppColors.whiteColor),
//                 textAlign: TextAlign.left,
//               ),
//               SizedBox(height: height * .03),
//               Padding(
//                 padding: EdgeInsets.only(left: 15, right: 15),
//                 child: TextFormField(
//                   controller: nameCon,
//                   keyboardType: TextInputType.text,
//                   cursorColor: AppColors.whiteColor,
//                   focusNode: nameFocusNode,
//                   style: TextStyle(color: AppColors.whiteColor),
//                   decoration: InputDecoration(
//                     hintText: 'Name',
//                     hintStyle: TextStyle(color: AppColors.whiteColor),
//                     prefixIcon: Icon(Icons.person_2_outlined, color: AppColors.yellowColor),
//                     labelText: 'Name',
//                     labelStyle: TextStyle(color: AppColors.whiteColor),
//                     filled: true,
//                     fillColor: Colors.transparent,
//                     enabledBorder: OutlineInputBorder(
//                       borderSide: BorderSide(
//                         color: nameFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                       ),
//                       borderRadius: BorderRadius.circular(8.0),
//                     ),
//                     focusedBorder: OutlineInputBorder(
//                       borderSide: BorderSide(
//                         color: nameFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                       ),
//                       borderRadius: BorderRadius.circular(8.0),
//                     ),
//                   ),
//                   onFieldSubmitted: (value) {
//                     Utils.fieldFocusChanged(context, nameFocusNode, emailFocusNode);
//                   },
//                 ),
//               ),
//               SizedBox(height: 20),
//               Padding(
//                 padding: EdgeInsets.only(left: 15, right: 15),
//                 child: TextFormField(
//                   controller: emailCon,
//                   keyboardType: TextInputType.emailAddress,
//                   cursorColor: AppColors.whiteColor,
//                   focusNode: emailFocusNode,
//                   style: TextStyle(color: AppColors.whiteColor),
//                   decoration: InputDecoration(
//                     hintText: 'Email',
//                     hintStyle: TextStyle(color: AppColors.whiteColor),
//                     prefixIcon: Icon(Icons.alternate_email, color: AppColors.yellowColor),
//                     labelText: 'Email',
//                     labelStyle: TextStyle(color: AppColors.whiteColor),
//                     filled: true,
//                     fillColor: Colors.transparent,
//                     enabledBorder: OutlineInputBorder(
//                       borderSide: BorderSide(
//                         color: emailFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                       ),
//                       borderRadius: BorderRadius.circular(8.0),
//                     ),
//                     focusedBorder: OutlineInputBorder(
//                       borderSide: BorderSide(
//                         color: emailFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                       ),
//                       borderRadius: BorderRadius.circular(8.0),
//                     ),
//                   ),
//                   onFieldSubmitted: (value) {
//                     Utils.fieldFocusChanged(context, emailFocusNode, passwordFocusNode);
//                   },
//                 ),
//               ),
//               SizedBox(height: 20),
//               ValueListenableBuilder(
//                 valueListenable: _obscurePassword,
//                 builder: (context, value, child) {
//                   return Padding(
//                     padding: EdgeInsets.only(left: 15, right: 15),
//                     child: TextFormField(
//                       controller: passCon,
//                       obscuringCharacter: '*',
//                       obscureText: _obscurePassword.value,
//                       cursorColor: AppColors.whiteColor,
//                       focusNode: passwordFocusNode,
//                       style: TextStyle(color: AppColors.whiteColor),
//                       decoration: InputDecoration(
//                         hintText: 'Password',
//                         hintStyle: TextStyle(color: AppColors.whiteColor),
//                         prefixIcon: Icon(Icons.lock_open_outlined, color: AppColors.yellowColor),
//                         labelText: 'Password',
//                         labelStyle: TextStyle(color: AppColors.whiteColor),
//                         filled: true,
//                         fillColor: Colors.transparent,
//                         enabledBorder: OutlineInputBorder(
//                           borderSide: BorderSide(
//                             color: passwordFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                           ),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         focusedBorder: OutlineInputBorder(
//                           borderSide: BorderSide(
//                             color: passwordFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                           ),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         errorBorder: OutlineInputBorder(
//                           borderSide: BorderSide(color: AppColors.redColor),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         focusedErrorBorder: OutlineInputBorder(
//                           borderSide: BorderSide(color: AppColors.redColor),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         suffixIcon: InkWell(
//                           onTap: () {
//                             _obscurePassword.value = !_obscurePassword.value;
//                           },
//                           child: Icon(
//                             _obscurePassword.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
//                             color: AppColors.whiteColor,
//                           ),
//                         ),
//                       ),
//                       onFieldSubmitted: (value) {
//                         Utils.fieldFocusChanged(context, passwordFocusNode, conformPasswordFocusNode);
//                       },
//                     ),
//                   );
//                 },
//               ),
//               SizedBox(height: 20),
//               ValueListenableBuilder(
//                 valueListenable: _obscurePassword,
//                 builder: (context, value, child) {
//                   return Padding(
//                     padding: EdgeInsets.only(left: 15, right: 15),
//                     child: TextFormField(
//                       controller: conPassCon,
//                       obscuringCharacter: '*',
//                       obscureText: _obscurePassword.value,
//                       cursorColor: AppColors.whiteColor,
//                       focusNode: conformPasswordFocusNode,
//                       style: TextStyle(color: AppColors.whiteColor),
//                       decoration: InputDecoration(
//                         hintText: 'Conform Password',
//                         hintStyle: TextStyle(color: AppColors.whiteColor),
//                         prefixIcon: Icon(Icons.lock_open_outlined, color: AppColors.yellowColor),
//                         labelText: 'Conform Password',
//                         labelStyle: TextStyle(color: AppColors.whiteColor),
//                         filled: true,
//                         fillColor: Colors.transparent,
//                         enabledBorder: OutlineInputBorder(
//                           borderSide: BorderSide(
//                             color: conformPasswordFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                           ),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         focusedBorder: OutlineInputBorder(
//                           borderSide: BorderSide(
//                             color: conformPasswordFocusNode.hasFocus ? AppColors.yellowColor : AppColors.redColor,
//                           ),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         errorBorder: OutlineInputBorder(
//                           borderSide: BorderSide(color: AppColors.redColor),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         focusedErrorBorder: OutlineInputBorder(
//                           borderSide: BorderSide(color: AppColors.redColor),
//                           borderRadius: BorderRadius.circular(8.0),
//                         ),
//                         suffixIcon: InkWell(
//                           onTap: () {
//                             _obscurePassword.value = !_obscurePassword.value;
//                           },
//                           child: Icon(
//                             _obscurePassword.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
//                             color: AppColors.whiteColor,
//                           ),
//                         ),
//                       ),
//                     ),
//                   );
//                 },
//               ),
//               SizedBox(height: height * .02),
//               RoundButton(
//                 title: 'Continue',
//                 onPress: () async{
//                   if (nameCon.text.isEmpty) {
//                     Utils.flushBarErrorMessagas('Please Enter Name', context);
//                   } else if (emailCon.text.isEmpty) {
//                     Utils.flushBarErrorMessagas('Please Enter Email', context);
//                   }else if (passCon.text.isEmpty) {
//                     Utils.flushBarErrorMessagas('Please Enter Password', context);
//                   }else if (conPassCon.text.isEmpty) {
//                     Utils.flushBarErrorMessagas('Please re-enter Password', context);
//                   } else {
//                     setState(() {
//                       isLoading=false;
//                     });
//                     //Navigator.pushNamed(context, RoutesName.home);
//                     await FirebaseAuth.instance.signInWithEmailAndPassword(
//                         email: emailCon.text.trim(), password: passCon.text.trim()).then((onValue)
//                     {
//                       Utils.snackBar('Login Successfully', context);
//                       Navigator.pushReplacement(context,
//                           CupertinoPageRoute(builder: (context)=>DoctorHomeScreen())
//                       );
//                     }).onError((error,handleError){
//                       setState(() {
//                         isLoading=true;
//                       });
//                       Utils.flushBarErrorMessagas(error.toString(), context);
//                     });
//
//                     /*Map data = {
//                       'email': emailCon.text.toString(),
//                       'password': passCon.text.toString(),
//                     };*/
//                   }
//                 },
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
