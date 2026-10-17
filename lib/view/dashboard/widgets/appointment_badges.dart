import 'package:flutter/material.dart';

/// Status Badge Widget (for Appt Status column)
/// Format: "Appt(Active, Confirmed, Cancelled)"
class ApptStatusBadge extends StatelessWidget {
  final String status;
  final String? userResponse;
  final bool isSmallScreen;

  const ApptStatusBadge({
    super.key,
    required this.status,
    this.userResponse,
    this.isSmallScreen = false,
  });

  @override
  Widget build(BuildContext context) {
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
    } else if (statusLower == 'reminder_sent_awaiting_reply' ||
        statusLower == 'awaitingreply') {
      backgroundColor = Colors.amber;
      textColor = Colors.white;
      displayText = 'Appt(Reminder Sent)';
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
        horizontal: 12.0,
        vertical: isSmallScreen ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8.0),
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
}

/// User Response Badge Widget
class UserResponseBadge extends StatelessWidget {
  final String response;
  final bool isSmallScreen;

  const UserResponseBadge({
    super.key,
    required this.response,
    this.isSmallScreen = false,
  });

  @override
  Widget build(BuildContext context) {
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
}

/// Reallocation Status Badge Widget
class ReallocationBadge extends StatelessWidget {
  final String status;
  final bool isSmallScreen;

  const ReallocationBadge({
    super.key,
    required this.status,
    this.isSmallScreen = false,
  });

  @override
  Widget build(BuildContext context) {
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
}
