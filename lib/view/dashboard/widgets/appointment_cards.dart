import 'package:flutter/material.dart';

import '../../../models/appointment_data.dart';
import 'appointment_badges.dart';
import 'reminder_button_style.dart';

typedef AppointmentContextCallback = void Function(
    BuildContext context, AppointmentData appointment);
typedef QuickActionsCallback = void Function(BuildContext buttonContext,
    BuildContext overlayContext, AppointmentData appointment);

/// Build appointment cards for small/medium screens
class AppointmentCards extends StatelessWidget {
  final List<AppointmentData> appointments;
  final BoxConstraints constraints;

  /// Edit button: receives the BuildContext of the row/card it was built in.
  final AppointmentContextCallback onEdit;

  /// Quick SMS actions (bolt) button: receives the button's own context (for
  /// menu positioning) and the row/card context (for the overlay).
  final QuickActionsCallback onQuickActions;

  /// Send Appointment Reminder button.
  final ValueChanged<AppointmentData> onSendReminder;

  const AppointmentCards({
    super.key,
    required this.appointments,
    required this.constraints,
    required this.onEdit,
    required this.onQuickActions,
    required this.onSendReminder,
  });

  @override
  Widget build(BuildContext context) {
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
                    ApptStatusBadge(status: appointment.status,
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
                      child: ApptStatusBadge(status: appointment.status,
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
                      child: UserResponseBadge(response: 
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
                      child: ReallocationBadge(status: 
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
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onEdit(context, appointment),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1976D2),
                          side: const BorderSide(color: Color(0xFF1976D2)),
                          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 16, vertical: isSmallScreen ? 10 : 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: Icon(Icons.edit, size: isSmallScreen ? 16 : 18),
                        label: Text('Edit', style: TextStyle(fontSize: isSmallScreen ? 12 : 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Builder(
                      builder: (buttonContext) {
                        return IconButton(
                          onPressed: isQuickActionsEnabled(appointment) ? () => onQuickActions(buttonContext, context, appointment) : null,
                          icon: const Icon(Icons.bolt),
                          color: Colors.amber,
                          tooltip: 'Quick SMS Actions',
                          iconSize: isSmallScreen ? 20 : 22,
                        );
                      },
                    ),
                    SizedBox(width: isSmallScreen ? 4 : 6),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: isSmallScreen ? 100 : 110, maxWidth: double.infinity),
                        child: Tooltip(
                          message: 'Send Appointment Reminder',
                          child: ElevatedButton.icon(
                            onPressed: isReminderButtonEnabled(appointment) ? () => onSendReminder(appointment) : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: reminderButtonColor(appointment),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[400],
                              disabledForegroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 14 : 18, vertical: isSmallScreen ? 11 : 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                              minimumSize: Size(isSmallScreen ? 100 : 110, isSmallScreen ? 40 : 44),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.standard,
                            ),
                            icon: Icon(reminderButtonIcon(appointment), size: isSmallScreen ? 16 : 18),
                            label: Text(reminderButtonText(appointment), style: TextStyle(fontSize: isSmallScreen ? 12 : 13, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
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
}
