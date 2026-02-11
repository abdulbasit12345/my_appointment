import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_appointment/res/color.dart';
import 'package:my_appointment/utils/date_utils.dart';
import 'package:my_appointment/view/Doctor-views/doctor-home-screen.dart';
import 'package:my_appointment/view/dashboard/dashboard_screen.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';
import 'package:my_appointment/view/patient-views/mobile_booking_form.dart';
import 'package:my_appointment/view/selection_view.dart';

import 'firebase_options.dart';
import 'notification/notification_services.dart';

User? user = FirebaseAuth.instance.currentUser;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
//final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
//final DateFormat _dateFormat = DateFormat('dd-MM-yyyy');
//final DateFormat dateFormat = DateFormat(Date_Utils.formatDate('dd-MM-yyyy' as DateTime));

DateTime now = DateTime.now();
String dateFormat = Date_Utils.formatDate(now);

NotificationServices notificationServices = NotificationServices();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_FirebaseMessagingBegroudnHandler);

  runApp(const MyApp());
}

// this is for background notification (when app is in background, not terminated)
@pragma('vm:entry-point')
Future<void> _FirebaseMessagingBegroudnHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling a background message: ${message.messageId}");
  print("Background notification title: ${message.notification?.title}");
  print("Background notification body: ${message.notification?.body}");
  // Note: Don't call setupInteractMessage here - it should only be called once at app startup
  // Background handler is just for processing messages when app is in background
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/book',
            builder: (context, state) => const MobileBookingForm(),
          ),
          GoRoute(
            path: '/dashboard/new-appointment',
            builder: (context, state) {
              return Scaffold(
                backgroundColor: Colors.black54,
                body: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Dialog(
                        insetPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth > 800
                                ? 640
                                : constraints.maxWidth * 0.9,
                            maxHeight: constraints.maxHeight * 0.9,
                          ),
                          child: MobileBookingForm(
                            onSuccess: (patientName) {
                              context.pop();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      );

      return MaterialApp.router(
        title: 'MyAppointment',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(color: Colors.blueAccent),
        ),
        routerConfig: router,
      );
    }

    return MaterialApp(
      title: 'MyAppointment',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(color: Colors.blueAccent),
      ),
      navigatorKey: navigatorKey,
      routes: {
        '/book': (context) => const MobileBookingForm(),
      },
      home: const AppEntryPoint(),
    );
  }
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  _AppEntryPointState createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    Future.microtask(() => checkUserAuthentication());
  }

  // Initialize notifications at app startup (only for mobile platforms)
  Future<void> _initializeNotifications() async {
    // Skip notifications on web platform
    if (kIsWeb) {
      print('Skipping notifications initialization on web');
      return;
    }
    
    try {
      // Request notification permissions
      await notificationServices.requestNotificationPermission();
      
      // Setup notification listeners (handles foreground, background, and terminated states)
      await notificationServices.setupInteractMessage();
      
      // Setup iOS foreground notification presentation
      await notificationServices.forgroundMessage();
      
      print('Notifications initialized successfully');
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  void checkUserAuthentication() async {
    // If running on web, show dashboard directly (master dashboard - no auth required)
    if (kIsWeb) {
      Future.delayed(Duration.zero, () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      });
      return;
    }

    // Mobile platform: Use existing authentication-based routing
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // User is already logged in
      String userEmail = user.email!;
      bool isPatient = await checkIfPatient(userEmail);

      if (isPatient) {
        Future.delayed(Duration.zero, () {
          Navigator.of(context).pushReplacement(
            CupertinoPageRoute(
                builder: (context) => const PatientHomeViewNew()),
          );
        });
      } else {
        Future.delayed(Duration.zero, () {
          Navigator.of(context).pushReplacement(
            CupertinoPageRoute(builder: (context) => const DoctorHomeScreen()),
          );
        });
      }
    } else {
      // User is not logged in, navigate to SelectionView for login/signup
      Future.delayed(Duration.zero, () {
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(builder: (context) => const SelectionView()),
        );
      });
    }
  }

  Future<bool> checkIfPatient(String userEmail) async {
    try {
      // Query Firestore to check if there is a document in 'PatientData' collection
      // with a matching email
      var snapshot = await FirebaseFirestore.instance
          .collection('PatientData')
          .where('email', isEqualTo: userEmail)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking patient data: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.blackColor,
        ), // Show a loading indicator while checking authentication
      ),
    );
  }
}
