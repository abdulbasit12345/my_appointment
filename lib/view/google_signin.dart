import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:my_appointment/services/google_sign_in_service.dart';
import 'package:my_appointment/utils/utils.dart';
import 'package:my_appointment/view/Doctor-views/doctor-home-screen.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';

/// Professional Google Sign In Button Widget
/// Can be used in both patient and doctor login screens
class GoogleSignInButton extends StatefulWidget {
  final String userType; // 'patient' or 'doctor'
  final VoidCallback? onSuccess;

  const GoogleSignInButton({
    super.key,
    required this.userType,
    this.onSuccess,
  });

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  final GoogleSignInService _googleSignInService = GoogleSignInService();
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Sign in with Google
      final UserCredential? userCredential =
          await _googleSignInService.signInWithGoogle();

      if (userCredential == null || userCredential.user == null) {
        // User canceled or sign-in failed
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final User user = userCredential.user!;
      final String email = user.email ?? '';

      if (email.isEmpty) {
        throw Exception('Email not found in Google account');
      }

      // Check if user exists in Firestore
      final String? existingUserType =
          await _googleSignInService.getUserType(email);

      if (existingUserType != null) {
        // User exists - verify they're signing in with correct type
        if (existingUserType != widget.userType) {
          setState(() {
            _isLoading = false;
          });
          if (mounted) {
            Utils.flushBarErrorMessagas(
              'This account is registered as a ${existingUserType == 'patient' ? 'Patient' : 'Doctor'}. Please use the ${existingUserType == 'patient' ? 'Patient' : 'Doctor'} login.',
              context,
            );
          }
          // Sign out since wrong account type
          await _googleSignInService.signOut();
          return;
        }
      } else {
        // New user - create account in appropriate collection
        if (widget.userType == 'patient') {
          await _googleSignInService.createPatientUser(user);
        } else {
          await _googleSignInService.createDoctorUser(user);
        }
      }

      // Navigate based on user type
      if (mounted) {
        Utils.flushBarSuccessMessagas('Sign in successful!', context);

        if (widget.userType == 'patient') {
          Navigator.of(context).pushReplacement(
            CupertinoPageRoute(
              builder: (context) => const PatientHomeViewNew(),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            CupertinoPageRoute(
              builder: (context) => const DoctorHomeScreen(),
            ),
          );
        }

        if (widget.onSuccess != null) {
          widget.onSuccess!();
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        String errorMessage = 'Sign in failed';
        switch (e.code) {
          case 'account-exists-with-different-credential':
            errorMessage =
                'An account already exists with a different sign-in method.';
            break;
          case 'invalid-credential':
            errorMessage = 'Invalid credentials. Please try again.';
            break;
          case 'operation-not-allowed':
            errorMessage = 'Google Sign In is not enabled.';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled.';
            break;
          case 'user-not-found':
            errorMessage = 'User not found.';
            break;
          default:
            errorMessage = e.message ?? 'An error occurred during sign in.';
        }
        Utils.flushBarErrorMessagas(errorMessage, context);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        String errorMessage = 'An error occurred during sign in.';
        if (e.toString().contains('internet') ||
            e.toString().contains('network')) {
          errorMessage = 'No internet connection. Please check your network.';
        }
        Utils.flushBarErrorMessagas(errorMessage, context);
      }
      if (kDebugMode) {
        print('Google Sign In Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isLoading ? null : _handleGoogleSignIn,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _isLoading
            ? const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google Icon
                  Image.asset(
                    'assets/google_login.jpg',
                    height: 24,
                    width: 24,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback if image doesn't exist
                      return const Icon(
                        Icons.login,
                        size: 24,
                        color: Colors.blue,
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  // Text
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
