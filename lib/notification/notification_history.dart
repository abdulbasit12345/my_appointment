import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Represents a stored notification in history
class NotificationHistoryItem {
  final String id;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final bool read;

  NotificationHistoryItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.timestamp,
    this.read = false,
  });

  factory NotificationHistoryItem.fromRemoteMessage(RemoteMessage message) {
    return NotificationHistoryItem(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: message.notification?.title ?? 'Notification',
      body: message.notification?.body ?? '',
      type: message.data['type'] ?? 'unknown',
      data: message.data,
      timestamp: message.sentTime ?? DateTime.now(),
      read: false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'read': read,
    };
  }

  factory NotificationHistoryItem.fromMap(Map<String, dynamic> map) {
    return NotificationHistoryItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: map['type'] ?? 'unknown',
      data: Map<String, dynamic>.from(map['data'] ?? {}),
      timestamp: DateTime.parse(map['timestamp']),
      read: map['read'] ?? false,
    );
  }
}

/// Manages notification history
class NotificationHistory {
  static const String _collectionName = 'NotificationHistory';

  /// Save a notification to history
  static Future<void> saveNotification(
    String userId,
    NotificationHistoryItem notification,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .collection('notifications')
          .doc(notification.id)
          .set(notification.toMap());
    } catch (e) {
      // Log error but don't fail notification delivery
      print('Error saving notification to history: $e');
    }
  }

  /// Get notification history for a user
  static Future<List<NotificationHistoryItem>> getHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => NotificationHistoryItem.fromMap(doc.data()))
          .toList();
    } catch (e) {
      print('Error getting notification history: $e');
      return [];
    }
  }

  /// Mark notification as read
  static Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  /// Delete notification from history
  static Future<void> deleteNotification(
    String userId,
    String notificationId,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  /// Get unread count
  static Future<int> getUnreadCount(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(userId)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }
}

