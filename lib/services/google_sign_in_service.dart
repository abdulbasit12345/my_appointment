import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Professional Google Sign In Service
/// Handles Google authentication and user data management
class GoogleSignInService {
  static final GoogleSignInService _instance = GoogleSignInService._internal();
  factory GoogleSignInService() => _instance;
  GoogleSignInService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with Google
  /// Returns UserCredential on success, null on failure
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Check internet connectivity
      await _checkInternetConnection();

      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in
        if (kDebugMode) {
          print('Google Sign In: User canceled');
        }
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      if (kDebugMode) {
        print('Google Sign In: Success');
        print('User: ${userCredential.user?.email}');
        print('Display Name: ${userCredential.user?.displayName}');
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('Google Sign In Firebase Error: ${e.code} - ${e.message}');
      }
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign In Error: $e');
      }
      rethrow;
    }
  }

  /// Check if user exists in PatientData collection
  Future<bool> userExistsInPatientData(String email) async {
    try {
      final doc = await _firestore.collection('PatientData').doc(email).get();
      return doc.exists;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking PatientData: $e');
      }
      return false;
    }
  }

  /// Check if user exists in DoctorData collection
  Future<bool> userExistsInDoctorData(String email) async {
    try {
      final doc = await _firestore.collection('DoctorData').doc(email).get();
      return doc.exists;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking DoctorData: $e');
      }
      return false;
    }
  }

  /// Create user in PatientData collection
  Future<void> createPatientUser(User user) async {
    try {
      final userData = {
        'name': user.displayName ?? 'User',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'authProvider': 'google',
      };

      await _firestore.collection('PatientData').doc(user.email).set(userData);

      if (kDebugMode) {
        print('Patient user created in Firestore');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating patient user: $e');
      }
      rethrow;
    }
  }

  /// Create user in DoctorData collection
  Future<void> createDoctorUser(User user) async {
    try {
      final userData = {
        'name': user.displayName ?? 'User',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'authProvider': 'google',
      };

      await _firestore.collection('DoctorData').doc(user.email).set(userData);

      if (kDebugMode) {
        print('Doctor user created in Firestore');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating doctor user: $e');
      }
      rethrow;
    }
  }

  /// Determine if user is a patient or doctor
  /// Returns 'patient', 'doctor', or null if neither exists
  Future<String?> getUserType(String email) async {
    try {
      final isPatient = await userExistsInPatientData(email);
      if (isPatient) return 'patient';

      final isDoctor = await userExistsInDoctorData(email);
      if (isDoctor) return 'doctor';

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error determining user type: $e');
      }
      return null;
    }
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
      if (kDebugMode) {
        print('Google Sign Out: Success');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign Out Error: $e');
      }
      rethrow;
    }
  }

  /// Check internet connection
  Future<void> _checkInternetConnection() async {
    try {
      await InternetAddress.lookup('google.com');
    } catch (e) {
      throw Exception('No internet connection. Please check your network.');
    }
  }
}

