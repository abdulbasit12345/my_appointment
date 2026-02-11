import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import 'notification_logger.dart';

class PushNotificationServices {
  /// ⚠️ SECURITY WARNING: This method contains hardcoded credentials.
  /// 
  /// **CRITICAL**: Move credentials to environment variables before production.
  /// See SECURITY_GUIDE.md for instructions.
  /// 
  /// **IMMEDIATE ACTION REQUIRED**:
  /// 1. Rotate service account key in Firebase Console
  /// 2. Use environment variables (see SECURITY_GUIDE.md)
  /// 3. Never commit credentials to version control
  static Future<String> getAccessToken() async {
    try {
      // TODO: Replace hardcoded values with environment variables
      // See SECURITY_GUIDE.md for proper implementation
      final serviceAccountJson = {
      "type": "service_account",
      "project_id": "myappointment-6843e",
      "private_key_id": "12fe85a18b2ba6736fd8d34d90dcdb81cc5b0376",
      "private_key":
          "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDabx4bNsvOEdof\nWFkpTDhg/xFZso5mgYUrw6eTeBzVoJciDYy061O4xla1i+jgB3VaubyVns771N+4\neooDDQoYm1R5w/nXzky1tgNj1eMXdL4fhk8yTai3X/KS0uRmilkbHeulkTPddJmJ\nx5SMolPbdh6p0Cbp0XsjmHjdjtWFWYG+ADunwXJtN0HmdUFYnjtaq1HabTZtZqr8\njssTmt4zBPFrEiBf6KoAk0Bi54kucoyiDdvsQM/9XvPKwv9mBv3kDb7SHMrFIGeR\njIRUhEnZ53CLVAvfNKf57asJvG8Wz0aNFZ39AYIl6NVAg5Fo+Pe2NKEsLNUnuAvz\nsc4OVvZ5AgMBAAECggEAGoyF5r3ewJGn5sZos93JPnTSCYprx2a3pm2V6RUgwBBQ\nPjnSX8z4dI1azZ8PM2eEqn3Hv5G5S5+Af54ZNyy3DO2YM2KP89xls3JHcDN3cgrk\n7tT2vED3IC6fv5u1Wgc3tFWLJikDWkfJP5dL5Vn3gkWVjYM4r5Of+WAXVKp/JkFU\nxHnuKH0O8FPhRBrMwRYl18aAPjc+T+QUs7rGsFTfn5QfNERFLx/vtNCVdhY0Mncd\n9VXLue9DNEfZMMI37Zomo6QCvCvOd28MmNESZHV8h91rrIRLKaOkvD/KCpnYTiEy\nac6UhTnGzCsfQtSmFWo/VkIGTmwoG7WUdzlH1Ao3uQKBgQDyowVmKopO04HpXylW\nhnbwoZ3dlLFgEJxSgkjh7mMcNk6QheL5jv6lZFI5oABfQyUyBPexaq424rsJYRnA\n4x7StF0VyIZFyc1G0y6JGby8coruv6vxroOq1qyNg4gwXAMZBkQOOQZ8CGoyhnY4\nIUx2HyUXiESFeNW19PsX8HWzbQKBgQDmdtuTKFzOznAFFMS/Mkh+Sq10opEHIOMz\nq0DFa3yh2aAQsmwOTDXCDzA5oZoibOgzPtDfjTDspZ85cCfx0X/SruwGN6xipmXh\nOdqwP9AmVw11/JKYh3jITiiZrd3kQqW4/fDGEeg42QamAaTN/T8M1JQTPk1vMwgw\nhxYAK3kbvQKBgCpKjeNb4NWSeh9SLeNd9pdEpD5971i+LHEZMljm8zF0qcb4/zHe\nYbY0QTy4DbiM/Iu2X/H1lT4N0On2mcWMENBLDbqBRB4f6X7BymetK79w+5RXpkGu\n2FZLqrHTzkYXk5amB/CusdmmodQCqdJow2oHTbDHWKInCKD5fVaT3AAVAoGBAJQ8\nm1t6OMfkzPTXuP1qMGrbSdqdvj8hjkJrwsu5KX9JZcWXnh1MM7/Q2SoYofXGq0xa\n+SrxvChbF6FwXKEUKe2wCayuHrmNYjaOafW39gDTOZtMjFaDvNLKQx8mUHVD0Si+\nXiJo3j/CiJ46rHC6ldWA3oXKKzB9WKUuHp6ZV9rZAoGAPPC2CEqwPr5WXu2rHZVu\nJCEnwu1IdOlWdLncTadXReJ71weQ8SG8F3FNXeVsF7XGReouhHrNZlLv3uwK9eeo\nUUeUXtbgb/UF5XtKABCUTsJM1IjR1nlM6NXFKCbwwfcCPZuczb3G8u0Wk7f2X+2p\n8Heb/7UrGJAdURoVwBWpDFI=\n-----END PRIVATE KEY-----\n",
      "client_email":
          "my-appointment-302@myappointment-6843e.iam.gserviceaccount.com",
      "client_id": "117419145450581272229",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url":
          "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url":
          "https://www.googleapis.com/robot/v1/metadata/x509/my-appointment-302%40myappointment-6843e.iam.gserviceaccount.com",
      "universe_domain": "googleapis.com"
    };

    List<String> scope = [
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/firebase.database",
      "https://www.googleapis.com/auth/firebase.messaging",
    ];

      http.Client client = await auth.clientViaServiceAccount(
          auth.ServiceAccountCredentials.fromJson(serviceAccountJson), scope);
      
      // Get the Access token
      auth.AccessCredentials credentials =
          await auth.obtainAccessCredentialsViaServiceAccount(
        auth.ServiceAccountCredentials.fromJson(serviceAccountJson),
        scope,
        client,
      );
      client.close();
      
      NotificationLogger.info('FCM access token obtained successfully');
      return credentials.accessToken.data;
    } catch (e, stackTrace) {
      NotificationLogger.error(
        'Error obtaining FCM access token',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Send notification to user with proper error handling and retry logic
  Future<bool> sendNotificationToUser({
    required String deviceToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String? imageUrl,
    required BuildContext context,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        NotificationLogger.info(
          'Sending notification',
          {
            'attempt': attempt + 1,
            'type': data?['type'],
            'deviceToken': deviceToken.substring(0, 20) + '...',
          },
        );

        final String serverAccessTokenKey = await getAccessToken();
        const String endpointFirebaseCloudMessaging =
            'https://fcm.googleapis.com/v1/projects/myappointment-6843e/messages:send';

        // Construct the notification payload
        final Map<String, dynamic> message = {
          'message': {
            'token': deviceToken,
            'notification': {
              'title': title,
              'body': body,
              if (imageUrl != null) 'image': imageUrl,
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channelId': _getChannelId(data?['type']),
                'sound': 'default',
              },
            },
            'apns': {
              'payload': {
                'aps': {
                  'sound': 'default',
                  'badge': 1,
                },
              },
            },
            'data': {
              'type': data?['type'] ?? 'default',
              ...?data,
            },
          },
        };

        final http.Response response = await http.post(
          Uri.parse(endpointFirebaseCloudMessaging),
          body: jsonEncode(message),
          headers: <String, String>{
            'content-type': 'application/json',
            'authorization': 'Bearer $serverAccessTokenKey',
          },
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('FCM request timeout');
          },
        );

        if (response.statusCode == 200) {
          NotificationLogger.info('FCM notification sent successfully');
          return true;
        } else {
          NotificationLogger.warning(
            'FCM notification failed',
            'Status: ${response.statusCode}, Body: ${response.body}',
          );
          
          // Retry on server errors (5xx)
          if (response.statusCode >= 500 && attempt < maxRetries - 1) {
            attempt++;
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }
          
          return false;
        }
      } catch (e, stackTrace) {
        NotificationLogger.error(
          'Error sending FCM notification',
          e,
          stackTrace,
        );
        
        // Retry on network errors
        if (attempt < maxRetries - 1) {
          attempt++;
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }
        
        return false;
      }
    }
    
    return false;
  }

  /// Get channel ID based on notification type
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
}

/// Exception for timeout errors
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}
