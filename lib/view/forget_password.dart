import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../res/color.dart';
import '../res/components/round_button.dart';
import '../utils/utils.dart';

class ForgetPasswordView extends StatefulWidget {
  const ForgetPasswordView({super.key});

  @override
  State<ForgetPasswordView> createState() => _ForgetPasswordViewState();
}

class _ForgetPasswordViewState extends State<ForgetPasswordView> {
  final TextEditingController emailCon = TextEditingController();
  final FocusNode emailFocusNode = FocusNode();
  bool isSending = false;

  @override
  void dispose() {
    emailCon.dispose();
    emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    final email = emailCon.text.trim();
    if (email.isEmpty) {
      Utils.flushBarErrorMessagas('Please Enter Email', context);
      return;
    }
    if (!email.contains('@')) {
      Utils.flushBarErrorMessagas('Please enter a valid email', context);
      return;
    }

    setState(() => isSending = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      Utils.flushBarSuccessMessagas(
          'Password reset link sent. Please check your email.', context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'invalid-email' => 'Please enter a valid email',
        'user-not-found' => 'No account found for this email',
        'network-request-failed' =>
          'No internet connection. Please try again.',
        _ => e.message ?? 'Could not send reset email',
      };
      Utils.flushBarErrorMessagas(message, context);
    } catch (e) {
      if (!mounted) return;
      Utils.flushBarErrorMessagas('Could not send reset email', context);
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forget Password',
            style: TextStyle(color: AppColors.whiteColor)),
        centerTitle: true,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new, color: AppColors.whiteColor),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: height * .03),
              const Text(
                'Reset your password.',
                style: TextStyle(
                  color: AppColors.blackColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              SizedBox(height: height * .01),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 25),
                child: Text(
                  "Enter your account email and we'll send you a link to set a new password.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.blackColor),
                ),
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
                      borderSide: const BorderSide(color: AppColors.redColor),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppColors.blueAccent),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  onFieldSubmitted: (_) => _sendResetEmail(),
                ),
              ),
              SizedBox(height: height * .04),
              isSending
                  ? const CupertinoActivityIndicator()
                  : RoundButton(
                      title: 'Send Reset Link',
                      onPress: _sendResetEmail,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
