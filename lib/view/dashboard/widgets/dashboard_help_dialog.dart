import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appointment_badges.dart';

/// Sections of the "How to use" guide, in tab order.
enum DashboardHelpSection {
  start,
  list,
  labels,
  buttons,
  addAndPrint,
  rightPanel,
  questions,
}

const String _seenKey = 'dashboard_help_seen_v1';

/// Opens the guide automatically the first time this browser opens the
/// dashboard. Does nothing if it was shown before (or storage is unavailable).
Future<void> showDashboardHelpOnFirstVisit(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return;
    await prefs.setBool(_seenKey, true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await showDashboardHelp(context);
}

/// The "How to use" guide.
Future<void> showDashboardHelp(
  BuildContext context, {
  DashboardHelpSection section = DashboardHelpSection.start,
}) {
  return showDialog(
    context: context,
    builder: (context) => _DashboardHelpDialog(initialSection: section),
  );
}

/// A small "?" button that opens the guide at [section].
class HelpIconButton extends StatelessWidget {
  final DashboardHelpSection section;
  final String tooltip;

  const HelpIconButton({
    super.key,
    required this.section,
    this.tooltip = 'How does this work?',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.help_outline, size: 20, color: Color(0xFF1976D2)),
      visualDensity: VisualDensity.compact,
      onPressed: () => showDashboardHelp(context, section: section),
    );
  }
}

class _DashboardHelpDialog extends StatelessWidget {
  final DashboardHelpSection initialSection;

  const _DashboardHelpDialog({required this.initialSection});

  static const _tabs = <(String, IconData)>[
    ('Start here', Icons.flag_outlined),
    ('Appointment list', Icons.list_alt),
    ('Labels', Icons.label_outline),
    ('Row buttons', Icons.touch_app_outlined),
    ('Add & print', Icons.add_circle_outline),
    ('Right panel', Icons.insights_outlined),
    ('Questions', Icons.help_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 8 : 40,
        vertical: isNarrow ? 16 : 32,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 860,
          maxHeight: size.height * 0.9,
        ),
        child: DefaultTabController(
          length: _tabs.length,
          initialIndex: initialSection.index,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                decoration: const BoxDecoration(
                  color: Color(0xFF1976D2),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.menu_book, color: Colors.white),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'How to use the Master Dashboard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.white,
                      tabs: [
                        for (final (label, icon) in _tabs)
                          Tab(icon: Icon(icon, size: 20), text: label),
                      ],
                    ),
                  ],
                ),
              ),
              Flexible(
                child: TabBarView(
                  children: [
                    _page(_start()),
                    _page(_list()),
                    _page(_labels()),
                    _page(_buttons()),
                    _page(_addAndPrint(context)),
                    _page(_rightPanel()),
                    _page(_questions()),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'You can open this guide again any time with the '
                        '"How to use" button at the top of the page.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _page(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        children: children,
      );

  // ---------------------------------------------------------------------------
  // Pages (short sentences, one screen each)
  // ---------------------------------------------------------------------------

  List<Widget> _start() => [
        _intro('This dashboard shows all appointments for the next 30 days. '
            'It updates by itself – no need to refresh.'),
        _heading('The page has two parts'),
        _bullet('Left', 'the appointment list and its buttons.'),
        _bullet('Right',
            'patients waiting for an earlier slot, totals and a history log.'),
        _heading('What the system does for you'),
        _step(1, 'Reminds patients',
            'An SMS goes out 48 hours before each appointment.'),
        _step(2, 'Reads their replies',
            '1 = coming,  2 = cancel,  3 = wants an earlier time.'),
        _step(3, 'Fills cancelled slots',
            'When someone cancels, patients booked later are offered the free slot in the app.'),
        _tip(
            'Not sure what something does? Hover over it, or click the ? next to a title.'),
      ];

  List<Widget> _list() => [
        _intro('Shows today up to 30 days ahead, earliest first. '
            'Cancelled appointments stay visible for 7 days.'),
        _heading('Search'),
        _para(
            'Pick Name, Phone or Date on the left of the search bar, then type. '
            'Click × to clear.'),
        _heading('Columns'),
        _term('Appt Status', 'Where the appointment stands (see Labels).'),
        _term('User Response',
            'The patient\'s SMS reply. "-" means no reply yet.'),
        _term('Reallocation',
            'Whether the patient was moved to an earlier slot.'),
        _term('New User', 'Who took a moved slot, and from/to which date.'),
        _term('Moved', 'How many days earlier the patient was seen.'),
        _term('Action', 'Buttons for that patient (see Row buttons).'),
        _tip(
            'On a phone, each appointment is shown as a card instead of a table row.'),
      ];

  List<Widget> _labels() => [
        _badgeRow(
            const ApptStatusBadge(status: 'active'), 'Booked, no reply yet.'),
        _badgeRow(
            const ApptStatusBadge(status: 'active', userResponse: 'Confirmed'),
            'Booked and confirmed.'),
        _badgeRow(const ApptStatusBadge(status: 'CONFIRMED'),
            'Patient replied 1 – coming.'),
        _badgeRow(const ApptStatusBadge(status: 'reminder_sent_awaiting_reply'),
            'Reminder sent, waiting for a reply.'),
        _badgeRow(const ApptStatusBadge(status: 'no response'),
            'No reply to the reminder. Consider calling.'),
        _badgeRow(const ApptStatusBadge(status: 'Confirmed_Priority'),
            'Patient replied 3 – wants an earlier slot, keeps this one meanwhile.'),
        _badgeRow(const ApptStatusBadge(status: 'ON_HOLD_OFFER_SENT'),
            'An earlier slot was offered, waiting for an answer.'),
        _badgeRow(const ApptStatusBadge(status: 'cancelled'),
            'Cancelled. The slot is offered to other patients.'),
        _heading('Other columns'),
        _badgeRow(const UserResponseBadge(response: 'Confirmed'),
            'Confirmed by SMS.'),
        _badgeRow(const UserResponseBadge(response: 'Cancelled'),
            'Cancelled by SMS.'),
        _badgeRow(const ReallocationBadge(status: 'Original'),
            'At its original time.'),
        _badgeRow(const ReallocationBadge(status: 'Reallocated'),
            'Moved to an earlier slot.'),
      ];

  List<Widget> _buttons() => [
        _heading('✏️  Edit'),
        _para('Change name, phone, date or time, then click "Save Changes". '
            'Phone numbers starting 03 become Pakistan (+92); 07 or 0 become UK (+44).'),
        _heading('🔔  Remind'),
        _para('Sends the reminder SMS now. The patient can reply 1, 2 or 3. '
            'The button then shows "Reminder Sent" and stays grey until they reply.'),
        _heading('⚡  Quick message'),
        _term(
            'Offer Early Slot',
            '"We have an earlier slot today at <time>. Reply 1 to claim." '
                'If they reply 1, move them with Edit.'),
        _term('Confirm Attendance',
            '"Please confirm your <time> appointment by replying 1."'),
        _term('Late Warning',
            '"We noticed you\'re a bit late. Are you still coming?"'),
        _tip('Green message = sent. Red message = not sent. '
            'SMS only works with mobile numbers, not landlines.'),
      ];

  List<Widget> _addAndPrint(BuildContext context) => [
        _heading('➕  Book Now'),
        _para('Add one appointment: name, phone, date, time. '
            'A time that is already booked can\'t be booked twice.'),
        _heading('▦  QR code'),
        _para(
            'Patients scan it with their phone to book themselves. Print it for reception.'),
        _heading('⬆  Import CSV – many appointments at once'),
        _para(
            'Make a spreadsheet with 4 columns: Patient Name, Phone, Appt Date, Appt Time. '
            'Save it as CSV, click "Import CSV" and pick the file within 30 seconds. '
            'A summary shows what was added and which rows had problems.'),
        _quote(_csvExample),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy example'),
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: _csvExample));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Example copied – paste it into a spreadsheet.'),
              ));
            },
          ),
        ),
        _heading('🖨  Print Schedule'),
        _para(
            'Makes a PDF of the list you see. Search first to print only some appointments.'),
      ];

  static const String _csvExample = 'Patient Name,Phone,Appt Date,Appt Time\n'
      'Sarah Khan,07700900123,10-01-2027,10:00 AM\n'
      'Ali Raza,03001234567,10-01-2027,02:30 PM';

  List<Widget> _rightPanel() => [
        _term('Priority Queue',
            'Patients who asked for an earlier slot (replied 3), earliest first.'),
        _term(
            'Totals',
            'Cancelled, moved to an earlier slot, and total days saved. '
                'Click "Reallocated" for a 7-day chart.'),
        _term(
            'Activity Log',
            'Everything that happened, newest first. '
                'Use the filters to narrow it, "Load More" for older entries.'),
        _heading('Log filters'),
        _term('Claims', 'Patients who took an earlier slot.'),
        _term('Cancellations', 'Cancelled appointments.'),
        _term('Cascades', 'Free slots offered to other patients.'),
        _term('Errors', 'Things that failed, e.g. an SMS not delivered.'),
        _term('Maintenance', 'Messages sent by staff from this dashboard.'),
      ];

  List<Widget> _questions() => [
        _qa(
            'How do I cancel or delete an appointment?',
            'The dashboard can\'t. The patient cancels by replying 2 to the reminder, '
                'or in the patient app. To change the time, use Edit.'),
        _qa('An appointment is missing.',
            'Only the next 30 days are shown. Check the search box is empty.'),
        _qa('A button is grey.',
            'A reminder is waiting for a reply, or the appointment is cancelled.'),
        _qa('The SMS failed.',
            'The number may be a landline. Use Edit to enter a mobile number.'),
        _qa('A row says "⚠ Invalid date".',
            'Click Edit, set the correct date and time, then "Save Changes".'),
        _qa('Some CSV rows were skipped.',
            'The summary lists them and why. Fix those rows and import them again.'),
        _qa(
            'Accepted CSV formats?',
            'Dates: 10-01-2027, 10/01/2027, 10 Jan 2027, 2027-01-10. '
                'Times: 10:00 AM, 2:30 PM, 14:30.'),
      ];

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  static Widget _intro(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
      );

  static Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1976D2),
          ),
        ),
      );

  static Widget _para(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 14, height: 1.45)),
      );

  static Widget _bullet(String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 10),
              child: Icon(Icons.circle, size: 7, color: Color(0xFF1976D2)),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$title: ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: text),
                ]),
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ),
          ],
        ),
      );

  static Widget _term(String term, String meaning) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(term,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, height: 1.45)),
            ),
            Expanded(
              child: Text(meaning,
                  style: const TextStyle(fontSize: 14, height: 1.45)),
            ),
          ],
        ),
      );

  static Widget _step(int number, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFF1976D2),
              child: Text('$number',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(text,
                      style: const TextStyle(fontSize: 14, height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      );

  static Widget _badgeRow(Widget badge, String meaning) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: Align(alignment: Alignment.centerLeft, child: badge),
            ),
            Expanded(
              child: Text(meaning,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          ],
        ),
      );

  static Widget _quote(String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5FB),
          border: const Border(
              left: BorderSide(color: Color(0xFF1976D2), width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          text,
          style: const TextStyle(
              fontSize: 13.5, height: 1.45, fontFamily: 'monospace'),
        ),
      );

  static Widget _tip(String text) => Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline,
                size: 20, color: Color(0xFFF9A825)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 14, height: 1.4))),
          ],
        ),
      );

  static Widget _qa(String question, String answer) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Q: $question',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(answer, style: const TextStyle(fontSize: 14, height: 1.45)),
          ],
        ),
      );
}
