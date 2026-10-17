import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_appointment/main.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';
import 'package:my_appointment/view/patient-views/slot_claim_screen.dart';

import 'message_screen.dart';
import 'notification_history.dart';
import 'notification_logger.dart';
import 'notification_preferences.dart';

class NotificationServices {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  //to show the notification on device
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // Track if listeners are already set up to avoid duplicates
  bool _listenersInitialized = false;
  bool _localNotificationsInitialized = false;

  /// Request notification permission with proper error handling
  Future<bool> requestNotificationPermission() async {
    try {
      if (kDebugMode) {
        print('=== REQUESTING NOTIFICATION PERMISSION ===');
      }
      
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: true,
        criticalAlert: true,
        provisional: true,
        sound: true,
      );

      final bool isAuthorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      if (kDebugMode) {
        print('Permission Status: ${settings.authorizationStatus}');
        print('Alert: ${settings.alert}');
        print('Badge: ${settings.badge}');
        print('Sound: ${settings.sound}');
        print('Is Authorized: $isAuthorized');
      }

      if (isAuthorized) {
        NotificationLogger.info(
          'Notification permission granted',
          {'status': settings.authorizationStatus.toString()},
        );
        await NotificationPreferences.setNotificationsEnabled(true);
        if (kDebugMode) {
          print('✓ Notification permission GRANTED');
        }
      } else {
        NotificationLogger.warning(
          'Notification permission denied',
          {'status': settings.authorizationStatus.toString()},
        );
        await NotificationPreferences.setNotificationsEnabled(false);
        if (kDebugMode) {
          print('✗ Notification permission DENIED');
          print('User must enable notifications in iOS Settings > Your App > Notifications');
        }
      }

      return isAuthorized;
    } catch (e, stackTrace) {
      NotificationLogger.error(
        'Error requesting notification permission',
        e,
        stackTrace,
      );
      if (kDebugMode) {
        print('✗ ERROR requesting permission: $e');
      }
      return false;
    }
  }

  /// Get device token and save it to Firestore with error handling
  Future<String?> getDeviceToken(String userId) async {
    try {
      // Check notification permission status first
      NotificationSettings settings = await messaging.getNotificationSettings();
      if (kDebugMode) {
        print('=== DEVICE TOKEN DEBUG ===');
        print('Authorization Status: ${settings.authorizationStatus}');
        print('Alert: ${settings.alert}');
        print('Badge: ${settings.badge}');
        print('Sound: ${settings.sound}');
      }
      
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        NotificationLogger.warning('Notification permission denied - cannot get device token');
        if (kDebugMode) {
          print('⚠️ NOTIFICATION PERMISSION DENIED - User must grant permission in Settings');
        }
        return null;
      }
      
      String? token = await messaging.getToken();

      if (token != null) {
        if (kDebugMode) {
          print('✓ Device token obtained: ${token.substring(0, 20)}...');
          print('Token length: ${token.length}');
        }
        
        await FirebaseFirestore.instance
            .collection('TokenData')
            .doc(userId)
            .set({
          'deviceToken': token,
          'updatedAt': FieldValue.serverTimestamp(),
          'platform': Platform.isIOS ? 'ios' : 'android',
        }, SetOptions(merge: true));

        isTokenRefresh(userId);
        NotificationLogger.info('Device token saved', {'userId': userId, 'platform': Platform.isIOS ? 'ios' : 'android'});
        
        if (kDebugMode) {
          print('✓ Device token saved to Firestore');
        }
      } else {
        NotificationLogger.warning('Failed to get device token - token is null');
        if (kDebugMode) {
          print('✗ ERROR: Device token is null');
          print('Possible causes:');
          print('  1. Running on iOS Simulator (FCM does not work on simulator)');
          print('  2. APNs not configured in Firebase Console');
          print('  3. Push Notifications capability not enabled in Xcode');
          print('  4. Notification permissions not granted');
        }
      }

      return token;
    } catch (e, stackTrace) {
      NotificationLogger.error('Error getting device token', e, stackTrace);
      if (kDebugMode) {
        print('✗ ERROR getting device token: $e');
        print('Stack trace: $stackTrace');
      }
      return null;
    }
  }

  /// Handle token refresh and update Firestore automatically
  void isTokenRefresh(String userId) {
    messaging.onTokenRefresh.listen((newToken) async {
      try {
        NotificationLogger.info('Token refreshed', {'userId': userId});
        await FirebaseFirestore.instance
            .collection('TokenData')
            .doc(userId)
            .set({
          'deviceToken': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e, stackTrace) {
        NotificationLogger.error(
          'Error updating refreshed token',
          e,
          stackTrace,
        );
      }
    });
  }

  // Initialize local notifications plugin (call this once at app startup)
  Future<void> initLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    
    var androidInitialization =
        const AndroidInitializationSettings('@mipmap/ic_launcher');
    var iosInitialization = const DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    var initializationSetting = InitializationSettings(
      android: androidInitialization,
      iOS: iosInitialization,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSetting,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap when app is in foreground or background
        // Check if user clicked an action button (like "Claim Slot")
        if (response.actionId != null && response.actionId == 'claim') {
          // User clicked "Claim Slot" - parse payload and navigate to SlotClaimScreen
          if (response.payload != null) {
            try {
              if (kDebugMode) {
                print('Claim Slot action clicked, payload: ${response.payload}');
              }
              
              // Parse the JSON payload to get notification data
              final payloadData = jsonDecode(response.payload!);
              final notificationData = payloadData['data'] as Map<String, dynamic>?;
              final notificationType = payloadData['type'] as String?;

              if (kDebugMode) {
                print('Parsed notification type: $notificationType');
                print('Parsed notification data: $notificationData');
              }

              if (notificationData != null &&
                  (notificationType == 'slot_available' ||
                      notificationType == 'cascaded_slot_available')) {
                final availableDate = notificationData['availableDate'] ?? '';
                final availableTime = notificationData['availableTime'] ?? '';
                final hospital = notificationData['hospital'] ?? '';
                final operationType = notificationData['operationType'] ?? '';
                final newSlotId = notificationData['newSlotId']; // Enhanced: Get slot ID for deep linking

                if (kDebugMode) {
                  print('Navigating to SlotClaimScreen with:');
                  print('  Date: $availableDate');
                  print('  Time: $availableTime');
                  print('  Hospital: $hospital');
                  print('  Operation: $operationType');
                  print('  New Slot ID: $newSlotId');
                }

                // Navigate directly to SlotClaimScreen with the notification data
                // Pass newSlotId if available for enhanced deep linking
                navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => SlotClaimScreen(
                      availableDate: availableDate,
                      availableTime: availableTime,
                      hospital: hospital,
                      operationType: operationType,
                      notificationType: notificationType ?? 'slot_available',
                      newSlotId: newSlotId, // Pass newSlotId for deep linking
                    ),
                  ),
                  (route) => false,
                );
                return;
              } else {
                if (kDebugMode) {
                  print('Invalid notification data or type for claim slot');
                }
              }
            } catch (e, stackTrace) {
              NotificationLogger.error(
                'Error parsing claim slot notification payload',
                e,
                stackTrace,
              );
              if (kDebugMode) {
                print('Error parsing payload: $e');
                print('Payload was: ${response.payload}');
              }
            }
          } else {
            if (kDebugMode) {
              print('Claim Slot action clicked but payload is null');
            }
          }
          // Fallback: navigate to home if payload parsing fails
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const PatientHomeViewNew(),
            ),
            (route) => false,
          );
        } else if (response.payload != null) {
          try {
            // Parse the payload if it's JSON, otherwise handle as needed
            // Navigate to home screen - MessageScreen will handle detailed navigation
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => const PatientHomeViewNew(),
              ),
            );
          } catch (e, stackTrace) {
            NotificationLogger.error(
              'Error handling notification response',
              e,
              stackTrace,
            );
          }
        }
      },
    );
    
    _localNotificationsInitialized = true;
  }

  void firebaseInit(BuildContext context) {
    // This method is kept for backward compatibility but setupInteractMessage handles everything
    // No need to duplicate the onMessage listener here
  }

  /// Get notification channel based on notification type
  String _getChannelId(String? notificationType) {
    switch (notificationType) {
      case 'appointment_reminder':
        return 'appointment_reminders';
      case 'appointment_cancellation':
        return 'appointment_alerts';
      case 'view_graph':
        return 'graph_updates';
      case 'slot_available':
      case 'cascaded_slot_available':
        return 'slot_opportunities';
      default:
        return 'general_notifications';
    }
  }

  String _getChannelName(String? notificationType) {
    switch (notificationType) {
      case 'appointment_reminder':
        return 'Appointment Reminders';
      case 'appointment_cancellation':
        return 'Appointment Alerts';
      case 'view_graph':
        return 'Graph Updates';
      case 'slot_available':
      case 'cascaded_slot_available':
        return 'Slot Opportunities';
      default:
        return 'General Notifications';
    }
  }

  /// Show notification with proper error handling and preferences
  Future<void> showNotification(RemoteMessage message) async {
    try {
      // Check if notifications are enabled
      if (!await NotificationPreferences.areNotificationsEnabled()) {
        NotificationLogger.info('Notifications disabled by user preference');
        return;
      }

      // Check if this specific notification type is enabled
      final notificationType = message.data['type'];
      if (notificationType != null &&
          !await NotificationPreferences.shouldShowNotification(
              notificationType)) {
        NotificationLogger.info(
          'Notification type disabled',
          {'type': notificationType},
        );
        return;
      }

      // Ensure local notifications are initialized
      if (!_localNotificationsInitialized) {
        await initLocalNotifications();
      }

      // Get channel based on notification type
      final channelId = _getChannelId(notificationType);
      final channelName = _getChannelName(notificationType);

      // Create notification channel for Android
      if (Platform.isAndroid) {
        final AndroidNotificationChannel channel = AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Notifications for $channelName',
          importance: Importance.high,
          showBadge: true,
        );

        await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      // Get user preferences
      final soundEnabled = await NotificationPreferences.isSoundEnabled();
      final vibrationEnabled =
          await NotificationPreferences.isVibrationEnabled();

      // Create notification actions based on type
      List<AndroidNotificationAction>? actions;
      if (notificationType == 'appointment_reminder') {
        actions = [
          const AndroidNotificationAction(
            'view',
            'View',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'dismiss',
            'Dismiss',
            cancelNotification: true,
          ),
        ];
      } else if (notificationType == 'slot_available' ||
          notificationType == 'cascaded_slot_available') {
        actions = [
          const AndroidNotificationAction(
            'claim',
            'Claim Slot',
            showsUserInterface: true,
          ),
          const AndroidNotificationAction(
            'dismiss',
            'Dismiss',
            cancelNotification: true,
          ),
        ];
      }

      AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifications for $channelName',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        actions: actions,
        styleInformation: const BigTextStyleInformation(''),
      );

      DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: soundEnabled,
      );

      NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      // Create proper JSON payload
      final payload = jsonEncode({
        'type': notificationType ?? 'unknown',
        'data': message.data,
        'messageId': message.messageId,
      });

      final notificationId = message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch;

      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? 'You have a new notification',
        notificationDetails,
        payload: payload,
      );

      NotificationLogger.info(
        'Notification displayed',
        {'type': notificationType, 'id': notificationId},
      );

      // Save to history if user is logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final historyItem =
            NotificationHistoryItem.fromRemoteMessage(message);
        await NotificationHistory.saveNotification(user.uid, historyItem);
      }
    } catch (e, stackTrace) {
      NotificationLogger.error('Error showing notification', e, stackTrace);
    }
  }

  //for ios
  Future forgroundMessage() async {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> handleMessage(RemoteMessage message) async {
    // Show the notification details screen first
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => MessageScreen(message: message),
      ),
    );
    
    // The MessageScreen will handle navigation to appropriate screens via its action buttons
    // But we can also navigate directly based on notification type if needed
    // For now, the MessageScreen shows all details and user can choose to navigate
  }

  /// Initialize notification listeners (call this once at app startup)
  Future<void> setupInteractMessage() async {
    try {
      // Prevent duplicate listener setup
      if (_listenersInitialized) {
        NotificationLogger.warning('Notification listeners already initialized');
        return;
      }

      // Initialize local notifications first
      await initLocalNotifications();

      // 1. Handle notifications when app is TERMINATED (killed) and opened via notification
      RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        NotificationLogger.info('App opened from terminated state via notification');
        // Wait for app to be fully initialized before handling
        Future.delayed(const Duration(seconds: 1), () {
          handleMessage(initialMessage);
        });
      }

      // 2. Handle notifications when app is in BACKGROUND and opened via notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        NotificationLogger.info('App opened from background state via notification');
        handleMessage(message);
      });

      // 3. Handle notifications when app is in FOREGROUND
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        NotificationLogger.info(
          'Foreground message received',
          {
            'title': message.notification?.title,
            'type': message.data['type'],
          },
        );

        // Show local notification for foreground messages
        if (message.notification != null) {
          await showNotification(message);
        }
      });

      _listenersInitialized = true;
      NotificationLogger.info('Notification listeners initialized successfully');
    } catch (e, stackTrace) {
      NotificationLogger.error(
        'Error setting up notification listeners',
        e,
        stackTrace,
      );
    }
  }

  // Version with BuildContext (for backward compatibility)
  Future<void> setupInteractMessageWithContext(BuildContext context) async {
    // Just call the main setup method
    await setupInteractMessage();
  }
}
