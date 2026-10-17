/// What a stored status value means, whatever its spelling.
enum AppointmentStatusKind {
  active,
  confirmed,
  priority,
  reminderSent,
  noResponse,
  cancelled,
  available,
  offerSent,
  unknown;

  /// Patient still holds the slot.
  bool get isBooked =>
      this == active ||
      this == confirmed ||
      this == priority ||
      this == reminderSent ||
      this == noResponse;
}

/// Status values stored on documents in the `Appointments` collection.
///
/// The mobile app, the web dashboard and the Cloud Functions have written
/// different spellings over time ('active', 'CONFIRMED',
/// 'reminder_sent_awaiting_reply', ...). Existing documents keep their
/// values, so reads should use these lists/helpers instead of comparing
/// against a single literal.
class AppointmentStatus {
  static const String active = 'active';
  static const String cancelled = 'cancelled';
  static const String confirmed = 'CONFIRMED';
  static const String priority = 'Confirmed_Priority';
  static const String reminderSent = 'reminder_sent_awaiting_reply';
  static const String noResponse = 'no response';

  /// Every stored value meaning the patient still holds their slot.
  /// Usable directly in a Firestore `whereIn` (limit 30 values).
  static const List<String> bookedValues = [
    'active',
    'ACTIVE',
    'BOOKED',
    'CONFIRMED',
    'Confirmed_Priority',
    'reminder_sent_awaiting_reply',
    'REMINDER_SENT_AWAITING_REPLY',
    'awaitingReply',
    'no response',
  ];

  /// Every stored value meaning the patient cancelled.
  static const List<String> cancelledValues = [
    'cancelled',
    'CANCELLED',
    'Cancelled',
    'canceled',
  ];

  static final Set<String> _bookedLower =
      bookedValues.map((s) => s.toLowerCase()).toSet();
  static final Set<String> _cancelledLower =
      cancelledValues.map((s) => s.toLowerCase()).toSet();

  /// Maps any stored spelling to its meaning.
  static AppointmentStatusKind kindOf(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'active':
      case 'booked':
        return AppointmentStatusKind.active;
      case 'confirmed':
        return AppointmentStatusKind.confirmed;
      case 'confirmed_priority':
        return AppointmentStatusKind.priority;
      case 'reminder_sent_awaiting_reply':
      case 'awaitingreply':
        return AppointmentStatusKind.reminderSent;
      case 'no response':
        return AppointmentStatusKind.noResponse;
      case 'cancelled':
      case 'canceled':
        return AppointmentStatusKind.cancelled;
      case 'available':
        return AppointmentStatusKind.available;
      case 'on_hold_offer_sent':
        return AppointmentStatusKind.offerSent;
      default:
        return AppointmentStatusKind.unknown;
    }
  }

  static bool isBooked(String? status) =>
      status != null && _bookedLower.contains(status.trim().toLowerCase());

  static bool isCancelled(String? status) =>
      status != null && _cancelledLower.contains(status.trim().toLowerCase());
}
