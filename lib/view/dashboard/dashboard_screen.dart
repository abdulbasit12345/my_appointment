import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Web-specific imports for native file picker
import 'dart:html' as html;

import '../../models/appointment_data.dart';
import '../../notification/notification_services.dart';
import '../../notification/push_notification_services.dart';
import '../../services/dashboard_metrics_service.dart';
import '../../utils/date_utils.dart';
import 'edit_appointment_dialog.dart';

/// Master Dashboard Screen for Flutter Web
/// Two-column responsive layout with real-time Firestore data streaming
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardMetricsService _metricsService = DashboardMetricsService();
  final PushNotificationServices _pushNotificationServices =
      PushNotificationServices();
  final NotificationServices _notificationServices = NotificationServices();

  // Phase 2: Activity log filtering and pagination state
  String? _selectedLogType; // null = all types
  int _activityLogLimit = 10;

  // Search and filter state
  String _searchCategory = 'Patient Name';
  final TextEditingController _searchController = TextEditingController();

  // Scroll controllers for table scrolling
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Stream of appointments from today to next 30 days
  /// Note: We fetch all appointments with status filter, then filter by date in memory
  /// to avoid Firestore's disjunction limit (max 30 disjunctions)
  /// Includes 'AVAILABLE' status to show cancelled appointments that are set to AVAILABLE for reallocation
  Stream<QuerySnapshot> _getTodayAppointments() {
    return FirebaseFirestore.instance
        .collection('Appointments')
        .where('status', whereIn: [
      'active',
      'cancelled',
      'AVAILABLE', // Include AVAILABLE status (cancelled appointments set to AVAILABLE for reallocation)
      'ON_HOLD_OFFER_SENT', // Include ON_HOLD_OFFER_SENT status (slot offer sent, awaiting reply)
      'no response',
      'REMINDER_SENT_AWAITING_REPLY', // Include reminder sent status
      'CONFIRMED', // Include confirmed status
    ]).snapshots();
  }

  /// Filter appointments to only include those within the next 30 days
  /// Also includes cancelled appointments from the past 7 days to ensure they remain visible
  List<AppointmentData> _filterAppointmentsByDateRange(
      List<AppointmentData> appointments) {
    final now = DateTime.now();
    final startDate =
        DateTime(now.year, now.month, now.day); // Today at 00:00:00
    final endDate = startDate
        .add(const Duration(days: 30)); // 30 days from today (inclusive)

    // Include cancelled appointments from the past 7 days
    final cancelledStartDate = startDate.subtract(const Duration(days: 7));

    print('Filtering appointments: Start Date: $startDate, End Date: $endDate');

    return appointments.where((appointment) {
      final appointmentDate = appointment.date;
      // Normalize appointment date to start of day for comparison
      final appointmentDateOnly = DateTime(
        appointmentDate.year,
        appointmentDate.month,
        appointmentDate.day,
      );

      // Check if appointment is cancelled (by status or userResponse)
      final isCancelled = appointment.status.toLowerCase() == 'cancelled' ||
          appointment.status == 'AVAILABLE' ||
          appointment.userResponse == 'Cancelled';

      // If cancelled, show if within past 7 days or future 30 days
      if (isCancelled) {
        final isInRange = !appointmentDateOnly.isBefore(cancelledStartDate) &&
            !appointmentDateOnly.isAfter(endDate);
        if (!isInRange) {
          print('Filtered out cancelled appointment: ${appointment.name}, Date: $appointmentDateOnly (outside range)');
        }
        return isInRange;
      }

      // For non-cancelled appointments, only show future appointments (today to 30 days)
      // IMPORTANT: Include today's appointments (use isBefore with startDate, not isAfter)
      final isInRange = (appointmentDateOnly.isAtSameMomentAs(startDate) || 
                         appointmentDateOnly.isAfter(startDate)) &&
                         !appointmentDateOnly.isAfter(endDate);
      
      if (!isInRange) {
        print('Filtered out appointment: ${appointment.name}, Date: $appointmentDateOnly, Status: ${appointment.status} (before start or after end)');
      }
      
      return isInRange;
    }).toList();
  }

  /// Build search bar widget
  Widget _buildSearchBar(BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 12 : 16,
        vertical: isSmallScreen ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Search Category Dropdown
          Container(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: DropdownButton<String>(
              value: _searchCategory,
              isDense: true,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[700]),
              style: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
                color: const Color(0xFF333333),
              ),
              items: ['Patient Name', 'Phone', 'Date'].map((String category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _searchCategory = newValue;
                  });
                }
              },
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          // Search TextField
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}), // Real-time update
              decoration: InputDecoration(
                hintText: 'Search by $_searchCategory...',
                hintStyle: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  color: Colors.grey[500],
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF666666)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF666666)),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 12 : 14,
                ),
              ),
              style: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
                color: const Color(0xFF333333),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Apply search filter to appointments list
  List<AppointmentData> _applySearchFilter(
    List<AppointmentData> appointments,
    String category,
    String query,
  ) {
    if (query.isEmpty) {
      return appointments;
    }

    final lowerQuery = query.toLowerCase().trim();

    switch (category) {
      case 'Patient Name':
        return appointments.where((apt) {
          return apt.name.toLowerCase().contains(lowerQuery);
        }).toList();

      case 'Phone':
        return appointments.where((apt) {
          // Remove all non-digit characters for comparison
          final phoneDigits = apt.phone.replaceAll(RegExp(r'[^\d]'), '');
          final queryDigits = lowerQuery.replaceAll(RegExp(r'[^\d]'), '');
          // Match start, middle, or end of phone number
          return phoneDigits.contains(queryDigits) ||
              apt.phone.toLowerCase().contains(lowerQuery);
        }).toList();

      case 'Date':
        return appointments.where((apt) {
          // Match date as shown in table (e.g., "29 January 2026")
          final dateStr = apt.ukFormattedDate.toLowerCase();
          final dateStrShort = Date_Utils.formatDate(apt.date).toLowerCase();
          return dateStr.contains(lowerQuery) || dateStrShort.contains(lowerQuery);
        }).toList();

      default:
        return appointments;
    }
  }

  /// Format phone number to E.164 format
  /// Handles various formats and preserves existing E.164 format
  /// Convert scientific notation to regular number string
  /// Handles Excel's scientific notation like "9.27E+11" -> "927000000000"
  String _convertScientificNotation(String value) {
    if (value.isEmpty) return value;
    
    // Check if it's in scientific notation (contains 'E' or 'e' followed by + or -)
    if (RegExp(r'[Ee][\+\-]?\d+').hasMatch(value)) {
      try {
        // Try to parse as double first (handles scientific notation)
        final numValue = double.parse(value);
        // Convert to integer string (remove decimal if any)
        return numValue.toInt().toString();
      } catch (e) {
        print('⚠️ Warning: Could not parse scientific notation: $value');
        return value; // Return original if parsing fails
      }
    }
    return value; // Not scientific notation, return as is
  }

  String _formatPhoneToE164(String phone) {
    if (phone.isEmpty) return phone;

    // First, convert scientific notation if present (Excel format)
    phone = _convertScientificNotation(phone);

    // Remove all non-digit characters except +
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '').trim();

    // If already in E.164 format (starts with +), return as is
    if (cleaned.startsWith('+')) {
      return cleaned;
    }

    // If starts with 00 (international format), replace with +
    if (cleaned.startsWith('00')) {
      return '+' + cleaned.substring(2);
    }

    // Handle Pakistan mobile numbers (country code 92)
    // Pakistan mobile numbers: +92 3XX XXXXXXX (11 digits total)
    // Local format: 03XX XXXXXXX (11 digits)
    
    // If starts with 0 and is 11 digits, likely Pakistan mobile (03XX format)
    if (cleaned.startsWith('0') && cleaned.length == 11) {
      // Check if it's a Pakistan mobile (starts with 03)
      if (cleaned.startsWith('03')) {
        // Pakistan mobile: 03XX XXXXXXX -> +92 3XX XXXXXXX
        return '+92' + cleaned.substring(1); // Remove leading 0, add +92
      }
    }
    
    // If starts with 92 and is 12 digits (92 + 10 digits), check if it's mobile
    if (cleaned.startsWith('92') && cleaned.length == 12) {
      // Check if it starts with 923 (Pakistan mobile prefix)
      if (cleaned.startsWith('923')) {
        return '+' + cleaned; // Valid Pakistan mobile
      }
      // Otherwise might be landline, but return it anyway (Twilio will reject if landline)
      return '+' + cleaned;
    }
    
    // If number starts with 9 and is 11 digits, check if Pakistan mobile
    if (cleaned.startsWith('9') && cleaned.length == 11) {
      // If starts with 93, it's likely Pakistan mobile missing country code
      if (cleaned.startsWith('93')) {
        return '+92' + cleaned; // Add country code
      }
    }

    // If starts with 0 and longer than 11, might be UK or other country
    if (cleaned.startsWith('0') && cleaned.length > 11) {
      // UK format: 0XXXXXXXXX -> +44XXXXXXXXX
      return '+44' + cleaned.substring(1);
    }

    // If 10 digits, assume US number
    if (cleaned.length == 10) {
      return '+1' + cleaned;
    }

    // If 11 digits starting with 1, assume US
    if (cleaned.length == 11 && cleaned.startsWith('1')) {
      return '+' + cleaned;
    }

    // For 12-digit numbers starting with 9, might be Pakistan (but could be landline)
    if (cleaned.length == 12 && cleaned.startsWith('9')) {
      // Check if it starts with 923 (mobile) or 92 (could be landline)
      if (cleaned.startsWith('923')) {
        return '+92' + cleaned.substring(2); // Already has country code, just add +
      }
      return '+92' + cleaned; // Add country code, Twilio will validate
    }

    // If we can't determine, try to return with + prefix if it looks like a valid number
    if (cleaned.length >= 10 && cleaned.length <= 15 && !cleaned.startsWith('0')) {
      // Assume it might be a valid international number missing the +
      return '+' + cleaned;
    }

    // If we can't determine, try to add + prefix if it looks like a valid international number
    // This is more aggressive for CSV imports to ensure Twilio-acceptable format
    if (cleaned.length >= 10 && cleaned.length <= 15) {
      // For numbers that look valid but don't match specific patterns, add + prefix
      // This ensures CSV-imported numbers are in E.164 format
      print('Info: Adding + prefix to phone number: $phone -> +$cleaned');
      return '+' + cleaned;
    }

    // If we still can't determine, return original (might already be in correct format)
    // Log a warning in production
    print('Warning: Could not normalize phone number: $phone (cleaned: $cleaned, length: ${cleaned.length})');
    // Try to add + anyway if it doesn't have one and looks numeric
    if (!phone.startsWith('+') && cleaned.isNotEmpty) {
      return '+' + cleaned;
    }
    return phone; // Return original as last resort
  }

  /// Get reminder button text based on appointment status
  String _getReminderButtonText(AppointmentData appointment) {
    // Check if reminder was sent and awaiting reply (case-insensitive)
    final status = appointment.status.toLowerCase();
    if (status == 'reminder_sent_awaiting_reply') {
      return 'Reminder Sent';
    }

    // Check if user has responded (confirmed or cancelled)
    // If userResponse exists, it means user already responded to a previous reminder
    if (appointment.userResponse != null &&
        appointment.userResponse!.isNotEmpty) {
      return 'Send Reminder';
    }

    // Check if status is CONFIRMED (user confirmed after reminder)
    if (status == 'confirmed') {
      return 'Send Reminder';
    }

    // Default state - no reminder sent yet
    return 'Remind';
  }

  /// Get reminder button icon based on appointment status
  IconData _getReminderButtonIcon(AppointmentData appointment) {
    final status = appointment.status.toLowerCase();
    if (status == 'reminder_sent_awaiting_reply') {
      return Icons.check_circle;
    }
    return Icons.send;
  }

  /// Get reminder button color based on appointment status
  Color _getReminderButtonColor(AppointmentData appointment) {
    final status = appointment.status.toLowerCase();
    if (status == 'reminder_sent_awaiting_reply') {
      return Colors.green; // Green when reminder sent
    }
    return const Color(0xFF1976D2); // Blue for default/active state
  }

  /// Check if reminder button should be enabled
  bool _isReminderButtonEnabled(AppointmentData appointment) {
    final status = appointment.status.toLowerCase();
    // Disable if reminder was just sent (waiting for reply)
    // Button will be enabled again once user responds (status changes or userResponse is set)
    if (status == 'reminder_sent_awaiting_reply') {
      return false; // Disabled until user responds
    }
    return true; // Enabled for sending new reminder
  }

  /// Show Quick Actions Menu (SMS Templates)
  /// Uses button's BuildContext to get the exact button position
  void _showQuickActionsMenu(
    BuildContext buttonContext,
    BuildContext overlayContext,
    AppointmentData appointment,
    BoxConstraints constraints,
  ) {
    // Get the RenderBox of the button using its context
    final RenderBox? buttonBox = buttonContext.findRenderObject() as RenderBox?;
    if (buttonBox == null) {
      print('Error: Could not find button RenderBox');
      return;
    }

    // Get screen size from MediaQuery
    final MediaQueryData mediaQuery = MediaQuery.of(overlayContext);
    final Size screenSize = mediaQuery.size;

    // Calculate button's global position (relative to screen)
    final Offset buttonGlobalPosition = buttonBox.localToGlobal(Offset.zero);
    final Size buttonSize = buttonBox.size;

    // Position menu directly below button with small gap
    const double menuGap = 4.0;
    final double menuTop = buttonGlobalPosition.dy + buttonSize.height + menuGap;
    final double menuLeft = buttonGlobalPosition.dx;
    
    // Calculate right and bottom for RelativeRect (distances from edges)
    final double menuRight = screenSize.width - menuLeft;
    final double menuBottom = screenSize.height - menuTop;

    showMenu<String>(
      context: overlayContext,
      position: RelativeRect.fromLTRB(menuLeft, menuTop, menuRight, menuBottom),
      items: [
        const PopupMenuItem<String>(
          value: 'offer_early_slot',
          child: Row(
            children: [
              Icon(Icons.schedule, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('Offer Early Slot'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'confirm_attendance',
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Colors.green),
              SizedBox(width: 8),
              Text('Confirm Attendance'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'late_warning',
          child: Row(
            children: [
              Icon(Icons.warning, size: 18, color: Colors.orange),
              SizedBox(width: 8),
              Text('Late Warning'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _sendQuickActionSMS(context, appointment, value);
      }
    });
  }

  /// Send SMS for quick action template
  Future<void> _sendQuickActionSMS(
    BuildContext context,
    AppointmentData appointment,
    String actionType,
  ) async {
    try {
      // Format phone number to E.164 format
      final cleanedPhone = _formatPhoneToE164(appointment.phone);
      print('Quick Action: Original phone: ${appointment.phone}, Formatted: $cleanedPhone');

      // Get template message based on action type
      String templateName;
      String message;

      switch (actionType) {
        case 'offer_early_slot':
          templateName = 'Offer Early Slot';
          // Get current time for the offer
          final now = DateTime.now();
          final offerTime = DateFormat('hh:mm a').format(now.add(const Duration(hours: 1)));
          message = 'Good news! We have an earlier slot today at $offerTime. Reply 1 to claim.';
          break;
        case 'confirm_attendance':
          templateName = 'Confirm Attendance';
          message = 'Please confirm your ${appointment.formattedTime} appointment by replying 1.';
          break;
        case 'late_warning':
          templateName = 'Late Warning';
          message = 'Hi, we noticed you\'re a bit late. Are you still coming?';
          break;
        default:
          return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sending $templateName...'),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // Send SMS via Cloud Function
      // Try sendCustomSms first (for custom messages), then fallback to sendSmsReminder
      bool smsSent = false;
      String errorMessage = '';
      
      try {
        // First try: Use sendCustomSms if available (for custom messages)
        try {
          final result = await FirebaseFunctions.instance
              .httpsCallable('sendCustomSms')
              .call({
            'phone': cleanedPhone,
            'message': message,
          });

          if (result.data != null) {
            if (result.data['success'] == true) {
              smsSent = true;
              print('Custom SMS sent successfully via sendCustomSms');
            } else {
              errorMessage = result.data['message'] ?? result.data['error'] ?? 'SMS sending failed';
              print('sendCustomSms failed: $errorMessage');
              throw Exception(errorMessage); // Throw to trigger fallback
            }
          } else {
            throw Exception('No response from sendCustomSms');
          }
        } catch (e) {
          // Fallback: Try sendSmsReminder (standard reminder function)
          print('sendCustomSms not available or failed, trying sendSmsReminder: $e');
          try {
            final result = await FirebaseFunctions.instance
                .httpsCallable('sendSmsReminder')
                .call({
              'patientPhone': cleanedPhone,
              'slotStatus': appointment.status,
              'patientId': appointment.patientID,
              'appointmentDate': appointment.formattedDate,
              'appointmentTime': appointment.formattedTime,
            });

            if (result.data != null && result.data['success'] == true) {
              smsSent = true;
              errorMessage = ''; // Clear error since fallback worked
              print('Fallback SMS sent successfully (using default reminder message)');
              // Note: This will send the standard reminder message, not the custom one
            } else {
              errorMessage = result.data?['message'] ?? result.data?['error'] ?? 'SMS sending failed';
              print('sendSmsReminder also failed: $errorMessage');
            }
          } catch (e2) {
            errorMessage = 'SMS service error: ${e2.toString()}';
            print('Both SMS functions failed: $e2');
          }
        }
      } catch (e) {
        errorMessage = 'Unexpected error: ${e.toString()}';
        print('Unexpected error in SMS sending: $e');
      }

      // Log to activity log
      await _logManualAdminAction(
        appointment.name,
        templateName,
        message,
      );

      // Show success/error message
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Check if error is about landline
        bool isLandlineError = errorMessage.toLowerCase().contains('landline');
        String displayMessage;
        
        if (smsSent) {
          displayMessage = 'Manual $templateName sent to ${appointment.name}.';
        } else if (isLandlineError) {
          displayMessage = 'Cannot send SMS: ${appointment.phone} appears to be a landline number. SMS can only be sent to mobile numbers.';
        } else {
          displayMessage = 'Failed to send $templateName to ${appointment.name}.${errorMessage.isNotEmpty ? '\nError: ${errorMessage.length > 80 ? errorMessage.substring(0, 80) + "..." : errorMessage}' : ''}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMessage),
            backgroundColor: smsSent ? Colors.green : Colors.red,
            duration: Duration(seconds: smsSent ? 3 : (isLandlineError ? 6 : 5)),
            action: isLandlineError ? SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ) : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending SMS: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error in _sendQuickActionSMS: $e');
    }
  }

  /// Log manual admin action to activity log
  Future<void> _logManualAdminAction(
    String patientName,
    String templateName,
    String message,
  ) async {
    try {
      final now = DateTime.now();
      final timeStr = DateFormat('hh:mm a').format(now);

      await FirebaseFirestore.instance
          .collection('DashboardMetrics')
          .doc('metrics')
          .collection('activityLog')
          .add({
        'message': '$timeStr: Manual Admin Action - $templateName sent to $patientName',
        'timestamp': Timestamp.now(),
        'type': 'maintenance',
      });
    } catch (e) {
      print('Error logging manual admin action: $e');
    }
  }

  /// Send reminder via notification and SMS
  Future<void> _triggerReminder(
      String patientId,
      String phone,
      String patientName,
      String appointmentDate,
      String appointmentTime) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending reminder...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Format phone number to E.164 format for SMS
      final cleanedPhone = _formatPhoneToE164(phone);
      print('Reminder: Original phone: $phone, Formatted: $cleanedPhone');

      // Get current appointment status from Firestore
      String currentStatus = 'active';
      try {
        final appointmentSnapshot = await FirebaseFirestore.instance
            .collection('Appointments')
            .where('patientID', isEqualTo: patientId)
            .where('date', isEqualTo: appointmentDate)
            .limit(1)
            .get();

        if (appointmentSnapshot.docs.isNotEmpty) {
          currentStatus =
              appointmentSnapshot.docs.first.data()['status'] ?? 'active';
        }
      } catch (e) {
        print('Error fetching appointment status: $e');
      }

      // Send SMS via Cloud Function
      bool smsSent = false;
      String smsMessage = '';
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('sendSmsReminder')
            .call({
          'patientPhone': cleanedPhone,
          'slotStatus': currentStatus,
          'patientId': patientId,
          'appointmentDate': appointmentDate,
          'appointmentTime': appointmentTime,
        });

        if (result.data != null && result.data['success'] == true) {
          smsSent = true;
          smsMessage = result.data['message'] ?? 'SMS sent successfully';
        } else {
          smsMessage = result.data?['message'] ?? 'SMS sending failed';
        }
      } catch (e) {
        print('Error calling Cloud Function for SMS: $e');
        smsMessage = 'SMS service unavailable: ${e.toString()}';
      }

      // Get device token for push notification
      String? deviceToken =
          await _notificationServices.getDeviceToken(patientId);

      bool notificationSent = false;
      if (deviceToken != null) {
        notificationSent =
            await _pushNotificationServices.sendNotificationToUser(
          deviceToken: deviceToken,
          title: 'Appointment Reminder',
          body:
              'You have an appointment on $appointmentDate at $appointmentTime. Please confirm your attendance.',
          data: {
            'type': 'appointment_reminder',
            'patientId': patientId,
            'date': appointmentDate,
            'time': appointmentTime,
            'action': 'reminder',
          },
          context: context,
        );
      }

      // Show appropriate success/error message
      if (mounted) {
        String message;
        Color backgroundColor;
        
        // Check if error is about landline
        bool isLandlineError = smsMessage.toLowerCase().contains('landline');

        if (smsSent && notificationSent) {
          message = 'Reminder sent successfully via SMS and push notification!';
          backgroundColor = Colors.green;
        } else if (smsSent && deviceToken == null) {
          message =
              'SMS sent successfully! (No device token for push notification)';
          backgroundColor = Colors.green;
        } else if (smsSent && !notificationSent) {
          message = 'SMS sent successfully! (Push notification failed)';
          backgroundColor = Colors.orange;
        } else if (!smsSent && notificationSent) {
          if (isLandlineError) {
            message = 'Push notification sent! (SMS failed: $phone appears to be a landline number)';
          } else {
            message = 'Push notification sent! (SMS failed: $smsMessage)';
          }
          backgroundColor = Colors.orange;
        } else {
          if (isLandlineError) {
            message = 'Cannot send SMS: $phone appears to be a landline number. SMS can only be sent to mobile numbers.';
          } else {
            message =
                'Reminder failed: SMS - $smsMessage, Push - ${deviceToken == null ? "No device token" : "Failed"}';
          }
          backgroundColor = Colors.red;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: Duration(seconds: isLandlineError ? 6 : 3),
            action: isLandlineError ? SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ) : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending reminder: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (context, constraints) {
            final isSmallScreen = constraints.maxWidth < 600;
            return Text(
              'Master Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: isSmallScreen ? 18 : 24,
              ),
            );
          },
        ),
        backgroundColor: const Color(0xFF1976D2),
        elevation: 2,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // More granular breakpoints for better responsiveness
          final isExtraWideScreen = constraints.maxWidth > 1600;
          final isWideScreen = constraints.maxWidth > 1200;
          final isMediumScreen = constraints.maxWidth > 800;
          final isSmallScreen = constraints.maxWidth < 600;
          final isVerySmallScreen = constraints.maxWidth < 400;

          if (isWideScreen) {
            // Wide screen: Two columns side by side
            return Container(
              padding: EdgeInsets.all(isSmallScreen
                  ? 8.0
                  : isMediumScreen
                      ? 12.0
                      : 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: isExtraWideScreen ? 70 : 65,
                    child: _buildLeftColumn(constraints),
                  ),
                  SizedBox(
                      width: isSmallScreen
                          ? 8
                          : isMediumScreen
                              ? 12
                              : 16),
                  Expanded(
                    flex: isExtraWideScreen ? 30 : 35,
                    child: _buildRightColumn(constraints),
                  ),
                ],
              ),
            );
          } else if (isMediumScreen) {
            // Medium screen: Two columns with adjusted spacing
            return Container(
              padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 60,
                    child: _buildLeftColumn(constraints),
                  ),
                  SizedBox(width: isSmallScreen ? 8 : 12),
                  Expanded(
                    flex: 40,
                    child: _buildRightColumn(constraints),
                  ),
                ],
              ),
            );
          } else {
            // Small screen: Stacked columns with proper scrolling
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isVerySmallScreen
                  ? 8.0
                  : isSmallScreen
                      ? 10.0
                      : 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLeftColumn(constraints),
                  SizedBox(
                      height: isVerySmallScreen
                          ? 8
                          : isSmallScreen
                              ? 10
                              : 12),
                  _buildRightColumn(constraints),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  /// Left Column: Daily Appointment Queue
  Widget _buildLeftColumn(BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isMediumScreen = constraints.maxWidth < 900;
    final isTabletOrSmall = constraints.maxWidth < 1000;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen
            ? 12.0
            : isMediumScreen
                ? 16.0
                : 24.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: isTabletOrSmall ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Title + Actions
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Daily Appointment Queue',
                    style: TextStyle(
                      fontSize: isSmallScreen
                          ? 18
                          : isMediumScreen
                              ? 20
                              : 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A1A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Book Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 10 : 14,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                      ),
                      onPressed: () =>
                          context.push('/dashboard/new-appointment'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1976D2),
                        side: const BorderSide(color: Color(0xFF1976D2)),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 10 : 14,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                      ),
                      onPressed: () => _importCsvFile(context),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print Schedule'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey[700],
                        side: BorderSide(color: Colors.blueGrey[700]!),
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 10 : 14,
                          vertical: isSmallScreen ? 8 : 10,
                        ),
                      ),
                      onPressed: () => _printSchedule(context),
                    ),
                    IconButton(
                      tooltip: 'Show booking QR',
                      icon: const Icon(Icons.qr_code),
                      onPressed: () => _showQrDialog(context),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Text(
              'Showing: ${DateFormat('MMM dd, yyyy').format(DateTime.now())} - ${DateFormat('MMM dd, yyyy').format(DateTime.now().add(const Duration(days: 29)))} (Next 30 Days)',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: const Color(0xFF666666),
                fontWeight: FontWeight.w500,
              ),
            ),
            Divider(height: isSmallScreen ? 20 : 32, thickness: 1),
            // Search and Filter Bar
            _buildSearchBar(constraints),
            SizedBox(height: isSmallScreen ? 12 : 16),
            // Responsive layout: Cards for small screens, DataTable for large screens
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _getTodayAppointments(),
                builder: (context, snapshot) {
                  // Show scroll indicator when table is wider than container
                  final showScrollHint = constraints.maxWidth < 1200;
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (!snapshot.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'No appointments scheduled for the next 30 days',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  // Convert documents to AppointmentData objects with error handling
                  final allAppointments = <AppointmentData>[];
                  final parseErrors = <String>[];
                  
                  for (var doc in snapshot.data!.docs) {
                    try {
                      final apt = AppointmentData.fromFirestore(doc);
                      allAppointments.add(apt);
                    } catch (e) {
                      parseErrors.add('Error parsing doc ${doc.id}: $e');
                      print('❌ Error parsing appointment ${doc.id}: $e');
                      print('   Document data: ${doc.data()}');
                    }
                  }

                  // Debug: Log all appointments before filtering
                  print('📊 Total appointments from Firestore: ${allAppointments.length}');
                  if (parseErrors.isNotEmpty) {
                    print('⚠️ Parse errors: ${parseErrors.length}');
                    for (var error in parseErrors) {
                      print('   $error');
                    }
                  }
                  
                  // Log status distribution to identify status issues
                  final statusCounts = <String, int>{};
                  for (var apt in allAppointments) {
                    statusCounts[apt.status] = (statusCounts[apt.status] ?? 0) + 1;
                  }
                  print('📈 Status distribution: $statusCounts');
                  
                  // Log sample appointments with full details
                  for (var apt in allAppointments.take(10)) {
                    final dateStr = Date_Utils.formatDate(apt.date);
                    print('📅 Appointment: "${apt.name}", Date: $dateStr, Status: "${apt.status}"');
                  }

                  // Filter appointments to only show next 30 days
                  var appointments =
                      _filterAppointmentsByDateRange(allAppointments);
                  
                  // Apply search filter if search query is not empty
                  if (_searchController.text.isNotEmpty) {
                    appointments = _applySearchFilter(appointments, _searchCategory, _searchController.text);
                  }
                  
                  // Debug: Log filtered appointments
                  print('✅ Filtered appointments (within 30 days): ${appointments.length}');
                  for (var apt in appointments.take(10)) {
                    final dateStr = Date_Utils.formatDate(apt.date);
                    print('   ✓ ${apt.name} - $dateStr @ ${apt.formattedTime} (${apt.status})');
                  }

                  // Check if filtered list is empty
                  if (appointments.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _searchController.text.isNotEmpty
                              ? 'No appointments found matching your search'
                              : 'No appointments scheduled for the next 30 days',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  // Sort by appointment time
                  appointments.sort((a, b) =>
                      a.appointmentDateTime.compareTo(b.appointmentDateTime));

                  // Use card layout for small/medium screens, DataTable for larger screens
                  // Switch to cards at 1000px instead of 900px for better table visibility
                  if (constraints.maxWidth < 1000) {
                    return _buildAppointmentCards(appointments, constraints);
                  } else {
                    return Column(
                      children: [
                        // Scroll hint for smaller screens
                        if (showScrollHint)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.swap_horiz,
                                    size: 16, color: Colors.blue[700]!),
                                SizedBox(width: 8),
                                Text(
                                  'Scroll horizontally and vertically to see all columns and appointments',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700]!,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child:
                              _buildAppointmentTable(appointments, constraints),
                        ),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build appointment cards for small/medium screens
  Widget _buildAppointmentCards(
      List<AppointmentData> appointments, BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      shrinkWrap: false,
      itemCount: appointments.length,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        return Card(
          margin: EdgeInsets.only(bottom: isSmallScreen ? 10 : 12),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appointment.name,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    _buildApptStatusBadge(appointment.status,
                        userResponse: appointment.userResponse,
                        isSmallScreen: isSmallScreen),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: isSmallScreen ? 16 : 18,
                      color: const Color(0xFF666666),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: Text(
                        appointment.ukFormattedDate +
                            ' @ ' +
                            appointment.formattedTime,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13 : 14,
                          color: const Color(0xFF666666),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Row(
                  children: [
                    Icon(
                      Icons.phone,
                      size: isSmallScreen ? 16 : 18,
                      color: const Color(0xFF666666),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: Text(
                        appointment.phone,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 13 : 14,
                          color: const Color(0xFF666666),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 8 : 10),
                // Appt Status
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: isSmallScreen ? 16 : 18,
                      color: const Color(0xFF666666),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: _buildApptStatusBadge(appointment.status,
                          userResponse: appointment.userResponse,
                          isSmallScreen: isSmallScreen),
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 6 : 8),
                // User Response
                Row(
                  children: [
                    Icon(
                      Icons.reply,
                      size: isSmallScreen ? 16 : 18,
                      color: const Color(0xFF666666),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: _buildUserResponseBadge(
                          appointment.userResponseDisplay,
                          isSmallScreen: isSmallScreen),
                    ),
                  ],
                ),
                SizedBox(height: isSmallScreen ? 6 : 8),
                // Reallocation Status
                Row(
                  children: [
                    Icon(
                      Icons.swap_horiz,
                      size: isSmallScreen ? 16 : 18,
                      color: const Color(0xFF666666),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: _buildReallocationBadge(
                          appointment.reallocationStatusDisplay,
                          isSmallScreen: isSmallScreen),
                    ),
                  ],
                ),
                if (appointment.newUserName != null &&
                    appointment.newUserName!.isNotEmpty) ...[
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Row(
                    children: [
                      Icon(
                        Icons.person_add,
                        size: isSmallScreen ? 16 : 18,
                        color: const Color(0xFF666666),
                      ),
                      SizedBox(width: isSmallScreen ? 6 : 8),
                      Expanded(
                        child: Text(
                          appointment.newUserNameDisplay,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            color: const Color(0xFF666666),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (appointment.daysMoved != null &&
                    appointment.daysMoved! > 0) ...[
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Row(
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: isSmallScreen ? 16 : 18,
                        color: const Color(0xFF666666),
                      ),
                      SizedBox(width: isSmallScreen ? 6 : 8),
                      Expanded(
                        child: Text(
                          appointment.daysMovedDisplay,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: isSmallScreen ? 10 : 12),
                // Action Buttons Row
                Row(
                  children: [
                    // Edit Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showEditAppointmentDialog(
                            context, appointment, constraints),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1976D2),
                          side: const BorderSide(color: Color(0xFF1976D2)),
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 12 : 16,
                            vertical: isSmallScreen ? 10 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        icon: Icon(
                          Icons.edit,
                          size: isSmallScreen ? 16 : 18,
                        ),
                        label: Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    // Quick Actions Menu (SMS Templates)
                    Builder(
                      builder: (buttonContext) {
                        return IconButton(
                          onPressed: () => _showQuickActionsMenu(
                            buttonContext,
                            context,
                            appointment,
                            constraints,
                          ),
                          icon: const Icon(Icons.bolt),
                          color: Colors.amber,
                          tooltip: 'Quick Actions',
                          iconSize: isSmallScreen ? 20 : 22,
                        );
                      },
                    ),
                    SizedBox(width: isSmallScreen ? 4 : 6),
                    // Remind Button - Professional sizing with dynamic width
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: isSmallScreen ? 100 : 110,
                          maxWidth: double.infinity,
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isReminderButtonEnabled(appointment)
                              ? () => _triggerReminder(
                                    appointment.patientID,
                                    appointment.phone,
                                    appointment.name,
                                    appointment.formattedDate,
                                    appointment.formattedTime,
                                  )
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _getReminderButtonColor(appointment),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[400],
                            disabledForegroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 14 : 18,
                              vertical: isSmallScreen ? 11 : 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 2,
                            minimumSize: Size(isSmallScreen ? 100 : 110,
                                isSmallScreen ? 40 : 44),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.standard,
                          ),
                          icon: Icon(
                            _getReminderButtonIcon(appointment),
                            size: isSmallScreen ? 16 : 18,
                          ),
                          label: Text(
                            _getReminderButtonText(appointment),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build appointment table for large screens
  Widget _buildAppointmentTable(
      List<AppointmentData> appointments, BoxConstraints constraints) {
    // More granular breakpoints for better responsiveness
    final screenWidth = constraints.maxWidth;
    final isVerySmallTable = screenWidth < 1100;
    final isSmallTable = screenWidth < 1300;
    final isMediumTable = screenWidth < 1500;

    // Calculate dynamic column spacing based on available width
    final baseSpacing = isVerySmallTable
        ? 6.0
        : isSmallTable
            ? 8.0
            : isMediumTable
                ? 12.0
                : 16.0;
    final columnSpacing = baseSpacing;

    // Calculate font sizes dynamically
    final headingFontSize = isVerySmallTable
        ? 9.0
        : isSmallTable
            ? 10.0
            : isMediumTable
                ? 11.0
                : 12.0;
    final cellFontSize = isVerySmallTable
        ? 10.0
        : isSmallTable
            ? 11.0
            : isMediumTable
                ? 12.0
                : 13.0;

    // Determine which columns to show based on screen width
    // Always show all columns but make them scrollable
    final showNewUserName = true; // Always show, but with better constraints
    final showMoved = true; // Always show
    final showReallocation = true; // Always show
    final showUserResponse = true; // Always show

    // Calculate minimum table width to ensure all columns fit
    // Patient Name: 120, Date&Time: 140, Phone: 100, Appt Status: 120,
    // User Response: 100, Reallocation: 120, New User: 180, Moved: 80, Action: 180 (dynamic width for buttons)
    final minTableWidth = 120 +
        140 +
        100 +
        120 +
        100 +
        120 +
        180 +
        80 +
        180 +
        (columnSpacing * 8);

    return LayoutBuilder(
      builder: (context, tableConstraints) {
        // Calculate the actual table width needed
        final actualTableWidth = minTableWidth > tableConstraints.maxWidth
            ? minTableWidth
            : tableConstraints.maxWidth;

        // Build the data table widget
        final dataTable = DataTable(
          headingRowColor: MaterialStateProperty.all(
            const Color(0xFFF5F5F5),
          ),
          headingRowHeight: isVerySmallTable
              ? 40
              : isSmallTable
                  ? 45
                  : isMediumTable
                      ? 50
                      : 55,
          dataRowMinHeight: isVerySmallTable
              ? 50
              : isSmallTable
                  ? 55
                  : isMediumTable
                      ? 60
                      : 65,
          dataRowMaxHeight: isVerySmallTable
              ? 65
              : isSmallTable
                  ? 70
                  : isMediumTable
                      ? 75
                      : 80, // Reduced to prevent tall rows
          columnSpacing: columnSpacing,
          columns: [
            // Always show: Patient Name, Date & Time, Phone, Appt Status, Action
            DataColumn(
              label: Text(
                'Patient Name',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: headingFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Date & Time',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: headingFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Phone',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: headingFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Appt Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: headingFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
            // Conditionally show User Response
            if (showUserResponse)
              DataColumn(
                label: Text(
                  'User Response',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: headingFontSize,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            // Conditionally show Reallocation
            if (showReallocation)
              DataColumn(
                label: Text(
                  'Reallocation',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: headingFontSize,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            // Conditionally show New User
            if (showNewUserName)
              DataColumn(
                label: Text(
                  'New User',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: headingFontSize,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            // Conditionally show Moved
            if (showMoved)
              DataColumn(
                label: Text(
                  'Moved',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: headingFontSize,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            // Always show Action
            DataColumn(
              label: Text(
                'Action',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: headingFontSize,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ),
          ],
          rows: appointments.map((appointment) {
            return DataRow(
              cells: [
                // Always show: Patient Name, Date & Time, Phone, Appt Status, Action
                DataCell(
                  Text(
                    appointment.name,
                    style: TextStyle(
                      fontSize: cellFontSize,
                      color: const Color(0xFF333333),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    appointment.ukFormattedDate +
                        ' @ ' +
                        appointment.formattedTime,
                    style: TextStyle(
                      fontSize: cellFontSize,
                      color: const Color(0xFF333333),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    appointment.phone,
                    style: TextStyle(
                      fontSize: cellFontSize,
                      color: const Color(0xFF333333),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  _buildApptStatusBadge(
                    appointment.status,
                    userResponse: appointment.userResponse,
                    isSmallScreen: isVerySmallTable,
                  ),
                ),
                // Conditionally show User Response
                if (showUserResponse)
                  DataCell(
                    _buildUserResponseBadge(
                      appointment.userResponseDisplay,
                      isSmallScreen: isVerySmallTable,
                    ),
                  ),
                // Conditionally show Reallocation
                if (showReallocation)
                  DataCell(
                    _buildReallocationBadge(
                      appointment.reallocationStatusDisplay,
                      isSmallScreen: isVerySmallTable,
                    ),
                  ),
                // Conditionally show New User - with fixed width to prevent wrapping
                if (showNewUserName)
                  DataCell(
                    Container(
                      constraints: BoxConstraints(
                        maxWidth:
                            180, // Fixed width to prevent excessive wrapping
                        minWidth: 150,
                      ),
                      child: Tooltip(
                        message: appointment
                            .newUserNameDisplay, // Show full text on hover
                        child: Text(
                          appointment.newUserNameDisplayCompact,
                          style: TextStyle(
                            fontSize: cellFontSize - 1,
                            color: appointment.newUserName != null
                                ? const Color(0xFF1976D2)
                                : const Color(0xFF999999),
                            fontWeight: appointment.newUserName != null
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines:
                              1, // Single line to prevent row height increase
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                // Conditionally show Moved
                if (showMoved)
                  DataCell(
                    Text(
                      appointment.daysMovedDisplay,
                      style: TextStyle(
                        fontSize: cellFontSize,
                        color: appointment.daysMoved != null &&
                                appointment.daysMoved! > 0
                            ? Colors.green[700]
                            : const Color(0xFF999999),
                        fontWeight: appointment.daysMoved != null &&
                                appointment.daysMoved! > 0
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                // Always show Action - Edit and Remind buttons with dynamic width
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      // Edit Button
                      IconButton(
                        onPressed: () => _showEditAppointmentDialog(
                            context, appointment, constraints),
                        icon: Icon(
                          Icons.edit,
                          size: isVerySmallTable
                              ? 16
                              : isSmallTable
                                  ? 18
                                  : 20,
                          color: const Color(0xFF1976D2),
                        ),
                        tooltip: 'Edit Appointment',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: isVerySmallTable ? 28 : 32,
                          minHeight: isVerySmallTable ? 28 : 32,
                        ),
                      ),
                      SizedBox(width: isVerySmallTable ? 4 : 6),
                      // Quick Actions Menu (SMS Templates)
                      Builder(
                        builder: (buttonContext) {
                          return IconButton(
                            onPressed: () => _showQuickActionsMenu(
                              buttonContext,
                              context,
                              appointment,
                              constraints,
                            ),
                            icon: const Icon(Icons.bolt),
                            color: Colors.amber,
                            tooltip: 'Quick Actions',
                            iconSize: isVerySmallTable
                                ? 16
                                : isSmallTable
                                    ? 18
                                    : 20,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(
                              minWidth: isVerySmallTable ? 28 : 32,
                              minHeight: isVerySmallTable ? 28 : 32,
                            ),
                          );
                        },
                      ),
                      SizedBox(width: isVerySmallTable ? 4 : 6),
                      // Remind Button - Professional sizing with dynamic width
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: isVerySmallTable
                                ? 70
                                : isSmallTable
                                    ? 80
                                    : 90,
                            maxWidth: double.infinity,
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _isReminderButtonEnabled(appointment)
                                ? () => _triggerReminder(
                                      appointment.patientID,
                                      appointment.phone,
                                      appointment.name,
                                      appointment.formattedDate,
                                      appointment.formattedTime,
                                    )
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _getReminderButtonColor(appointment),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[400],
                              disabledForegroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isVerySmallTable
                                    ? 8
                                    : isSmallTable
                                        ? 10
                                        : 12,
                                vertical: isVerySmallTable
                                    ? 6
                                    : isSmallTable
                                        ? 7
                                        : 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              elevation: 2,
                              minimumSize: Size(
                                isVerySmallTable
                                    ? 70
                                    : isSmallTable
                                        ? 80
                                        : 90,
                                isVerySmallTable
                                    ? 32
                                    : isSmallTable
                                        ? 34
                                        : 36,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.standard,
                            ),
                            icon: Icon(
                              _getReminderButtonIcon(appointment),
                              size: isVerySmallTable
                                  ? 12
                                  : isSmallTable
                                      ? 13
                                      : 14,
                            ),
                            label: Text(
                              _getReminderButtonText(appointment),
                              style: TextStyle(
                                fontSize: isVerySmallTable
                                    ? 9
                                    : isSmallTable
                                        ? 10
                                        : 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        );

        // Professional bidirectional scrolling with improved physics
        // Structure: Horizontal Scrollbar -> Horizontal ScrollView -> Vertical Scrollbar -> Vertical ScrollView -> Table
        return Scrollbar(
          thumbVisibility: true,
          interactive: true,
          controller: _horizontalScrollController,
          thickness: 12.0,
          radius: const Radius.circular(6),
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: actualTableWidth,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                interactive: true,
                controller: _verticalScrollController,
                thickness: 12.0,
                radius: const Radius.circular(6),
                child: SingleChildScrollView(
                  controller: _verticalScrollController,
                  scrollDirection: Axis.vertical,
                  physics: const ClampingScrollPhysics(),
                  child: dataTable,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Right Column: Reallocation Command Center
  Widget _buildRightColumn(BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isMediumScreen = constraints.maxWidth < 900;
    final isTabletOrSmall = constraints.maxWidth < 1000;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen
            ? 12.0
            : isMediumScreen
                ? 16.0
                : 24.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: isTabletOrSmall ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // Title
            Text(
              'Reallocation Command Center',
              style: TextStyle(
                fontSize: isSmallScreen
                    ? 16
                    : isMediumScreen
                        ? 18
                        : 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
                letterSpacing: 0.5,
              ),
            ),
            Divider(height: isSmallScreen ? 20 : 32, thickness: 1),
            // Scrollable content area with VERTICAL scrolling only
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Priority Queue Card
                    _buildPriorityQueueCard(constraints),
                    SizedBox(height: isSmallScreen ? 16 : 24),
                    // KPI Cards
                    _buildKPICards(constraints),
                    SizedBox(height: isSmallScreen ? 16 : 24),
                    // Activity Log
                    _buildActivityLog(constraints),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Priority Queue Card Section
  Widget _buildPriorityQueueCard(BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.trending_up,
                    color: Color(0xFF1976D2),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Priority Queue',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A1A),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Priority patients list
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Appointments')
                  .where('isPriority', isEqualTo: true)
                  .where('status', isEqualTo: 'Confirmed_Priority')
                  .orderBy('date')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: isSmallScreen ? 11 : 12,
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No patients on priority list',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final priorityAppointments = snapshot.data!.docs
                    .map((doc) => AppointmentData.fromFirestore(doc))
                    .toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: priorityAppointments.map((appointment) {
                    // Calculate waiting time with granular display
                    String waitingInfo = 'Not available';
                    if (appointment.priorityJoinedAt != null) {
                      final difference = DateTime.now().difference(appointment.priorityJoinedAt!);
                      if (difference.inDays > 0) {
                        waitingInfo = '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} waiting';
                      } else if (difference.inHours > 0) {
                        waitingInfo = '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} waiting';
                      } else {
                        waitingInfo = 'Joined just now';
                      }
                    }

                    return Padding(
                      padding: EdgeInsets.only(bottom: isSmallScreen ? 8 : 10),
                      child: Container(
                        padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF1976D2).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appointment.name,
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 13 : 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  SizedBox(height: isSmallScreen ? 4 : 6),
                                  Text(
                                    'Current: ${appointment.ukFormattedDate} @ ${appointment.formattedTime}',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 11 : 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallScreen ? 8 : 10,
                                vertical: isSmallScreen ? 4 : 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1976D2).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                waitingInfo,
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 11 : 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF1976D2),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// KPI Cards Section with real-time metrics
  Widget _buildKPICards(BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Appointments').snapshots(),
      builder: (context, appointmentsSnapshot) {
        // Calculate total cancellations dynamically from appointments
        int totalCancellations = 0;
        int totalReallocations = 0;
        int totalDaysMoved = 0;

        if (appointmentsSnapshot.hasData) {
          final appointments = appointmentsSnapshot.data!.docs;

          for (var doc in appointments) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? '';
            final statusLower = status.toLowerCase();
            final userResponse = data['userResponse'] as String?;

            // Count cancellations:
            // 1. status is 'cancelled' (any case)
            // 2. status is 'AVAILABLE' (uppercase) with userResponse 'Cancelled'
            // 3. status is 'available' (lowercase) with userResponse 'Cancelled'
            if (statusLower == 'cancelled' ||
                (status == 'AVAILABLE' && userResponse == 'Cancelled') ||
                (statusLower == 'available' && userResponse == 'Cancelled')) {
              totalCancellations++;
            }

            // Count reallocations: reallocationStatus is 'Reallocated' (case-insensitive)
            final reallocationStatus = data['reallocationStatus'] as String?;
            if (reallocationStatus != null) {
              final reallocationStatusLower =
                  reallocationStatus.toLowerCase().trim();
              if (reallocationStatusLower == 'reallocated') {
                totalReallocations++;
              }
            }

            // Sum days moved (handle both int and string types)
            final daysMovedValue = data['daysMoved'];
            if (daysMovedValue != null) {
              int days = 0;
              // Handle different types: int, string, or double
              if (daysMovedValue is int) {
                days = daysMovedValue;
              } else if (daysMovedValue is double) {
                days = daysMovedValue.toInt();
              } else if (daysMovedValue is String) {
                days = int.tryParse(daysMovedValue) ?? 0;
              }

              // Only add positive days (negative or zero means no movement or moved later)
              if (days > 0) {
                totalDaysMoved += days;
              }
            }
          }
        }

        // Always use calculated values from appointments (real-time, most accurate)
        // The metrics document may not be updated, so we calculate directly from appointments
        // This ensures we always show the correct count

        // Stack cards vertically on small screens
        if (isSmallScreen) {
          return Column(
            children: [
              _buildKPICard(
                title: 'TOTAL APPOINTMENTS CANCELED',
                value: totalCancellations.toString(),
                color: Colors.orangeAccent,
                backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                constraints: constraints,
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              _buildKPICard(
                title: 'TOTAL APPOINTMENTS REALLOCATED',
                value: totalReallocations.toString(),
                color: Colors.blueAccent,
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                constraints: constraints,
                onTap: () => _showReallocationChart(context),
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              _buildKPICard(
                title: 'TOTAL DAYS MOVED (NET)',
                value: '$totalDaysMoved Days',
                color: Colors.greenAccent[700] ?? Colors.green,
                backgroundColor: Colors.greenAccent.withOpacity(0.1),
                constraints: constraints,
              ),
            ],
          );
        }

        return Wrap(
          spacing: isSmallScreen ? 8 : 12,
          runSpacing: isSmallScreen ? 10 : 12,
          children: [
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - (isSmallScreen ? 8 : 12)) / 2
                  : constraints.maxWidth,
              child: _buildKPICard(
                title: 'TOTAL APPOINTMENTS CANCELED',
                value: totalCancellations.toString(),
                color: Colors.orangeAccent,
                backgroundColor: Colors.orangeAccent.withOpacity(0.1),
                constraints: constraints,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - (isSmallScreen ? 8 : 12)) / 2
                  : constraints.maxWidth,
              child: _buildKPICard(
                title: 'TOTAL APPOINTMENTS REALLOCATED',
                value: totalReallocations.toString(),
                color: Colors.blueAccent,
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                constraints: constraints,
                onTap: () => _showReallocationChart(context),
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - (isSmallScreen ? 8 : 12)) / 2
                  : constraints.maxWidth,
              child: _buildKPICard(
                title: 'TOTAL DAYS MOVED (NET)',
                value: '$totalDaysMoved Days',
                color: Colors.greenAccent[700] ?? Colors.green,
                backgroundColor: Colors.greenAccent.withOpacity(0.1),
                constraints: constraints,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Individual KPI Card
  Widget _buildKPICard({
    required String title,
    required String value,
    required Color color,
    Color? backgroundColor,
    required BoxConstraints constraints,
    VoidCallback? onTap,
  }) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isMediumScreen = constraints.maxWidth < 900;

    final cardContent = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: EdgeInsets.all(isSmallScreen
            ? 12.0
            : isMediumScreen
                ? 14.0
                : 18.0),
        decoration: BoxDecoration(
          color: backgroundColor ?? color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen
                    ? 11
                    : isMediumScreen
                        ? 12
                        : 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isSmallScreen ? 8 : 10),
            Text(
              value,
              style: TextStyle(
                fontSize: isSmallScreen
                    ? 18
                    : isMediumScreen
                        ? 20
                        : 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    // Wrap in InkWell if onTap is provided
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: cardContent,
      );
    }

    return cardContent;
  }

  /// Activity Log Section with real-time entries
  Widget _buildActivityLog(BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isMediumScreen = constraints.maxWidth < 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Filter Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reallocation Activity Log',
              style: TextStyle(
                fontSize: isSmallScreen
                    ? 14
                    : isMediumScreen
                        ? 16
                        : 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
        SizedBox(height: isSmallScreen ? 8 : 10),
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildLogFilterChip('All', null, constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Claims', 'slot_claim', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Cancellations', 'cancellation', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Cascades', 'cascade_trigger', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Errors', 'error', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Maintenance', 'maintenance', constraints),
            ],
          ),
        ),
        SizedBox(height: isSmallScreen ? 10 : 12),
        Container(
          height: constraints.maxWidth < 1000 ? 400 : 500,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFFFAFAFA),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: _metricsService.getActivityLogStream(
              limit: _activityLogLimit,
              typeFilter: _selectedLogType,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error loading activity log: ${snapshot.error}',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: isSmallScreen ? 11 : 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                // Show proper empty state when no activity log entries exist
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: isSmallScreen ? 48 : 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 16),
                        Text(
                          'No activity yet',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 8 : 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 16 : 24,
                          ),
                          child: Text(
                            'Activity log will appear here once\npatients start interacting with the system.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              color: Colors.grey[500],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Parse and display real activity log entries
              final entries = snapshot.data!.docs
                  .map((doc) => ActivityLogEntry.fromFirestore(doc))
                  .toList();

              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      children: entries.map((entry) {
                        return _buildActivityLogItem(
                          entry.message,
                          entry.formattedTimestamp,
                          entry.type,
                          constraints,
                        );
                      }).toList(),
                    ),
                  ),
                  // Load More Button
                  if (entries.length >= _activityLogLimit)
                    Padding(
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _activityLogLimit += 10;
                            });
                          },
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text('Load More'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isSmallScreen ? 10 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build filter chip for activity log types
  Widget _buildLogFilterChip(
      String label, String? type, BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isSelected = _selectedLogType == type;

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: isSmallScreen ? 11 : 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedLogType = selected ? type : null;
          _activityLogLimit = 10; // Reset limit when filter changes
        });
      },
      selectedColor: _getLogTypeColor(type).withOpacity(0.2),
      checkmarkColor: _getLogTypeColor(type),
      labelStyle: TextStyle(
        color: isSelected ? _getLogTypeColor(type) : Colors.grey[700],
      ),
      side: BorderSide(
        color: isSelected ? _getLogTypeColor(type) : Colors.grey[300]!,
        width: isSelected ? 1.5 : 1,
      ),
    );
  }

  /// Get color for log type
  Color _getLogTypeColor(String? type) {
    switch (type) {
      case 'slot_claim':
        return Colors.green;
      case 'cancellation':
      case 'rearrangement':
        return Colors.orange;
      case 'cascade_trigger':
        return Colors.blue;
      case 'error':
        return Colors.red;
      case 'maintenance':
        return Colors.purple;
      case 'dismissal':
        return Colors.grey;
      default:
        return const Color(0xFF1976D2);
    }
  }

  /// Individual Activity Log Item
  Widget _buildActivityLogItem(
    String activity,
    String timestamp,
    String? type,
    BoxConstraints constraints,
  ) {
    final isSmallScreen = constraints.maxWidth < 600;
    final typeColor = _getLogTypeColor(type);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 6.0 : 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isSmallScreen ? 8 : 10,
            height: isSmallScreen ? 8 : 10,
            margin: EdgeInsets.only(
              top: isSmallScreen ? 4 : 6,
              right: isSmallScreen ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: typeColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: typeColor.withOpacity(0.3),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 4 : 6),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 12,
                    color: const Color(0xFF888888),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Status Badge Widget (for Appt Status column)
  /// Format: "Appt(Active, Confirmed, Cancelled)"
  Widget _buildApptStatusBadge(String status,
      {String? userResponse, bool isSmallScreen = false}) {
    Color backgroundColor;
    Color textColor;
    String displayText;

    // Combine status with userResponse for display
    String statusLower = status.toLowerCase();

    if (statusLower == 'active' && userResponse == 'Confirmed') {
      backgroundColor = Colors.green;
      textColor = Colors.white;
      displayText = 'Appt(Active, Confirmed)';
    } else if (statusLower == 'active') {
      backgroundColor = Colors.green;
      textColor = Colors.white;
      displayText = 'Appt(Active)';
    } else if (statusLower == 'cancelled' && userResponse == 'Cancelled') {
      backgroundColor = Colors.red;
      textColor = Colors.white;
      displayText = 'Appt(Cancelled)';
    } else if (statusLower == 'cancelled') {
      backgroundColor = Colors.red;
      textColor = Colors.white;
      displayText = 'Appt(Cancelled)';
    } else if (statusLower == 'available' && userResponse == 'Cancelled') {
      // Show as cancelled if status is AVAILABLE but userResponse is Cancelled
      backgroundColor = Colors.red;
      textColor = Colors.white;
      displayText = 'Appt(Cancelled)';
    } else if (statusLower == 'confirmed') {
      backgroundColor = Colors.blue;
      textColor = Colors.white;
      displayText = 'Appt(Confirmed)';
    } else if (statusLower == 'no response') {
      backgroundColor = Colors.orange;
      textColor = Colors.white;
      displayText = 'Appt(No Response)';
    } else if (status == 'ON_HOLD_OFFER_SENT' ||
        statusLower == 'on_hold_offer_sent') {
      backgroundColor = Colors.amber;
      textColor = Colors.white;
      displayText = 'Offer Sent';
    } else if (status == 'Confirmed_Priority' || statusLower == 'confirmed_priority') {
      backgroundColor = const Color(0xFF1976D2);
      textColor = Colors.white;
      displayText = 'Priority';
    } else {
      backgroundColor = Colors.grey;
      textColor = Colors.white;
      displayText = 'Appt($status)';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 10,
        vertical: isSmallScreen ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontSize: isSmallScreen ? 9 : 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// User Response Badge Widget
  Widget _buildUserResponseBadge(String response,
      {bool isSmallScreen = false}) {
    if (response == '-') {
      return Text(
        '-',
        style: TextStyle(
          fontSize: isSmallScreen ? 10 : 12,
          color: Colors.grey[600],
        ),
      );
    }

    Color backgroundColor;
    Color textColor;

    if (response == 'Confirmed') {
      backgroundColor = Colors.green.withOpacity(0.2);
      textColor = Colors.green[700]!;
    } else {
      backgroundColor = Colors.red.withOpacity(0.2);
      textColor = Colors.red[700]!;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 10,
        vertical: isSmallScreen ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        response,
        style: TextStyle(
          color: textColor,
          fontSize: isSmallScreen ? 9 : 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Reallocation Status Badge Widget
  Widget _buildReallocationBadge(String status, {bool isSmallScreen = false}) {
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case 'Original':
        backgroundColor = Colors.blue.withOpacity(0.2);
        textColor = Colors.blue[700]!;
        break;
      case 'Reallocated':
        backgroundColor = Colors.purple.withOpacity(0.2);
        textColor = Colors.purple[700]!;
        break;
      case 'Not Reallocated':
        backgroundColor = Colors.grey.withOpacity(0.2);
        textColor = Colors.grey[700]!;
        break;
      default:
        backgroundColor = Colors.grey.withOpacity(0.2);
        textColor = Colors.grey[700]!;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 10,
        vertical: isSmallScreen ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontSize: isSmallScreen ? 9 : 11,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Show Edit Appointment Dialog
  Future<void> _showEditAppointmentDialog(BuildContext context,
      AppointmentData appointment, BoxConstraints constraints) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return EditAppointmentDialog(
          appointment: appointment,
          constraints: constraints,
        );
      },
    );

    // If update was successful, the dialog will have returned true
    // The snackbar is already shown in the dialog, so we don't need to do anything here
    if (result == true && mounted) {
      // Optionally refresh the data or show additional feedback
      // The StreamBuilder will automatically update when Firestore changes
    }
  }

  /// Import CSV file and bulk upload appointments
  /// 
  /// CSV FILE FORMAT REQUIREMENTS:
  /// - Required columns: Patient Name, Phone, Appt Date, Appt Time
  /// - Column names are case-insensitive and can have spaces
  /// Web-specific file picker using native HTML input (more reliable than file_picker on web)
  Future<Uint8List?> _pickFileWeb() async {
    if (!kIsWeb) return null;

    final completer = Completer<Uint8List?>();
    html.FileUploadInputElement? input;
    
    try {
      // Create a hidden file input element
      input = html.FileUploadInputElement()
        ..accept = '.csv'
        ..style.display = 'none';
      
      html.document.body?.append(input);

      // Set up a timeout to complete with null if user doesn't select
      Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          input?.remove();
          completer.complete(null);
        }
      });

      // Listen for file selection
      input.onChange.listen((e) async {
        try {
          final files = input?.files;
          if (files == null || files.isEmpty) {
            input?.remove();
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            return;
          }

          final file = files[0];
          print('📁 Selected file: ${file.name}, size: ${file.size} bytes');
          
          if (!file.name.toLowerCase().endsWith('.csv')) {
            print('❌ Invalid file type: ${file.name}');
            input?.remove();
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            return;
          }

          // Read file as bytes
          final reader = html.FileReader();
          
          reader.onLoadEnd.listen((e) {
            input?.remove();
            try {
              if (reader.result != null) {
                final bytes = reader.result as Uint8List;
                print('✅ File read successfully: ${bytes.length} bytes');
                if (!completer.isCompleted) {
                  completer.complete(bytes);
                }
              } else {
                print('❌ FileReader result is null');
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
              }
            } catch (e) {
              print('❌ Error processing file: $e');
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            }
          });
          
          reader.onError.listen((e) {
            input?.remove();
            print('❌ File read error: $e');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          });

          reader.readAsArrayBuffer(file);
        } catch (e) {
          input?.remove();
          print('❌ Error in file selection: $e');
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }
      });

      // Trigger file picker
      print('📂 Opening file picker...');
      input.click();
    } catch (e) {
      print('❌ Web file picker error: $e');
      input?.remove();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    return completer.future;
  }

  /// Import CSV file from local storage
  /// - Date formats supported: "30 January 2026", "30-01-2026", "30/01/2026", "2026-01-30"
  /// - Time formats supported: "09:00 AM", "09:00", "21:00" (24-hour)
  /// - Phone numbers: Any format (quotes will be removed automatically)
  /// - Dates must be within the next 30 days from today to appear on dashboard
  /// - Status will be automatically set to 'active'
  Future<void> _importCsvFile(BuildContext context) async {
    try {
      Uint8List? fileBytes;

      if (kIsWeb) {
        // Use native HTML file input for web (more reliable than file_picker on web)
        print('🌐 Web platform detected, using native file picker...');
        fileBytes = await _pickFileWeb();
        if (fileBytes == null) {
          print('❌ File picker returned null (user cancelled or error)');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File selection cancelled or failed. Please try again.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        print('✅ File bytes received: ${fileBytes.length} bytes');
      } else {
        // Use file_picker for mobile/desktop
        FilePickerResult? result;
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['csv'],
            withData: true,
            allowMultiple: false,
          );
        } catch (pickerError, stackTrace) {
          print('❌ File picker error: $pickerError');
          print('Stack trace: $stackTrace');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error opening file picker: ${pickerError.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        if (result == null || result.files.isEmpty) {
          return;
        }

        final pickedFile = result.files.first;
        fileBytes = pickedFile.bytes;

        if (fileBytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: Could not read file. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Validate file bytes
      if (fileBytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Selected file is empty. Please select a valid CSV file with data.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 16),
                Text('Processing CSV file...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      if (fileBytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Selected file is empty. Please select a valid CSV file with data.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Convert bytes to string with proper encoding
      String fileContent;
      try {
        fileContent = String.fromCharCodes(fileBytes);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: Could not read file content: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        print('❌ CSV Import Error: Failed to convert bytes to string: $e');
        return;
      }
      
      // Clean up the CSV content - remove problematic quotes and normalize
      String cleanedContent;
      try {
        cleanedContent = fileContent
            .replaceAll(RegExp(r"^'"), '') // Remove leading single quotes
            .replaceAll(RegExp(r"'$"), '') // Remove trailing single quotes
            .replaceAll(RegExp(r'^"'), '') // Remove leading double quotes
            .replaceAll(RegExp(r'"$'), ''); // Remove trailing double quotes
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing file content: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        print('❌ CSV Import Error: Failed to clean file content: $e');
        return;
      }
      
      // Parse CSV with proper quote handling
      List<List<dynamic>> csvData;
      try {
        csvData = const CsvToListConverter(
          shouldParseNumbers: false,
          fieldDelimiter: ',',
        ).convert(cleanedContent);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error parsing CSV file: $e. Please ensure the file is a valid CSV format.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        print('❌ CSV Import Error: Failed to parse CSV: $e');
        print('File content preview (first 500 chars): ${cleanedContent.length > 500 ? cleanedContent.substring(0, 500) : cleanedContent}');
        return;
      }

      if (csvData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: CSV file is empty'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get header row (first row) and clean values thoroughly
      final headers = csvData[0]
          .map((e) {
            String value = e.toString();
            // Remove all types of quotes (single, double, smart quotes)
            value = value.replaceAll(RegExp(r"[''""]"), '');
            // Remove leading/trailing whitespace and normalize spaces
            value = value.trim().replaceAll(RegExp(r'\s+'), ' ');
            return value;
          })
          .toList();
      
      // Debug: Print headers for troubleshooting
      print('CSV Headers found: ${headers.map((h) => '"$h"').join(', ')}');
      
      // Find column indices (case-insensitive, with flexible matching)
      // Support both spaced and non-spaced column names
      int? nameIndex = _findColumnIndex(headers, ['patient name', 'name', 'patientname', 'patient', 'patient name']);
      int? phoneIndex = _findColumnIndex(headers, ['phone', 'phone number', 'phonenumber', 'mobile', 'contact']);
      int? dateIndex = _findColumnIndex(headers, ['appt date', 'appointment date', 'date', 'apptdate', 'appointmentdate', 'appt date']);
      int? timeIndex = _findColumnIndex(headers, ['appt time', 'appointment time', 'time', 'appttime', 'appointmenttime', 'appt time']);
      
      // Debug: Print found indices
      print('Column indices - Name: $nameIndex, Phone: $phoneIndex, Date: $dateIndex, Time: $timeIndex');

      // Check which columns are missing and provide helpful error message
      if (nameIndex == null || phoneIndex == null || dateIndex == null || timeIndex == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          final missingColumns = <String>[];
          if (nameIndex == null) missingColumns.add('Patient Name');
          if (phoneIndex == null) missingColumns.add('Phone');
          if (dateIndex == null) missingColumns.add('Appt Date');
          if (timeIndex == null) missingColumns.add('Appt Time');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error: Missing columns: ${missingColumns.join(', ')}. Found columns: ${headers.join(', ')}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }

      // Process data rows (skip header and empty rows)
      final dataRows = csvData.skip(1).where((row) => row.isNotEmpty).toList();
      final validRows = <Map<String, String>>[];
      final List<String> errorLogs = [];
      final int totalRows = dataRows.length;

      for (int rowIndex = 0; rowIndex < dataRows.length; rowIndex++) {
        final row = dataRows[rowIndex];
        
        // Skip completely empty rows
        if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
          continue;
        }
        
        if (row.length <= nameIndex || row.length <= phoneIndex || 
            row.length <= dateIndex || row.length <= timeIndex) {
          errorLogs.add('Row ${rowIndex + 2}: Insufficient columns (found ${row.length}, need at least ${[nameIndex, phoneIndex, dateIndex, timeIndex].reduce((a, b) => a > b ? a : b) + 1})');
          continue;
        }

        // Clean and extract values, removing quotes
        String cleanValue(dynamic value) {
          if (value == null) return '';
          String cleaned = value.toString().trim();
          cleaned = cleaned.replaceAll(RegExp(r"^'"), '').replaceAll(RegExp(r"'$"), '');
          cleaned = cleaned.replaceAll(RegExp(r'^"'), '').replaceAll(RegExp(r'"$'), '');
          return cleaned.trim();
        }
        
        final name = cleanValue(row[nameIndex]);
        // For phone, convert scientific notation (Excel format like "9.27E+11")
        String phone = cleanValue(row[phoneIndex]);
        phone = _convertScientificNotation(phone);
        final dateStr = cleanValue(row[dateIndex]);
        final timeStr = cleanValue(row[timeIndex]);

        // Check all required fields and skip if ANY is missing
        final missingFields = <String>[];
        if (name.isEmpty) missingFields.add('Patient Name');
        if (phone.isEmpty) missingFields.add('Phone');
        if (dateStr.isEmpty) missingFields.add('Appt Date');
        if (timeStr.isEmpty) missingFields.add('Appt Time');

        if (missingFields.isNotEmpty) {
          errorLogs.add('Row ${rowIndex + 2}: Missing ${missingFields.join(', ')}');
          continue;
        }

        // Validate date format
        try {
          _parseDate(dateStr);
        } catch (e) {
          errorLogs.add('Row ${rowIndex + 2}: Invalid date format - "$dateStr"');
          continue;
        }

        // Validate time format (should contain ':' or be in valid time format)
        if (!timeStr.contains(':') && 
            !timeStr.toUpperCase().contains('AM') && 
            !timeStr.toUpperCase().contains('PM')) {
          errorLogs.add('Row ${rowIndex + 2}: Invalid time format - "$timeStr"');
          continue;
        }

        validRows.add({
          'name': name,
          'phone': phone,
          'date': dateStr,
          'time': timeStr,
        });
      }

      if (validRows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No valid rows found. Skipped ${errorLogs.length} rows with missing data.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check if exceeds 500 rows limit
      if (validRows.length > 500) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: CSV contains more than 500 rows. Please split into smaller files.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Upload to Firestore using WriteBatch
      final firestore = FirebaseFirestore.instance;
      int successCount = 0;

      // Process in batches of 500 (Firestore limit)
      for (int i = 0; i < validRows.length; i += 500) {
        final batch = firestore.batch();
        final batchRows = validRows.skip(i).take(500).toList();

        for (int rowIndex = 0; rowIndex < batchRows.length; rowIndex++) {
          final row = batchRows[rowIndex];
          try {
            // Validate patientName and phoneNumber are not empty
            // Clean phone number - remove quotes and normalize
            String cleanPhone(String? phone) {
              if (phone == null) return '';
              String cleaned = phone.trim();
              cleaned = cleaned.replaceAll(RegExp(r"^'"), '').replaceAll(RegExp(r"'$"), '');
              cleaned = cleaned.replaceAll(RegExp(r'^"'), '').replaceAll(RegExp(r'"$'), '');
              // Convert scientific notation (Excel format like "9.27E+11") to regular number
              cleaned = _convertScientificNotation(cleaned);
              return cleaned.trim();
            }
            
            final patientName = (row['name']?.toString() ?? '').trim();
            final rawPhoneNumber = cleanPhone(row['phone']?.toString());

            if (patientName.isEmpty || rawPhoneNumber.isEmpty) {
              errorLogs.add('Row ${i + rowIndex + 2}: Missing patient name or phone number');
              continue;
            }

            // Format phone number to E.164 format (Twilio-acceptable format with + sign)
            // This ensures the number is in the correct format for Twilio SMS sending
            final phoneNumber = _formatPhoneToE164(rawPhoneNumber);
            
            // Log phone number formatting for debugging
            if (rawPhoneNumber != phoneNumber) {
              print('📞 Phone formatted: "$rawPhoneNumber" -> "$phoneNumber"');
            }
            
            // Validate that the formatted phone number has a + sign (E.164 format)
            // If formatting failed, try to add + prefix as fallback
            String finalPhoneNumber = phoneNumber;
            if (!phoneNumber.startsWith('+')) {
              // Try to add + prefix if it looks like a valid number
              if (phoneNumber.length >= 10 && phoneNumber.length <= 15) {
                finalPhoneNumber = '+' + phoneNumber;
                print('⚠️ Warning: Phone number "$rawPhoneNumber" was not formatted correctly. Added + prefix: "$finalPhoneNumber"');
              } else {
                errorLogs.add('Row ${i + rowIndex + 2}: Phone number "$rawPhoneNumber" could not be formatted to E.164 format (invalid format)');
                print('⚠️ Warning: Phone number "$rawPhoneNumber" was not formatted correctly. Result: "$phoneNumber"');
                // Continue anyway - the number might still work, but log the warning
                finalPhoneNumber = phoneNumber; // Use original formatted value
              }
            }

            // Parse and format date
            DateTime? parsedDate;
            try {
              // Try to parse date in various formats
              final originalDateStr = row['date']!;
              parsedDate = _parseDate(originalDateStr);
              
              // Validate parsed date - ensure year is reasonable (2000-2100)
              if (parsedDate.year < 2000 || parsedDate.year > 2100) {
                errorLogs.add('Row ${i + rowIndex + 2}: Invalid year in date - "$originalDateStr" (parsed as year ${parsedDate.year})');
                print('❌ Invalid year: $originalDateStr -> ${parsedDate.year}');
                continue;
              }
              
              // Additional validation: Check if date seems reasonable (not too far in future/past)
              final now = DateTime.now();
              final daysDifference = parsedDate.difference(now).inDays;
              if (daysDifference < -365 || daysDifference > 365) {
                print('⚠️ Warning: Date "$originalDateStr" is ${daysDifference.abs()} days ${daysDifference < 0 ? "in the past" : "in the future"}');
              }
              
            } catch (e) {
              errorLogs.add('Row ${i + rowIndex + 2}: Invalid date format - "${row['date']}" (Error: $e)');
              print('❌ Date parsing error for "${row['date']}": $e');
              continue;
            }

            // Format date as 'dd-MM-yyyy' - CRITICAL: Must be this format
            final formattedDate = Date_Utils.formatDate(parsedDate);
            
            // CRITICAL VALIDATION: Ensure the formatted date matches what we expect
            // If parsedDate is Jan 3, 2026, formattedDate should be "03-01-2026"
            // If we see "03-07-2031", something went wrong in parsing
            final expectedMonth = parsedDate.month;
            final expectedYear = parsedDate.year;
            final formattedParts = formattedDate.split('-');
            if (formattedParts.length == 3) {
              final formattedMonth = int.tryParse(formattedParts[1]);
              final formattedYear = int.tryParse(formattedParts[2]);
              if (formattedMonth != expectedMonth || formattedYear != expectedYear) {
                errorLogs.add('Row ${i + rowIndex + 2}: Date parsing mismatch - parsed as ${parsedDate.day}/${parsedDate.month}/${parsedDate.year} but formatted as "$formattedDate"');
                print('❌ Date mismatch: Parsed ${parsedDate.day}/${parsedDate.month}/${parsedDate.year} but formatted as "$formattedDate"');
                continue;
              }
            }
            
            // Validate formatted date format and year
            if (!formattedDate.contains('-') || formattedDate.split('-').length != 3) {
              errorLogs.add('Row ${i + rowIndex + 2}: Date formatting error - got "$formattedDate"');
              continue;
            }
            
            // Verify the formatted date has correct year (not 2031, 0026, etc.)
            final dateParts = formattedDate.split('-');
            if (dateParts.length == 3) {
              final year = int.tryParse(dateParts[2]);
              if (year == null || year < 2000 || year > 2100) {
                errorLogs.add('Row ${i + rowIndex + 2}: Invalid year in formatted date - "$formattedDate"');
                print('❌ Invalid formatted date year: $formattedDate');
                continue;
              }
            }
            
            print('✅ Date validated: "$formattedDate" (parsed from "${row['date']}")');

            // Format time - ensure it's in 'HH:mm' or 'hh:mm a' format
            String formattedTime = row['time']!.trim();
            // If time doesn't have AM/PM, assume 24-hour format
            if (!formattedTime.toUpperCase().contains('AM') && 
                !formattedTime.toUpperCase().contains('PM')) {
              // Already in 24-hour format, use as is
              if (!formattedTime.contains(':')) {
                errorLogs.add('Row ${i + rowIndex + 2}: Invalid time format - ${row['time']}');
                continue;
              }
            }

            // Generate unique document ID
            final docId = 'csv-${DateTime.now().millisecondsSinceEpoch}-${successCount}';

            // Create appointment document
            final appointmentRef = firestore.collection('Appointments').doc(docId);
            
            // Debug: Print appointment data before saving
            print('Saving appointment: $patientName, Date: $formattedDate, Time: $formattedTime, Status: active');
            print('Parsed date: $parsedDate, Formatted date: $formattedDate');
            print('Phone: "$rawPhoneNumber" -> "$finalPhoneNumber" (E.164 format)');
            
            // Ensure all required fields are set correctly
            // CRITICAL: status field MUST be present and exactly 'active' (lowercase)
            final appointmentData = <String, dynamic>{
              'patientID': 'csv-import-${DateTime.now().millisecondsSinceEpoch}-$successCount',
              'name': patientName,
              'phone': finalPhoneNumber, // Use finalPhoneNumber (with + prefix if needed)
              'date': formattedDate, // Must be in 'dd-MM-yyyy' format (e.g., "10-01-2026")
              'time': formattedTime, // Can be 'HH:mm' or 'hh:mm a' format
              'status': 'active', // CRITICAL: Must be lowercase 'active' to match dashboard query
              'isPriority': false,
              'reallocationStatus': 'Original',
              'createdAt': FieldValue.serverTimestamp(),
              'email': '', // Empty email for CSV imports
              'address': '', // Empty address for CSV imports
              'hospital': '', // Empty hospital for CSV imports
              'userResponse': null, // No response yet
            };
            
            // Validate critical fields before saving
            if (appointmentData['status'] != 'active') {
              errorLogs.add('Row ${i + rowIndex + 2}: Status validation failed - ${appointmentData['status']}');
              continue;
            }
            
            if (!formattedDate.contains('-') || formattedDate.split('-')[2].length != 4) {
              errorLogs.add('Row ${i + rowIndex + 2}: Date format validation failed - $formattedDate');
              continue;
            }
            
            print('✅ Saving appointment: $patientName');
            print('   Date: $formattedDate (parsed from: ${row['date']})');
            print('   Time: $formattedTime');
            print('   Status: ${appointmentData['status']}');
            print('   Full data: $appointmentData');
            
            // Use set with merge: false to ensure all fields are set
            batch.set(appointmentRef, appointmentData, SetOptions(merge: false));
            
            print('Appointment document created with ID: $docId');

            // Only increment successCount if both name and phone are not empty
            if (patientName.isNotEmpty && finalPhoneNumber.isNotEmpty) {
              successCount++;
            }
          } catch (e) {
            errorLogs.add('Row ${i + rowIndex + 2}: Processing error - $e');
            print('Error processing row: $e');
          }
        }

        // Commit batch
        try {
          await batch.commit();
          print('✅ Batch committed successfully');
          
          // Verify a sample document was saved correctly
          if (batchRows.isNotEmpty) {
            final sampleDocId = 'csv-${DateTime.now().millisecondsSinceEpoch}-${successCount - 1}';
            final verifyDoc = await firestore.collection('Appointments').doc(sampleDocId).get();
            if (verifyDoc.exists) {
              final data = verifyDoc.data();
              print('✅ Verification - Sample document exists');
              print('   Status field: ${data?['status']}');
              print('   Date field: ${data?['date']}');
              if (data?['status'] != 'active') {
                print('⚠️ WARNING: Status field is missing or incorrect!');
              }
              final dateValue = data?['date'];
              if (dateValue == null || !(dateValue is String) || !dateValue.contains('-')) {
                print('⚠️ WARNING: Date field format is incorrect!');
              }
            }
          }
        } catch (e) {
          print('❌ Batch commit error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error uploading batch: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // Show success dialog after batch commit
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await _showImportSummaryDialog(context, totalRows, successCount, errorLogs);
      }
    } catch (e, stackTrace) {
      // Log full error details for debugging
      print('❌ CSV Import Error: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Provide user-friendly error message
        String errorMessage = 'Error importing CSV';
        if (e.toString().contains('LateInitializationError')) {
          errorMessage = 'Error: File picker initialization failed. Please try again or use a different browser.';
        } else if (e.toString().contains('has not been initialized')) {
          errorMessage = 'Error: File reading failed. Please ensure the file is a valid CSV and try again.';
        } else {
          errorMessage = 'Error importing CSV: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                // Show detailed error in console (for debugging)
                print('Full error details: $e\n$stackTrace');
              },
            ),
          ),
        );
      }
    }
  }

  /// Find column index by name (case-insensitive, flexible matching)
  int? _findColumnIndex(List<String> headers, List<String> possibleNames) {
    // Normalize a string for comparison
    String normalize(String str) {
      return str
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r"[''""]"), '') // Remove all quote types
          .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
          .trim();
    }
    
    for (var name in possibleNames) {
      final normalizedName = normalize(name);
      for (int i = 0; i < headers.length; i++) {
        final normalizedHeader = normalize(headers[i]);
        
        // Try exact match first
        if (normalizedHeader == normalizedName) {
          print('Matched "$name" to header "${headers[i]}" at index $i');
          return i;
        }
        // Try contains match (more flexible) - but only if both are substantial
        if (normalizedName.length >= 3 && normalizedHeader.length >= 3) {
          if (normalizedHeader.contains(normalizedName) || 
              normalizedName.contains(normalizedHeader)) {
            print('Matched "$name" to header "${headers[i]}" at index $i (contains match)');
            return i;
          }
        }
      }
    }
    print('Could not find column matching: ${possibleNames.join(', ')}');
    return null;
  }

  /// Parse date from various formats
  DateTime _parseDate(String dateStr) {
    // Clean the date string
    String cleanedDate = dateStr.trim();
    
    print('Parsing date: "$dateStr" (cleaned: "$cleanedDate")');
    
    // PRIORITY 1: Try formats with month names first (most reliable)
    // These formats are unambiguous and should be tried first
    final monthNameFormats = [
      'dd MMMM yyyy', // "10 January 2026" - FULL month name with spaces
      'd MMMM yyyy',  // "3 January 2026" (single digit day)
      'dd-MMMM-yyyy', // "10-January-2026" - FULL month name with dashes ⭐ NEW
      'd-MMMM-yyyy',  // "3-January-2026" (single digit day with dashes) ⭐ NEW
      'dd MMM yyyy',  // "10 Jan 2026" - SHORT month name with spaces
      'd MMM yyyy',   // "3 Jan 2026" (single digit day)
      'dd-MMM-yyyy',  // "10-Jan-2026" - SHORT month name with dashes ⭐ NEW
      'd-MMM-yyyy',   // "3-Jan-2026" (single digit day with dashes) ⭐ NEW
    ];
    
    for (var format in monthNameFormats) {
      try {
        final formatter = DateFormat(format, 'en_US'); // Use English locale for month names
        final parsed = formatter.parse(cleanedDate);
        
        // Validate year is reasonable
        if (parsed.year >= 2000 && parsed.year <= 2100) {
          print('✅ Parsed with format "$format": $parsed (${parsed.day}/${parsed.month}/${parsed.year})');
          return parsed;
        } else {
          print('⚠️ Parsed year ${parsed.year} is outside valid range (2000-2100)');
        }
      } catch (e) {
        // Continue to next format
        continue;
      }
    }
    
    // PRIORITY 2: Try unambiguous numeric formats (ISO format first)
    final numericFormats = [
      'yyyy-MM-dd',   // "2026-01-03" - ISO format (unambiguous)
      'yyyy/MM/dd',   // "2026/01/03" - ISO with slashes
      'dd-MM-yyyy',   // "03-01-2026" - DD-MM-YYYY (European format)
      'dd/MM/yyyy',   // "03/01/2026" - DD/MM/YYYY
    ];
    
    for (var format in numericFormats) {
      try {
        final formatter = DateFormat(format);
        final parsed = formatter.parse(cleanedDate);
        
        // Validate year is reasonable
        if (parsed.year >= 2000 && parsed.year <= 2100) {
          print('✅ Parsed with format "$format": $parsed (${parsed.day}/${parsed.month}/${parsed.year})');
          return parsed;
        }
      } catch (e) {
        continue;
      }
    }
    
    // PRIORITY 3: Try ambiguous US formats (MM-DD-YYYY) - LAST RESORT
    // These are ambiguous and should only be tried if nothing else works
    final ambiguousFormats = [
      'MM-dd-yyyy',   // "01-03-2026" - Could be Jan 3 or March 1
      'MM/dd/yyyy',   // "01/03/2026"
    ];
    
    for (var format in ambiguousFormats) {
      try {
        final formatter = DateFormat(format);
        final parsed = formatter.parse(cleanedDate);
        
        // Validate year is reasonable
        if (parsed.year >= 2000 && parsed.year <= 2100) {
          print('⚠️ Parsed with ambiguous format "$format": $parsed (${parsed.day}/${parsed.month}/${parsed.year})');
          return parsed;
        }
      } catch (e) {
        continue;
      }
    }

    // If all formats fail, try parsing as ISO string
    try {
      final parsed = DateTime.parse(cleanedDate);
      if (parsed.year >= 2000 && parsed.year <= 2100) {
        print('✅ Parsed as ISO string: $parsed');
        return parsed;
      }
    } catch (e) {
      // Continue to throw error
    }
    
    throw FormatException('Unable to parse date: $dateStr (cleaned: $cleanedDate). Please use formats like "03 January 2026" or "03-01-2026"');
  }

  /// Show import summary dialog
  Future<void> _showImportSummaryDialog(
    BuildContext context,
    int totalRows,
    int successCount,
    List<String> errorLogs,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 600,
                maxWidth: 500,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Title with icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Import Summary',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Summary content - scrollable if there are many errors
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Processed $totalRows records.',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Successfully added $successCount appointments.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (errorLogs.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange[200]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.orange[700],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Skipped ${errorLogs.length} records:',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.orange[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...errorLogs.take(10).map((error) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• $error',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.orange[900],
                                    ),
                                  ),
                                )),
                                if (errorLogs.length > 10)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '... and ${errorLogs.length - 10} more',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange[700],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Done button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Get current filtered appointments for printing
  /// Uses the EXACT same date range logic as the dashboard's _filterAppointmentsByDateRange
  /// This ensures print output matches what's displayed on the dashboard
  Future<List<AppointmentData>> _getCurrentFilteredAppointments() async {
    try {
      // Get current snapshot
      final snapshot = await _getTodayAppointments().first;
      
      // Convert to AppointmentData objects
      final allAppointments = <AppointmentData>[];
      for (var doc in snapshot.docs) {
        try {
          final apt = AppointmentData.fromFirestore(doc);
          allAppointments.add(apt);
        } catch (e) {
          print('Error parsing appointment ${doc.id}: $e');
        }
      }
      
      // Use the EXACT same date range filter as the dashboard
      // This calls _filterAppointmentsByDateRange which uses:
      // - startDate = DateTime(now.year, now.month, now.day) (today at 00:00:00)
      // - endDate = startDate.add(Duration(days: 30)) (30 days from today)
      // - Includes cancelled appointments from past 7 days
      var filtered = _filterAppointmentsByDateRange(allAppointments);
      
      // Apply search filter if active (same as dashboard)
      if (_searchController.text.isNotEmpty) {
        filtered = _applySearchFilter(filtered, _searchCategory, _searchController.text);
      }
      
      // Sort by appointment time (same as dashboard)
      filtered.sort((a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));
      
      return filtered;
    } catch (e) {
      print('Error getting filtered appointments: $e');
      return [];
    }
  }

  /// Print schedule with current filtered appointments
  /// Uses PDF generation with proper date range filtering
  Future<void> _printSchedule(BuildContext context) async {
    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 16),
                Text('Generating PDF...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // Get current filtered appointments (with date range and search filters)
      final appointments = await _getCurrentFilteredAppointments();

      // Get date range for header
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day);
      final endDate = startDate.add(const Duration(days: 30));
      final startDateStr = DateFormat('MMM dd, yyyy').format(startDate);
      final endDateStr = DateFormat('MMM dd, yyyy').format(endDate);

      if (appointments.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _searchController.text.isNotEmpty
                    ? 'No appointments found matching your search'
                    : 'No appointments found for this date range ($startDateStr to $endDateStr)',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Generate PDF document
      final pdf = await _generatePDF(appointments, startDateStr, endDateStr);

      // Show print dialog with proper error handling
      try {
        // On web, use sharePdf (downloads PDF) instead of layoutPdf (which fails)
        if (kIsWeb) {
          await Printing.sharePdf(
            bytes: pdf,
            filename: 'appointment-schedule.pdf',
          );
        } else {
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdf,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF generated: ${appointments.length} appointment(s)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } on MissingPluginException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Printer Initialization Required'),
              content: const Text(
                'System restart required to initialize printer drivers.\n\n'
                'Please restart the application and try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        print('MissingPluginException: $e');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening print dialog: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        print('Error opening print dialog: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error printing schedule: $e');
    }
  }

  /// Generate PDF document for printing
  /// Uses Unicode-compliant fonts to avoid Helvetica warnings
  Future<Uint8List> _generatePDF(
    List<AppointmentData> appointments,
    String startDateStr,
    String endDateStr,
  ) async {
    // The pdf package's default fonts support Unicode
    // We'll use the default theme which handles Unicode properly
    final pdf = pw.Document();

    // Build table data
    final tableData = <List<String>>[];
    
    // Header row
    tableData.add(['#', 'Patient Name', 'Date & Time', 'Phone', 'Status']);
    
    // Data rows
    for (int i = 0; i < appointments.length; i++) {
      final apt = appointments[i];
      tableData.add([
        '${i + 1}',
        apt.name,
        '${apt.ukFormattedDate} @ ${apt.formattedTime}',
        apt.phone,
        apt.status,
      ]);
    }

    // Build PDF with Unicode-compliant theme
    // Explicitly set theme to use Helvetica (supports Unicode) and avoid warnings
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(), // Helvetica supports Unicode characters
          bold: pw.Font.helveticaBold(), // Bold variant for headers
        ),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Aafia Clinic - Appointment Schedule',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue,
                  ),
                ),
                pw.Text(
                  DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.now()),
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 20),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) => [
          // Title and date range
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Date Range: $startDateStr to $endDateStr',
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
                if (_searchController.text.isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Filtered by: $_searchCategory = "${_searchController.text}"',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
                pw.SizedBox(height: 5),
                pw.Text(
                  'Total Appointments: ${appointments.length}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(2.0),
              2: const pw.FlexColumnWidth(2.0),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.0),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue100),
                children: tableData[0].map((header) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      header,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  );
                }).toList(),
              ),
              // Data rows
              ...tableData.skip(1).map((row) {
                return pw.TableRow(
                  children: row.asMap().entries.map((entry) {
                    final index = entry.key;
                    final value = entry.value;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        value,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: index == 4 // Status column
                              ? (value.toLowerCase() == 'active'
                                  ? PdfColors.green700
                                  : value.toLowerCase() == 'cancelled'
                                      ? PdfColors.red700
                                      : PdfColors.black)
                              : PdfColors.black,
                        ),
                      ),
                    );
                  }).toList(),
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Generate HTML content for printing (DEPRECATED - no longer used, PDF is used instead)
  @Deprecated('Use _generatePDF instead')
  String _generatePrintHTML(List<AppointmentData> appointments) {
    final buffer = StringBuffer();
    
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html>');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln('<title>Appointment Schedule</title>');
    buffer.writeln('<style>');
    buffer.writeln('''
      @media print {
        @page { margin: 1cm; }
        body { margin: 0; }
      }
      body {
        font-family: Arial, sans-serif;
        margin: 20px;
        color: #333;
      }
      h1 {
        color: #1976D2;
        border-bottom: 2px solid #1976D2;
        padding-bottom: 10px;
        margin-bottom: 20px;
      }
      .info {
        margin-bottom: 20px;
        color: #666;
        font-size: 14px;
      }
      table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 20px;
      }
      th {
        background-color: #1976D2;
        color: white;
        padding: 12px;
        text-align: left;
        font-weight: bold;
      }
      td {
        padding: 10px;
        border-bottom: 1px solid #ddd;
      }
      tr:nth-child(even) {
        background-color: #f5f5f5;
      }
      tr:hover {
        background-color: #e3f2fd;
      }
      .status-active {
        color: green;
        font-weight: bold;
      }
      .status-cancelled {
        color: red;
        font-weight: bold;
      }
    ''');
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    
    // Header
    buffer.writeln('<h1>Appointment Schedule</h1>');
    buffer.writeln('<div class="info">');
    buffer.writeln('Generated: ${DateFormat('MMMM dd, yyyy - hh:mm a').format(DateTime.now())}<br>');
    buffer.writeln('Total Appointments: ${appointments.length}');
    if (_searchController.text.isNotEmpty) {
      buffer.writeln('<br>Filtered by: $_searchCategory = "${_searchController.text}"');
    }
    buffer.writeln('</div>');
    
    // Table
    buffer.writeln('<table>');
    buffer.writeln('<thead>');
    buffer.writeln('<tr>');
    buffer.writeln('<th>#</th>');
    buffer.writeln('<th>Patient Name</th>');
    buffer.writeln('<th>Date & Time</th>');
    buffer.writeln('<th>Phone</th>');
    buffer.writeln('<th>Status</th>');
    buffer.writeln('</tr>');
    buffer.writeln('</thead>');
    buffer.writeln('<tbody>');
    
    for (int i = 0; i < appointments.length; i++) {
      final apt = appointments[i];
      final statusClass = apt.status.toLowerCase() == 'active' 
          ? 'status-active' 
          : apt.status.toLowerCase() == 'cancelled' 
              ? 'status-cancelled' 
              : '';
      
      buffer.writeln('<tr>');
      buffer.writeln('<td>${i + 1}</td>');
      buffer.writeln('<td>${apt.name}</td>');
      buffer.writeln('<td>${apt.ukFormattedDate} @ ${apt.formattedTime}</td>');
      buffer.writeln('<td>${apt.phone}</td>');
      buffer.writeln('<td class="$statusClass">${apt.status}</td>');
      buffer.writeln('</tr>');
    }
    
    buffer.writeln('</tbody>');
    buffer.writeln('</table>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');
    
    return buffer.toString();
  }

  /// Show reallocation performance chart dialog
  Future<void> _showReallocationChart(BuildContext context) async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Fetch reallocation data for last 7 days
      final chartData = await _fetchReallocationData();

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Show chart dialog
      await showDialog(
        context: context,
        builder: (ctx) => _ReallocationChartDialog(chartData: chartData),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Close loading dialog
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading chart data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Fetch reallocation data from Firestore for the last 7 days
  /// Returns a map of day names to reallocation counts
  /// Groups by the day of week when the reallocation happened (based on updatedAt/createdAt)
  Future<Map<String, int>> _fetchReallocationData() async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    
    // Query appointments with reallocationStatus == 'Reallocated'
    final querySnapshot = await FirebaseFirestore.instance
        .collection('Appointments')
        .where('reallocationStatus', isEqualTo: 'Reallocated')
        .get();

    // Initialize day counts for last 7 days
    final dayCounts = <String, int>{
      'Mon': 0,
      'Tue': 0,
      'Wed': 0,
      'Thu': 0,
      'Fri': 0,
      'Sat': 0,
      'Sun': 0,
    };

    // Process each document
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      final updatedAt = data['updatedAt'] as Timestamp?;
      
      // Use updatedAt if available (when reallocation happened), otherwise createdAt
      DateTime? reallocationDate;
      if (updatedAt != null) {
        reallocationDate = updatedAt.toDate();
      } else if (createdAt != null) {
        reallocationDate = createdAt.toDate();
      }

      if (reallocationDate == null) continue;

      // Check if reallocation happened within last 7 days
      if (reallocationDate.isAfter(sevenDaysAgo) && 
          reallocationDate.isBefore(now.add(const Duration(days: 1)))) {
        // Get day of week (1 = Monday, 7 = Sunday)
        final dayOfWeek = reallocationDate.weekday;
        
        // Map to day name
        final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final dayName = dayNames[dayOfWeek - 1]; // Convert 1-7 to 0-6 index
        
        dayCounts[dayName] = (dayCounts[dayName] ?? 0) + 1;
      }
    }

    return dayCounts;
  }

  /// Show QR code for mobile booking
  Future<void> _showQrDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Scan to Book Appointment',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: 'https://aafia-myappointment.web.app/#/book',
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Point your phone camera here to open the mobile booking form.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Reallocation Performance Chart Dialog
class _ReallocationChartDialog extends StatelessWidget {
  final Map<String, int> chartData;

  const _ReallocationChartDialog({required this.chartData});

  @override
  Widget build(BuildContext context) {
    // Calculate total reallocations
    final totalReallocations = chartData.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );

    // Prepare bar chart data
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final barGroups = dayNames.map((day) {
      final value = chartData[day] ?? 0;
      return BarChartGroupData(
        x: dayNames.indexOf(day),
        barRods: [
          BarChartRodData(
            toY: value.toDouble(),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1976D2), // Blue
                Color(0xFF42A5F5), // Light blue
              ],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 20,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 700,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Reallocation Performance (Last 7 Days)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Chart
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (chartData.values.isEmpty
                          ? 1
                          : chartData.values.reduce((a, b) => a > b ? a : b)) +
                      2.0, // Add padding at top
                  minY: 0,
                  barGroups: barGroups,
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < dayNames.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                dayNames[value.toInt()],
                                style: const TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.min || value == meta.max) {
                            return const Text('');
                          }
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: const Color(0xFFE0E0E0),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Summary footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF1976D2).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF1976D2),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The system has successfully saved $totalReallocations appointment${totalReallocations != 1 ? 's' : ''} this week.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Close button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
