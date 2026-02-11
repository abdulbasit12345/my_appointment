import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service for streaming dashboard metrics from Firestore
/// Mock collection: DashboardMetrics
class DashboardMetricsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream metrics document from DashboardMetrics collection
  /// Document ID: 'metrics' (single document)
  Stream<DocumentSnapshot> getMetricsStream() {
    return _firestore
        .collection('DashboardMetrics')
        .doc('metrics')
        .snapshots();
  }

  /// Get current metrics (one-time fetch)
  Future<Map<String, dynamic>?> getCurrentMetrics() async {
    try {
      final doc = await _firestore
          .collection('DashboardMetrics')
          .doc('metrics')
          .get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching dashboard metrics: $e');
      }
      return null;
    }
  }

  /// Parse metrics from Firestore document
  DashboardMetrics? parseMetrics(DocumentSnapshot doc) {
    if (!doc.exists) return null;
    
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;

      return DashboardMetrics(
        totalCancellations: data['totalCancellations'] as int? ?? 0,
        totalReallocations: data['totalReallocations'] as int? ?? 0,
        totalDaysMoved: data['totalDaysMoved'] as int? ?? 0,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing dashboard metrics: $e');
      }
      return null;
    }
  }

  /// Stream activity log entries from DashboardMetrics collection
  /// Subcollection: 'activityLog'
  /// 
  /// [limit] - Maximum number of entries to fetch (default: 10)
  /// [typeFilter] - Optional filter by activity type (null = all types)
  Stream<QuerySnapshot> getActivityLogStream({
    int limit = 10,
    String? typeFilter,
  }) {
    Query query = _firestore
        .collection('DashboardMetrics')
        .doc('metrics')
        .collection('activityLog');

    // Apply type filter if provided (must come before orderBy)
    if (typeFilter != null && typeFilter.isNotEmpty) {
      query = query.where('type', isEqualTo: typeFilter);
    }

    // Order by timestamp descending (must come after where clauses)
    query = query.orderBy('timestamp', descending: true);

    return query.limit(limit).snapshots();
  }
}

/// Data model for dashboard metrics
class DashboardMetrics {
  final int totalCancellations;
  final int totalReallocations;
  final int totalDaysMoved;

  DashboardMetrics({
    required this.totalCancellations,
    required this.totalReallocations,
    required this.totalDaysMoved,
  });
}

/// Data model for activity log entry
class ActivityLogEntry {
  final String id;
  final String message; // e.g., "P3 CXL (Day 3) -> P5 CLAIMED (Day 3)"
  final DateTime timestamp;
  final String? type; // 'cancellation', 'claim', 'reallocation'

  ActivityLogEntry({
    required this.id,
    required this.message,
    required this.timestamp,
    this.type,
  });

  factory ActivityLogEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ActivityLogEntry(
      id: doc.id,
      message: data['message'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: data['type'] as String?,
    );
  }

  /// Format timestamp as relative time (e.g., "2 hours ago")
  String get formattedTimestamp {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
}

