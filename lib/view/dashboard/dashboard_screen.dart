import 'package:cloud_firestore/cloud_firestore.dart' show QuerySnapshot;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/appointment_data.dart';
import '../../repositories/dashboard_repository.dart';
import 'appointment_filters.dart';
import 'latest_value_stream.dart';
import 'widgets/dashboard_help_dialog.dart';
import 'edit_appointment_dialog.dart';
import 'reallocation_chart_dialog.dart';
import 'services/csv_import_service.dart';
import 'services/dashboard_messaging_service.dart';
import 'services/schedule_print_service.dart';
import 'widgets/activity_log_panel.dart';
import 'widgets/appointment_cards.dart';
import 'widgets/appointment_table.dart';
import 'widgets/booking_qr_dialog.dart';
import 'widgets/dashboard_search_bar.dart';
import 'widgets/kpi_cards.dart';
import 'widgets/priority_queue_card.dart';
import 'widgets/quick_actions_menu.dart';

/// Master Dashboard Screen for Flutter Web
/// Two-column responsive layout with real-time Firestore data streaming
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Data access + services (created once per State, in initState)
  late final DashboardRepository _repository;
  // Created on first use: its notification services touch Firebase
  // Messaging, which isn't needed (or available in widget tests) to render.
  late final DashboardMessagingService _messagingService =
      DashboardMessagingService(_repository);
  late final CsvImportService _csvImportService;
  late final SchedulePrintService _schedulePrintService;

  // Phase 2: Activity log filtering and pagination state
  String? _selectedLogType; // null = all types
  int _activityLogLimit = 10;

  // Search and filter state
  String _searchCategory = 'Patient Name';
  final TextEditingController _searchController = TextEditingController();

  // Scroll controllers for table scrolling
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  // Firestore streams, created once so rebuilds (search keystrokes, chip
  // taps, ...) don't resubscribe. The activity-log stream is recreated only
  // when its filter or limit changes (see _refreshActivityLogStream).
  // Each keeps one Firestore subscription and replays the latest snapshot to
  // StreamBuilders created later (e.g. after resizing across a breakpoint).
  late final LatestValueStream<QuerySnapshot> _appointmentsStream;
  late final LatestValueStream<QuerySnapshot> _priorityQueueStream;
  late final LatestValueStream<QuerySnapshot> _allAppointmentsStream;
  late LatestValueStream<QuerySnapshot> _activityLogStream;

  /// Height given to the scrolling list regions when the columns are stacked
  /// inside the page's SingleChildScrollView (width <= 800), where an
  /// Expanded would get unbounded height.
  static const double _stackedRegionHeight = 560;

  @override
  void initState() {
    super.initState();
    _repository = context.read<DashboardRepository>();
    _csvImportService = CsvImportService(_repository);
    _schedulePrintService = SchedulePrintService(
      repository: _repository,
      searchController: _searchController,
      searchCategory: () => _searchCategory,
    );
    _appointmentsStream =
        LatestValueStream(_repository.watchDashboardAppointments());
    _priorityQueueStream = LatestValueStream(_repository.watchPriorityQueue());
    _allAppointmentsStream =
        LatestValueStream(_repository.watchAllAppointments());
    _activityLogStream = _createActivityLogStream();

    // First visit in this browser: open the guide once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDashboardHelpOnFirstVisit(context);
    });
  }

  LatestValueStream<QuerySnapshot> _createActivityLogStream() =>
      LatestValueStream(_repository.watchActivityLog(
        limit: _activityLogLimit,
        typeFilter: _selectedLogType,
      ));

  void _refreshActivityLogStream() {
    _activityLogStream.dispose();
    _activityLogStream = _createActivityLogStream();
  }

  /// Wraps a list region: Expanded in the side-by-side layouts (unchanged),
  /// a fixed-height box when stacked in the scrolling narrow layout.
  /// A null [stackedHeight] leaves the child at its natural height (only
  /// for children that size themselves, e.g. a SingleChildScrollView).
  Widget _flexibleRegion({
    required bool stacked,
    required Widget child,
    double? stackedHeight = _stackedRegionHeight,
  }) {
    if (stacked) {
      return stackedHeight == null
          ? child
          : SizedBox(height: stackedHeight, child: child);
    }
    return Expanded(child: child);
  }

  @override
  void dispose() {
    _appointmentsStream.dispose();
    _priorityQueueStream.dispose();
    _allAppointmentsStream.dispose();
    _activityLogStream.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Passed to the services so they can guard UI updates exactly like the
  /// original in-State code did with `mounted`.
  bool _isMounted() => mounted;

  /// Show Quick Actions Menu (SMS Templates)
  /// Uses the button's BuildContext to get position and anchor the menu beneath the button
  void _showQuickActionsMenu(
    BuildContext buttonContext,
    BuildContext overlayContext,
    AppointmentData appointment,
    BoxConstraints constraints,
  ) {
    showQuickActionsMenu(buttonContext, overlayContext)?.then((value) {
      if (value != null) {
        _messagingService.sendQuickActionSMS(
            context, _isMounted, appointment, value);
      }
    });
  }

  /// Send reminder via notification and SMS
  void _sendReminder(AppointmentData appointment) {
    _messagingService.triggerReminder(
        context,
        _isMounted,
        appointment.patientID,
        appointment.phone,
        appointment.name,
        appointment.formattedDate,
        appointment.formattedTime);
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
        actions: [
          Builder(
            builder: (context) {
              final isSmallScreen = MediaQuery.of(context).size.width < 600;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'Open the step-by-step guide',
                  child: isSmallScreen
                      ? IconButton(
                          icon: const Icon(Icons.help_outline,
                              color: Colors.white),
                          onPressed: () => showDashboardHelp(context),
                        )
                      : TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                          icon: const Icon(Icons.help_outline),
                          label: const Text('How to use',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          onPressed: () => showDashboardHelp(context),
                        ),
                ),
              );
            },
          ),
        ],
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
                  _buildLeftColumn(constraints, stacked: true),
                  SizedBox(
                      height: isVerySmallScreen
                          ? 8
                          : isSmallScreen
                              ? 10
                              : 12),
                  _buildRightColumn(constraints, stacked: true),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  /// Left Column: Daily Appointment Queue
  Widget _buildLeftColumn(BoxConstraints constraints, {bool stacked = false}) {
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
                  child: Row(
                    children: [
                      Flexible(
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
                      const HelpIconButton(
                        section: DashboardHelpSection.list,
                        tooltip: 'How does the appointment queue work?',
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    Tooltip(
                      message: 'Add a single appointment',
                      child: ElevatedButton.icon(
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
                    ),
                    Tooltip(
                      message:
                          'Add many appointments from a spreadsheet (CSV file)',
                      child: OutlinedButton.icon(
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
                        onPressed: () => _csvImportService.importCsvFile(
                            context, _isMounted),
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Tooltip(
                      message: 'Download as PDF or Print for Clinic Clipboard.',
                      child: OutlinedButton.icon(
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
                        onPressed: () => _schedulePrintService.printSchedule(
                            context, _isMounted),
                      ),
                    ),
                    IconButton(
                      tooltip:
                          'Show a QR code patients can scan to book themselves',
                      icon: const Icon(Icons.qr_code),
                      onPressed: () => showBookingQrDialog(context),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Text(
              'Showing: ${DateFormat('MMM dd, yyyy').format(DateTime.now())} - ${DateFormat('MMM dd, yyyy').format(DateTime.now().add(const Duration(days: 30)))} (Next 30 Days)',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: const Color(0xFF666666),
                fontWeight: FontWeight.w500,
              ),
            ),
            Divider(height: isSmallScreen ? 20 : 32, thickness: 1),
            // Search and Filter Bar
            DashboardSearchBar(
              constraints: constraints,
              searchCategory: _searchCategory,
              searchController: _searchController,
              onCategoryChanged: (newValue) {
                setState(() {
                  _searchCategory = newValue;
                });
              },
              onQueryChanged: () => setState(() {}), // Real-time update
              onClear: () {
                setState(() {
                  _searchController.clear();
                });
              },
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            // Responsive layout: Cards for small screens, DataTable for large screens
            _flexibleRegion(
              stacked: stacked,
              child: StreamBuilder<QuerySnapshot>(
                stream: _appointmentsStream.stream,
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

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
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

                  // Convert documents to AppointmentData objects; skip
                  // documents that fail to parse
                  final allAppointments = <AppointmentData>[];
                  for (var doc in snapshot.data!.docs) {
                    try {
                      allAppointments.add(AppointmentData.fromFirestore(doc));
                    } catch (e) {
                      if (kDebugMode) {
                        debugPrint('Error parsing appointment ${doc.id}: $e');
                      }
                    }
                  }

                  // Filter appointments to only show next 30 days
                  var appointments =
                      filterAppointmentsByDateRange(allAppointments);

                  // Apply search filter if search query is not empty
                  if (_searchController.text.isNotEmpty) {
                    appointments = applySearchFilter(
                        appointments, _searchCategory, _searchController.text);
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
                    return AppointmentCards(
                      appointments: appointments,
                      constraints: constraints,
                      onEdit: (context, appointment) =>
                          _showEditAppointmentDialog(
                              context, appointment, constraints),
                      onQuickActions: (buttonContext, context, appointment) =>
                          _showQuickActionsMenu(
                              buttonContext, context, appointment, constraints),
                      onSendReminder: _sendReminder,
                    );
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
                          child: AppointmentTable(
                            appointments: appointments,
                            constraints: constraints,
                            horizontalScrollController:
                                _horizontalScrollController,
                            verticalScrollController: _verticalScrollController,
                            onEdit: (context, appointment) =>
                                _showEditAppointmentDialog(
                                    context, appointment, constraints),
                            onQuickActions: (buttonContext, context,
                                    appointment) =>
                                _showQuickActionsMenu(buttonContext, context,
                                    appointment, constraints),
                            onSendReminder: _sendReminder,
                          ),
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

  /// Right Column: Reallocation Command Center
  Widget _buildRightColumn(BoxConstraints constraints, {bool stacked = false}) {
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
            Row(
              children: [
                Flexible(
                  child: Text(
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
                ),
                const HelpIconButton(
                  section: DashboardHelpSection.rightPanel,
                  tooltip: 'How does the Command Center work?',
                ),
              ],
            ),
            Divider(height: isSmallScreen ? 20 : 32, thickness: 1),
            // Scrollable content area with VERTICAL scrolling only
            // When stacked, the page itself scrolls: let this section take
            // its natural height instead of nesting a second scroll area.
            _flexibleRegion(
              stacked: stacked,
              stackedHeight: null,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: stacked
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Priority Queue Card
                    PriorityQueueCard(
                      constraints: constraints,
                      stream: _priorityQueueStream.stream,
                    ),
                    SizedBox(height: isSmallScreen ? 16 : 24),
                    // KPI Cards
                    KpiCardsSection(
                      constraints: constraints,
                      stream: _allAppointmentsStream.stream,
                      onReallocationsTap: showReallocationChart,
                    ),
                    SizedBox(height: isSmallScreen ? 16 : 24),
                    // Activity Log
                    ActivityLogPanel(
                      constraints: constraints,
                      stream: _activityLogStream.stream,
                      selectedLogType: _selectedLogType,
                      activityLogLimit: _activityLogLimit,
                      onFilterSelected: (type, selected) {
                        setState(() {
                          _selectedLogType = selected ? type : null;
                          _activityLogLimit =
                              10; // Reset limit when filter changes
                          _refreshActivityLogStream();
                        });
                      },
                      onLoadMore: () {
                        setState(() {
                          _activityLogLimit += 10;
                          _refreshActivityLogStream();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
}
