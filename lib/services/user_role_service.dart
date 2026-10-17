import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { patient, doctor, unknown }

/// Works out whether a signed-in user is a patient or a doctor.
///
/// PatientData / DoctorData documents are keyed by email as it was typed at
/// signup, which may differ in case from what Firebase Auth returns, so both
/// the document id and the `email` field are checked, as typed and lowercased.
class UserRoleService {
  static const String _roleKeyPrefix = 'user_role_';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<bool> _existsIn(String collection, String email) async {
    final variants = {email.trim(), email.trim().toLowerCase()};
    final checks = <Future<bool>>[];
    for (final e in variants) {
      checks.add(_db
          .collection(collection)
          .doc(e)
          .get()
          .then((doc) => doc.exists));
      checks.add(_db
          .collection(collection)
          .where('email', isEqualTo: e)
          .limit(1)
          .get()
          .then((snap) => snap.docs.isNotEmpty));
    }
    final results = await Future.wait(checks);
    return results.contains(true);
  }

  static Future<bool> isPatient(String email) => _existsIn('PatientData', email);

  static Future<bool> isDoctor(String email) => _existsIn('DoctorData', email);

  /// Throws if Firestore can't be reached, so callers can tell
  /// "no record" apart from "couldn't check".
  static Future<UserRole> resolveFromFirestore(String email) async {
    if (await isPatient(email)) return UserRole.patient;
    if (await isDoctor(email)) return UserRole.doctor;
    return UserRole.unknown;
  }

  /// Remembers the role a user last logged in with on this device.
  static Future<void> cacheRole(User user, UserRole role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_roleKeyPrefix${user.uid}', role.name);
    } catch (e) {
      if (kDebugMode) print('Could not cache user role: $e');
    }
  }

  static Future<UserRole> cachedRole(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString('$_roleKeyPrefix${user.uid}');
      return UserRole.values.firstWhere(
        (r) => r.name == value,
        orElse: () => UserRole.unknown,
      );
    } catch (_) {
      return UserRole.unknown;
    }
  }
}
