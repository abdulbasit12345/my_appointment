import 'package:flutter/material.dart';

import '../../../models/appointment_data.dart';
import 'appointment_badges.dart';
import 'appointment_cards.dart' show AppointmentContextCallback, QuickActionsCallback;
import 'reminder_button_style.dart';

/// Build appointment table for large screens
class AppointmentTable extends StatelessWidget {
  final List<AppointmentData> appointments;
  final BoxConstraints constraints;

  /// Edit button: receives the BuildContext of the row/card it was built in.
  final AppointmentContextCallback onEdit;

  /// Quick SMS actions (bolt) button: receives the button's own context (for
  /// menu positioning) and the row/card context (for the overlay).
  final QuickActionsCallback onQuickActions;

  /// Send Appointment Reminder button.
  final ValueChanged<AppointmentData> onSendReminder;

  /// Owned (and disposed) by the dashboard State.
  final ScrollController horizontalScrollController;
  final ScrollController verticalScrollController;

  const AppointmentTable({
    super.key,
    required this.appointments,
    required this.constraints,
    required this.onEdit,
    required this.onQuickActions,
    required this.onSendReminder,
    required this.horizontalScrollController,
    required this.verticalScrollController,
  });

  @override
  Widget build(BuildContext context) {
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
        final actualTableWidth = minTableWidth > tableConstraints.maxWidth
            ? minTableWidth
            : tableConstraints.maxWidth;

        final dataTable = DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey[50]!),
          headingRowHeight: 60.0,
          dataRowMinHeight: 65.0,
          dataRowMaxHeight: 75.0,
          dataRowColor: MaterialStateProperty.resolveWith<Color?>((Set<MaterialState> states) => states.contains(MaterialState.hovered) ? Colors.blue.withOpacity(0.05) : null),
          columnSpacing: columnSpacing,
          columns: [
            DataColumn(label: Text('Patient Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('Appt Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('User Response', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('Reallocation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('New User', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('Moved', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
            DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: headingFontSize, color: Color(0xFF1A1A1A)))),
          ],
          rows: appointments.map((appointment) {
            return DataRow(
              cells: [
                DataCell(Text(appointment.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.blueGrey[900]), maxLines: 2, overflow: TextOverflow.ellipsis)),
                DataCell(Text(appointment.ukFormattedDate + ' @ ' + appointment.formattedTime, style: TextStyle(fontSize: cellFontSize, color: Color(0xFF333333)), maxLines: 2, overflow: TextOverflow.ellipsis)),
                DataCell(Text(appointment.phone, style: TextStyle(fontSize: cellFontSize, color: Color(0xFF333333)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                DataCell(ApptStatusBadge(status: appointment.status, userResponse: appointment.userResponse, isSmallScreen: isVerySmallTable)),
                DataCell(UserResponseBadge(response: appointment.userResponseDisplay, isSmallScreen: isVerySmallTable)),
                DataCell(ReallocationBadge(status: appointment.reallocationStatusDisplay, isSmallScreen: isVerySmallTable)),
                DataCell(Container(constraints: BoxConstraints(maxWidth: 180, minWidth: 150), child: Tooltip(message: appointment.newUserNameDisplay, child: Text(appointment.newUserNameDisplayCompact, style: TextStyle(fontSize: cellFontSize - 1, color: appointment.newUserName != null ? Color(0xFF1976D2) : Color(0xFF999999), fontWeight: appointment.newUserName != null ? FontWeight.w500 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)))),
                DataCell(Text(appointment.daysMovedDisplay, style: TextStyle(fontSize: cellFontSize, color: appointment.daysMoved != null && appointment.daysMoved! > 0 ? Colors.green[700] : Color(0xFF999999), fontWeight: appointment.daysMoved != null && appointment.daysMoved! > 0 ? FontWeight.w600 : FontWeight.normal))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => onEdit(context, appointment),
                        icon: Icon(Icons.edit, size: isVerySmallTable ? 16 : isSmallTable ? 18 : 20, color: Color(0xFF1976D2)),
                        tooltip: 'Edit Appointment',
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(minWidth: isVerySmallTable ? 28 : 32, minHeight: isVerySmallTable ? 28 : 32),
                      ),
                      SizedBox(width: isVerySmallTable ? 4 : 6),
                      Builder(builder: (buttonContext) {
                        return IconButton(
                          onPressed: isQuickActionsEnabled(appointment) ? () => onQuickActions(buttonContext, context, appointment) : null,
                          icon: Icon(Icons.bolt, size: isVerySmallTable ? 16 : isSmallTable ? 18 : 20, color: isQuickActionsEnabled(appointment) ? Colors.amber : Colors.grey),
                          tooltip: 'Quick SMS Actions',
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(minWidth: isVerySmallTable ? 28 : 32, minHeight: isVerySmallTable ? 28 : 32),
                        );
                      }),
                      SizedBox(width: isVerySmallTable ? 4 : 6),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: isVerySmallTable ? 70 : isSmallTable ? 80 : 90, maxWidth: double.infinity),
                          child: Tooltip(
                            message: 'Send Appointment Reminder',
                            child: ElevatedButton.icon(
                              onPressed: isReminderButtonEnabled(appointment) ? () => onSendReminder(appointment) : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: reminderButtonColor(appointment),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: Colors.grey[400],
                                disabledForegroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: isVerySmallTable ? 8 : isSmallTable ? 10 : 12, vertical: isVerySmallTable ? 6 : isSmallTable ? 7 : 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 2,
                                minimumSize: Size(isVerySmallTable ? 70 : isSmallTable ? 80 : 90, isVerySmallTable ? 32 : isSmallTable ? 34 : 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.standard,
                              ),
                              icon: Icon(reminderButtonIcon(appointment), size: isVerySmallTable ? 12 : isSmallTable ? 13 : 14),
                              label: Text(reminderButtonText(appointment), style: TextStyle(fontSize: isVerySmallTable ? 9 : isSmallTable ? 10 : 11, fontWeight: FontWeight.w600, letterSpacing: 0.1)),
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

        return Scrollbar(
          thumbVisibility: true,
          interactive: true,
          controller: horizontalScrollController,
          thickness: 12.0,
          radius: const Radius.circular(6),
          child: SingleChildScrollView(
            controller: horizontalScrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: actualTableWidth),
              child: Scrollbar(
                thumbVisibility: true,
                interactive: true,
                controller: verticalScrollController,
                thickness: 12.0,
                radius: const Radius.circular(6),
                child: SingleChildScrollView(
                  controller: verticalScrollController,
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
}
