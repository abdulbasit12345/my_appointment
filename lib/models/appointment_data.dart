import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../utils/appointment_status.dart';
import '../utils/date_utils.dart';

/// Robust data model for Appointments collection from Firestore
/// Maps all fields from Firestore and includes computed properties
class AppointmentData {
  final String documentId;
  final String patientID;
  final String name;
  final String phone;
  final String? whatsappNumber; // Optional WhatsApp number (E.164 format)
  final String email;
  final String address;
  final String hospital;
  final String status; // 'active', 'cancelled', 'no response'
  final DateTime date; // Parsed date as DateTime
  final DateTime time; // Parsed time as DateTime (time only, date is 2000-01-01)
  
  // New fields for dashboard redesign
  final String? userResponse; // 'Confirmed', 'Cancelled', or null
  final String reallocationStatus; // 'Original', 'Reallocated', 'Not Reallocated'
  final String? originalDate; // Original date before reallocation (dd-MM-yyyy)
  final String? originalTime; // Original time before reallocation
  final int? daysMoved; // Number of days moved earlier (calculated)
  final String? newUserName; // Name of patient who took this slot (if reallocated)
  final String? originalPatientName; // Original patient name (if slot was taken from someone)
  final bool isPriority; // Whether patient is on priority list for earlier slots
  final DateTime? priorityJoinedAt; // When patient joined priority list

  // Set when the stored date/time couldn't be parsed. [date]/[time] then hold
  // a fallback value so sorting and filtering keep working, and the display
  // getters show a warning with the raw value instead of a believable date.
  final bool hasInvalidDate;
  final bool hasInvalidTime;
  final String? rawDate;
  final String? rawTime;

  bool get hasInvalidDateTime => hasInvalidDate || hasInvalidTime;

  /// Exact start time (UK clinic time) kept in sync from [date]/[time] by the
  /// onAppointmentWritten Cloud Function. Null until the function has
  /// processed the document; [date]/[time] remain the source of truth.
  final DateTime? appointmentAt;

  /// Meaning of [status], whatever spelling is stored.
  AppointmentStatusKind get statusKind => AppointmentStatus.kindOf(status);
  
  /// Computed property: Combined date and time as DateTime
  DateTime get appointmentDateTime => DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  
  /// Computed property: Formatted string "DD Month YYYY @ HH:MM AM/PM" (UK format)
  String get dateTimeString {
    final timeFormat = DateFormat('hh:mm a');
    final timeStr = timeFormat.format(appointmentDateTime);
    return '$ukFormattedDate @ $timeStr';
  }
  
  /// UK format date string: "12 December 2025"
  /// Carries a warning when the stored date or time is invalid.
  String get ukFormattedDate {
    if (hasInvalidDate) return '⚠ Invalid date "${rawDate ?? ''}"';
    final dateFormat = DateFormat('d MMMM yyyy');
    final dateStr = dateFormat.format(date);
    if (hasInvalidTime) return '$dateStr (⚠ invalid time "${rawTime ?? ''}")';
    return dateStr;
  }
  
  /// Formatted date string (dd-MM-yyyy format from Firestore)
  String get formattedDate => Date_Utils.formatDate(date);
  
  /// Formatted time string (hh:mm a format)
  String get formattedTime => DateFormat('hh:mm a').format(appointmentDateTime);
  
  /// Display text for user response
  String get userResponseDisplay {
    if (userResponse == null) return '-';
    return userResponse == 'Confirmed' ? 'Confirmed' : 'Cancelled';
  }
  
  /// Display text for reallocation status
  String get reallocationStatusDisplay {
    switch (reallocationStatus) {
      case 'Original':
        return 'Original';
      case 'Reallocated':
        return 'Reallocated';
      case 'Not Reallocated':
        return 'Not Reallocated';
      default:
        return 'Original';
    }
  }
  
  /// Display text for new user name with date range
  /// Format: "Name (from Date/time to Date/time)"
  String get newUserNameDisplay {
    if (newUserName == null) return '-';
    if (originalDate == null || originalTime == null) {
      return newUserName ?? '-';
    }
    // Format: "Name (from 12-12-2025 10:00 to 15-12-2025 14:00)"
    final originalDateFormatted = originalDate ?? '';
    final originalTimeFormatted = originalTime ?? '';
    final currentDateFormatted = formattedDate;
    final currentTimeFormatted = formattedTime;
    return '$newUserName (from $originalDateFormatted $originalTimeFormatted to $currentDateFormatted $currentTimeFormatted)';
  }
  
  /// Compact display for new user name (single line, for tables)
  String get newUserNameDisplayCompact {
    if (newUserName == null) return '-';
    if (originalDate == null || originalTime == null) {
      return newUserName ?? '-';
    }
    // Format: "Name (from 12-12-2025 10:00 to 15-12-2025 14:00)"
    return '$newUserName (from $originalDate $originalTime to $formattedDate $formattedTime)';
  }
  
  /// Display text for days moved
  String get daysMovedDisplay {
    if (daysMoved == null || daysMoved == 0) return '-';
    return '$daysMoved ${daysMoved == 1 ? 'day' : 'days'} earlier';
  }

  AppointmentData({
    required this.documentId,
    required this.patientID,
    required this.name,
    required this.phone,
    this.whatsappNumber,
    required this.email,
    required this.address,
    required this.hospital,
    required this.status,
    required this.date,
    required this.time,
    this.userResponse,
    this.reallocationStatus = 'Original',
    this.originalDate,
    this.originalTime,
    this.daysMoved,
    this.newUserName,
    this.originalPatientName,
    this.isPriority = false,
    this.priorityJoinedAt,
    this.hasInvalidDate = false,
    this.hasInvalidTime = false,
    this.rawDate,
    this.rawTime,
    this.appointmentAt,
  });

  /// Factory constructor to create AppointmentData from Firestore DocumentSnapshot
  factory AppointmentData.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Extract date string and parse it (strictly, so '32-01-2025' isn't
    // silently rolled over to 1 February)
    final rawDateValue = data['date'];
    final dateString = rawDateValue is String ? rawDateValue : '';
    DateTime? parsedDate = Date_Utils.tryParseDateStrict(dateString);
    final hasInvalidDate = parsedDate == null;
    if (parsedDate == null) {
      // Keep the record visible (today) but flagged
      parsedDate = DateTime.now();
      debugPrint('AppointmentData ${doc.id}: invalid date "$rawDateValue"');
    }
    
    // Extract time string and parse it
    // Handles 24-hour (HH:mm) and 12-hour (hh:mm a) formats, including PM
    final rawTimeValue = data['time'];
    final timeString = rawTimeValue is String ? rawTimeValue : '';
    DateTime? parsedTime = Date_Utils.tryParseTimeFlexible(timeString);
    final hasInvalidTime = parsedTime == null;
    if (parsedTime == null) {
      parsedTime = DateTime(2000, 1, 1, DateTime.now().hour, DateTime.now().minute);
      debugPrint('AppointmentData ${doc.id}: invalid time "$rawTimeValue"');
    }
    
    return AppointmentData(
      documentId: doc.id,
      patientID: data['patientID'] as String? ?? '',
      name: data['name'] as String? ?? 'Unknown',
      phone: data['phone'] as String? ?? '',
      whatsappNumber: data['whatsappNumber'] as String?,
      email: data['email'] as String? ?? '',
      address: data['address'] as String? ?? '',
      hospital: data['hospital'] as String? ?? '',
      status: data['status'] as String? ?? 'active',
      date: parsedDate,
      time: parsedTime,
      userResponse: data['userResponse'] as String?,
      reallocationStatus: data['reallocationStatus'] as String? ?? 'Original',
      originalDate: data['originalDate'] as String?,
      originalTime: data['originalTime'] as String?,
      daysMoved: data['daysMoved'] as int?,
      newUserName: data['newUserName'] as String?,
      originalPatientName: data['originalPatientName'] as String?,
      isPriority: data['isPriority'] as bool? ?? false,
      priorityJoinedAt: (data['priorityJoinedAt'] as Timestamp?)?.toDate(),
      hasInvalidDate: hasInvalidDate,
      hasInvalidTime: hasInvalidTime,
      rawDate: rawDateValue?.toString(),
      rawTime: rawTimeValue?.toString(),
      appointmentAt: (data['appointmentAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Convert to Map for Firestore (if needed for updates)
  Map<String, dynamic> toFirestore() {
    return {
      'patientID': patientID,
      'name': name,
      'phone': phone,
      'whatsappNumber': whatsappNumber,
      'email': email,
      'address': address,
      'hospital': hospital,
      'status': status,
      'date': Date_Utils.formatDate(date),
      'time': formattedTime,
      'userResponse': userResponse,
      'reallocationStatus': reallocationStatus,
      'originalDate': originalDate,
      'originalTime': originalTime,
      'daysMoved': daysMoved,
      'newUserName': newUserName,
      'originalPatientName': originalPatientName,
      'isPriority': isPriority,
      'priorityJoinedAt': priorityJoinedAt != null ? Timestamp.fromDate(priorityJoinedAt!) : null,
    };
  }

  /// Create a copy with updated fields
  AppointmentData copyWith({
    String? documentId,
    String? patientID,
    String? name,
    String? phone,
    String? whatsappNumber,
    String? email,
    String? address,
    String? hospital,
    String? status,
    DateTime? date,
    DateTime? time,
    String? userResponse,
    String? reallocationStatus,
    String? originalDate,
    String? originalTime,
    int? daysMoved,
    String? newUserName,
    String? originalPatientName,
    bool? isPriority,
    DateTime? priorityJoinedAt,
  }) {
    return AppointmentData(
      documentId: documentId ?? this.documentId,
      patientID: patientID ?? this.patientID,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      whatsappNumber: whatsappNumber ?? this.whatsappNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      hospital: hospital ?? this.hospital,
      status: status ?? this.status,
      date: date ?? this.date,
      time: time ?? this.time,
      userResponse: userResponse ?? this.userResponse,
      reallocationStatus: reallocationStatus ?? this.reallocationStatus,
      originalDate: originalDate ?? this.originalDate,
      originalTime: originalTime ?? this.originalTime,
      daysMoved: daysMoved ?? this.daysMoved,
      newUserName: newUserName ?? this.newUserName,
      originalPatientName: originalPatientName ?? this.originalPatientName,
      isPriority: isPriority ?? this.isPriority,
      priorityJoinedAt: priorityJoinedAt ?? this.priorityJoinedAt,
      // A copy with a new date/time is valid again
      hasInvalidDate: date != null ? false : hasInvalidDate,
      hasInvalidTime: time != null ? false : hasInvalidTime,
      rawDate: rawDate,
      rawTime: rawTime,
      appointmentAt: appointmentAt,
    );
  }
}

