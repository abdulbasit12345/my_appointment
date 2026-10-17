import 'package:flutter/material.dart';

/// Show Quick Actions Menu (SMS Templates)
/// Uses the button's BuildContext to get position and anchor the menu beneath the button
///
/// Returns the menu's future (the selected template value), or null when the
/// button has no render box (nothing is shown in that case).
Future<String?>? showQuickActionsMenu(
  BuildContext buttonContext,
  BuildContext overlayContext,
) {
  final RenderBox? buttonBox = buttonContext.findRenderObject() as RenderBox?;
  if (buttonBox == null) return null;

  final Offset offset = buttonBox.localToGlobal(Offset.zero);
  final Size size = buttonBox.size;
  const double menuGap = 4.0;
  final double menuTop = offset.dy + size.height + menuGap;
  final RelativeRect position = RelativeRect.fromLTRB(
    offset.dx,
    menuTop,
    0.0,
    0.0,
  );

  return showMenu<String>(
    context: overlayContext,
    position: position,
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
  );
}
