import 'package:flutter/material.dart';

/// Reusable status badge widget with color coding
/// Matches the web dashboard design
class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String displayText;

    switch (status.toLowerCase()) {
      case 'active':
        backgroundColor = Colors.green;
        textColor = Colors.white;
        displayText = 'Active';
        break;
      case 'cancelled':
        backgroundColor = Colors.red;
        textColor = Colors.white;
        displayText = 'Cancelled';
        break;
      case 'no response':
        backgroundColor = Colors.orange;
        textColor = Colors.white;
        displayText = 'No Response';
        break;
      default:
        backgroundColor = Colors.grey;
        textColor = Colors.white;
        displayText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

