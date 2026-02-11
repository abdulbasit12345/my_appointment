import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

// Ensure this utility file exists and contains parseDate/parseTime methods
import '../../utils/date_utils.dart';

/// Professional Appointment Graph Screen
/// Displays appointment availability with time on X-axis and date on Y-axis
class AppointmentGraphScreen extends StatelessWidget {
  const AppointmentGraphScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Availability Graph'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: const GraphWidget(),
    );
  }
}

/// Professional Graph Widget with real-time updates
class GraphWidget extends StatefulWidget {
  const GraphWidget({super.key});

  @override
  State<GraphWidget> createState() => _GraphWidgetState();
}

class _GraphWidgetState extends State<GraphWidget> {
  List<AppointmentChartData> _chartData = [];
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<QuerySnapshot>? _subscription;
  String? _currentUserId; // Current patient's user ID

  // Filter states
  String _selectedStatus = 'all'; // 'all', 'active', 'cancelled'
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _initializeData();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// Initialize data fetching and real-time updates
  void _initializeData() {
    _fetchDataFromFirestore();
    _listenToFirestoreUpdates();
  }

  /// Fetch initial data from Firestore
  Future<void> _fetchDataFromFirestore() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final snapshot =
          await FirebaseFirestore.instance.collection("AppointmentGraph").get();

      _processSnapshot(snapshot);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error fetching graph data: $e');
        print('Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load graph data. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  /// Listen to real-time Firestore updates
  void _listenToFirestoreUpdates() {
    _subscription = FirebaseFirestore.instance
        .collection("AppointmentGraph")
        .snapshots()
        .listen(
      (snapshot) {
        _processSnapshot(snapshot);
      },
      onError: (error) {
        if (kDebugMode) {
          print('Error listening to Firestore updates: $error');
        }
        if (mounted) {
          setState(() {
            _errorMessage = 'Error receiving updates';
          });
        }
      },
    );
  }

  /// Process Firestore snapshot and convert to chart data
  void _processSnapshot(QuerySnapshot snapshot) {
    try {
      final List<AppointmentChartData> dataList = [];

      for (var doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          // Safely parse date - handle String, Timestamp, or int
          DateTime parsedDate;
          try {
            final dateField = data['appointmentDate'];
            if (dateField == null) {
              if (kDebugMode) {
                print(
                    '⚠️ Document ${doc.id}: appointmentDate is null, skipping');
              }
              continue;
            }

            if (dateField is String) {
              parsedDate = Date_Utils.parseDate(dateField);
            } else if (dateField is Timestamp) {
              parsedDate = dateField.toDate();
            } else if (dateField is int) {
              parsedDate = DateTime.fromMillisecondsSinceEpoch(dateField);
            } else {
              if (kDebugMode) {
                print(
                    '⚠️ Document ${doc.id}: appointmentDate has unexpected type ${dateField.runtimeType}, value: $dateField');
              }
              continue;
            }
          } catch (e, stackTrace) {
            if (kDebugMode) {
              print('❌ Document ${doc.id}: Error parsing appointmentDate: $e');
              print('   Stack trace: $stackTrace');
              print(
                  '   Raw value: ${data['appointmentDate']} (type: ${data['appointmentDate']?.runtimeType})');
            }
            continue;
          }

          // Safely parse time - handle String, Timestamp, or int
          DateTime parsedTime;
          try {
            final timeField = data['time'];
            if (timeField == null) {
              if (kDebugMode) {
                print('⚠️ Document ${doc.id}: time is null, skipping');
              }
              continue;
            }

            if (timeField is String) {
              parsedTime = Date_Utils.parseTime(timeField);
            } else if (timeField is Timestamp) {
              parsedTime = timeField.toDate();
            } else if (timeField is int) {
              // If it's an int, assume it's milliseconds since epoch
              parsedTime = DateTime.fromMillisecondsSinceEpoch(timeField);
            } else {
              if (kDebugMode) {
                print(
                    '⚠️ Document ${doc.id}: time has unexpected type ${timeField.runtimeType}, value: $timeField');
              }
              continue;
            }
          } catch (e, stackTrace) {
            if (kDebugMode) {
              print('❌ Document ${doc.id}: Error parsing time: $e');
              print('   Stack trace: $stackTrace');
              print(
                  '   Raw value: ${data['time']} (type: ${data['time']?.runtimeType})');
            }
            continue;
          }

          // Validate parsed dates
          if (parsedDate.year < 2000 || parsedDate.year > 2100) {
            if (kDebugMode) {
              print(
                  '⚠️ Document ${doc.id}: Invalid date year ${parsedDate.year}, skipping');
            }
            continue;
          }

          // Create combined DateTime for the appointment
          final appointmentDateTime = DateTime(
            parsedDate.year,
            parsedDate.month,
            parsedDate.day,
            parsedTime.hour,
            parsedTime.minute,
          );

          // Extract status (handle both 'cancelled' and 'canceled')
          final status = (data['status'] as String? ?? 'unknown').toLowerCase();
          final normalizedStatus = status == 'canceled' ? 'cancelled' : status;

          // Get userId from document
          final userId = data['userId'] as String?;

          // Only add appointments from today onwards (not past appointments)
          final today = DateTime.now();
          final appointmentDateOnly =
              DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
          final todayOnly = DateTime(today.year, today.month, today.day);

          // Skip if appointment is in the past
          if (appointmentDateOnly.isBefore(todayOnly)) {
            if (kDebugMode) {
              print(
                  '⏭️ Skipping past appointment: ${doc.id} (date: $appointmentDateOnly)');
            }
            continue;
          }

          dataList.add(AppointmentChartData(
            appointmentDateTime: appointmentDateTime,
            date: parsedDate,
            time: parsedTime,
            status: normalizedStatus,
            patientName: data['patientName'] as String? ?? 'Unknown',
            hospitalName: data['hospitalName'] as String? ?? 'Unknown',
            documentId: doc.id,
            userId: userId,
          ));
        } catch (e, stackTrace) {
          if (kDebugMode) {
            print('❌ Error processing document ${doc.id}: $e');
            print('   Stack trace: $stackTrace');
            print('   Document data: ${doc.data()}');
          }
          // Continue processing other documents
        }
      }

      // Sort by date and time
      dataList.sort(
          (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime));

      if (kDebugMode) {
        print(
            '✅ Successfully processed ${dataList.length} appointments from ${snapshot.docs.length} documents');
      }

      if (mounted) {
        setState(() {
          _chartData = dataList;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error processing snapshot: $e');
        print('   Stack trace: $stackTrace');
      }
      if (mounted) {
        setState(() {
          _errorMessage = 'Error processing data: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  /// Get filtered chart data based on current filters
  List<AppointmentChartData> get _filteredData {
    var filtered = _chartData;

    // Filter by status
    if (_selectedStatus != 'all') {
      filtered =
          filtered.where((data) => data.status == _selectedStatus).toList();
    }

    // Filter by date range (if specified)
    if (_startDate != null) {
      filtered = filtered
          .where((data) =>
              data.date
                  .isAfter(_startDate!.subtract(const Duration(days: 1))) ||
              data.date.isAtSameMomentAs(_startDate!))
          .toList();
    }

    if (_endDate != null) {
      filtered = filtered
          .where((data) =>
              data.date.isBefore(_endDate!.add(const Duration(days: 1))) ||
              data.date.isAtSameMomentAs(_endDate!))
          .toList();
    }

    return filtered;
  }

  /// Get current patient's appointments
  List<AppointmentChartData> get _currentPatientData {
    if (_currentUserId == null) return [];
    return _filteredData
        .where((data) => data.userId == _currentUserId)
        .toList();
  }

  /// Get other patients' appointments
  List<AppointmentChartData> get _otherPatientsData {
    if (_currentUserId == null) return _filteredData;
    return _filteredData
        .where((data) => data.userId != _currentUserId)
        .toList();
  }

  /// Get current patient's active appointments
  List<AppointmentChartData> get _currentPatientActiveData {
    return _currentPatientData
        .where((data) => data.status == 'active')
        .toList();
  }

  /// Get current patient's cancelled appointments
  List<AppointmentChartData> get _currentPatientCancelledData {
    return _currentPatientData
        .where((data) => data.status == 'cancelled')
        .toList();
  }

  /// Get other patients' active appointments
  List<AppointmentChartData> get _otherPatientsActiveData {
    return _otherPatientsData.where((data) => data.status == 'active').toList();
  }

  /// Get other patients' cancelled appointments
  List<AppointmentChartData> get _otherPatientsCancelledData {
    return _otherPatientsData
        .where((data) => data.status == 'cancelled')
        .toList();
  }

  /// Get active appointments - ONLY for current patient
  List<AppointmentChartData> get _activeData {
    return _currentPatientData
        .where((data) => data.status == 'active')
        .toList();
  }

  /// Get cancelled appointments - ONLY for current patient
  List<AppointmentChartData> get _cancelledData {
    return _currentPatientData
        .where((data) => data.status == 'cancelled')
        .toList();
  }

  /// Get total appointments - ONLY for current patient
  List<AppointmentChartData> get _totalData {
    return _currentPatientData;
  }

  /// Calculate axis ranges with safe defaults
  DateTime get _minDate {
    if (_filteredData.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
    try {
      final dates = _filteredData.map((d) => d.date).toList();

      if (dates.isEmpty) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day);
      }

      return dates.reduce((a, b) => a.isBefore(b) ? a : b);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error calculating _minDate: $e');
        print('   Stack trace: $stackTrace');
      }
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
  }

  DateTime get _maxDate {
    if (_filteredData.isEmpty) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 30));
    }
    try {
      final dates = _filteredData.map((d) => d.date).toList();

      if (dates.isEmpty) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day)
            .add(const Duration(days: 30));
      }

      return dates.reduce((a, b) => a.isAfter(b) ? a : b);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error calculating _maxDate: $e');
        print('   Stack trace: $stackTrace');
      }
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 30));
    }
  }

  DateTime get _minTime {
    if (_filteredData.isEmpty)
      return DateTime(2000, 1, 1, 8, 0); // 8 AM default
    try {
      final times = _filteredData.map((d) => d.time).toList();

      if (times.isEmpty) {
        return DateTime(2000, 1, 1, 8, 0);
      }

      return times.reduce((a, b) => a.isBefore(b) ? a : b);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error calculating _minTime: $e');
        print('   Stack trace: $stackTrace');
      }
      return DateTime(2000, 1, 1, 8, 0);
    }
  }

  DateTime get _maxTime {
    if (_filteredData.isEmpty)
      return DateTime(2000, 1, 1, 20, 0); // 8 PM default
    try {
      final times = _filteredData.map((d) => d.time).toList();

      if (times.isEmpty) {
        return DateTime(2000, 1, 1, 20, 0);
      }

      return times.reduce((a, b) => a.isAfter(b) ? a : b);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error calculating _maxTime: $e');
      }
      return DateTime(2000, 1, 1, 20, 0);
    }
  }

  /// Get safe minimum time for X-axis (ensures valid DateTime)
  DateTime _getSafeMinTime() {
    try {
      final minHour = math.max(0, math.min(23, _minTime.hour - 1));
      return DateTime(2000, 1, 1, minHour, 0);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _getSafeMinTime: $e');
      }
      return DateTime(2000, 1, 1, 6, 0); // Default to 6 AM
    }
  }

  /// Get safe maximum time for X-axis (ensures valid DateTime)
  DateTime _getSafeMaxTime() {
    try {
      final maxHour = math.max(1, math.min(23, _maxTime.hour + 1));
      return DateTime(2000, 1, 1, maxHour, 0);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _getSafeMaxTime: $e');
      }
      return DateTime(2000, 1, 1, 22, 0); // Default to 10 PM
    }
  }

  /// Get safe minimum date for Y-axis (ensures valid DateTime)
  DateTime _getSafeMinDate() {
    try {
      return _minDate.subtract(const Duration(days: 1));
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _getSafeMinDate: $e');
      }
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
    }
  }

  /// Get safe maximum date for Y-axis (ensures valid DateTime)
  DateTime _getSafeMaxDate() {
    try {
      return _maxDate.add(const Duration(days: 1));
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in _getSafeMaxDate: $e');
      }
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 31));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading appointment data...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchDataFromFirestore,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_chartData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No appointment data available',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Appointments will appear here once they are created',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 🛠️ WRAP ENTIRE CONTENT IN SingleChildScrollView
    return SingleChildScrollView(
      // 🟢 CHANGE 1: Use ClampingScrollPhysics for better gesture interaction
      physics: const ClampingScrollPhysics(),
      child: Column(
        children: [
          // Filter and Legend Section
          _buildFilterSection(),

          // Zoom/Scroll Hint
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Pinch to zoom • Drag to pan • Scroll to navigate',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Graph Section - Enclosed in a Container with fixed height
          Container(
            height: MediaQuery.of(context).size.height * 0.7,
            margin: const EdgeInsets.all(16.0),
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _buildChart(),
          ),

          // Statistics Section
          _buildStatisticsSection(),

          // Add bottom padding for better scrolling
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Build filter section with professional styling
  Widget _buildFilterSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C3E50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.filter_list,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Filters & Legend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C3E50),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // Content Section
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Filter Section
                Row(
                  children: [
                    const Icon(
                      Icons.tune,
                      color: Color(0xFF34495E),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Status Filter',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF34495E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'all',
                        label: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'All',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        icon: Icon(Icons.apps, size: 16),
                      ),
                      ButtonSegment<String>(
                        value: 'active',
                        label: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        icon: Icon(Icons.check_circle_outline, size: 16),
                      ),
                      ButtonSegment<String>(
                        value: 'cancelled',
                        label: Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'Cancelled',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        icon: Icon(Icons.cancel_outlined, size: 16),
                      ),
                    ],
                    selected: {_selectedStatus},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        _selectedStatus = newSelection.first;
                      });
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.selected)) {
                            return const Color(0xFF2C3E50);
                          }
                          return Colors.transparent;
                        },
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          if (states.contains(MaterialState.selected)) {
                            return Colors.white;
                          }
                          return const Color(0xFF34495E);
                        },
                      ),
                      side: WidgetStateProperty.all(BorderSide.none),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Legend Section
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFF34495E),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Legend',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF34495E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Responsive layout for legend items
                      final isSmallScreen = constraints.maxWidth < 400;
                      return isSmallScreen
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: _buildLegendItem(
                                          const Color(0xFF27AE60), 'My Active',
                                          isHighlighted: true),
                                    ),
                                    Flexible(
                                      child: _buildLegendItem(
                                          const Color(0xFFE74C3C),
                                          'My Cancelled',
                                          isHighlighted: true),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: _buildLegendItem(
                                          const Color(0xFF52BE80),
                                          'Other Active'),
                                    ),
                                    Flexible(
                                      child: _buildLegendItem(
                                          const Color(0xFFEC7063),
                                          'Other Cancelled'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _buildLegendItem(
                                    const Color(0xFF27AE60), 'My Active',
                                    isHighlighted: true),
                                _buildLegendItem(
                                    const Color(0xFFE74C3C), 'My Cancelled',
                                    isHighlighted: true),
                                _buildLegendItem(
                                    const Color(0xFF52BE80), 'Other Active'),
                                _buildLegendItem(
                                    const Color(0xFFEC7063), 'Other Cancelled'),
                              ],
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build legend item with professional styling
  Widget _buildLegendItem(Color color, String label,
      {bool isHighlighted = false}) {
    Color borderColor;
    double borderWidth;
    double size;

    if (isHighlighted) {
      // For "My" appointments - triangles with bold borders
      borderColor = label.contains('Active')
          ? const Color(0xFF1E8449)
          : const Color(0xFFC0392B);
      borderWidth = 2.5;
      size = 20;
    } else {
      // For "Other" appointments - circles/diamonds with subtle borders
      borderColor = Colors.white;
      borderWidth = 2;
      size = 14;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: isHighlighted
                  ? BoxShape.rectangle
                  : (label.contains('Cancelled')
                      ? BoxShape.rectangle
                      : BoxShape.circle),
              borderRadius: isHighlighted
                  ? BorderRadius.circular(4)
                  : (label.contains('Cancelled')
                      ? BorderRadius.circular(2)
                      : null),
              border: Border.all(
                color: borderColor,
                width: borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isHighlighted ? 12.5 : 11.5,
                fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
                color: const Color(0xFF34495E),
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // 🛠️ CORRECTED HELPER FUNCTIONS TO RETURN 'num' (Milliseconds)

  /// Helper function to get X value as milliseconds (for Time of Day Axis)
  num _getXValue(AppointmentChartData data) {
    // Returns milliseconds since epoch (num) for the time component.
    return DateTime(2000, 1, 1, data.time.hour, data.time.minute)
        .millisecondsSinceEpoch;
  }

  /// Helper function to get Y value as milliseconds (for Date Axis)
  num _getYValue(AppointmentChartData data) {
    // Returns milliseconds since epoch (num) for the date component.
    return data.date.millisecondsSinceEpoch;
  }

  // ----------------------------------------------------------------------

  /// Build the main chart
  Widget _buildChart() {
    if (_filteredData.isEmpty) {
      return const Center(
        child: Text(
          'No data available for selected filters',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    // Chart will fill the container and use zoom/pan for navigation
    return RepaintBoundary(
      child: SfCartesianChart(
        key: ValueKey(
            'chart_${_filteredData.length}_${_currentUserId ?? 'none'}_${_selectedStatus}'), // Stable key with status
        title: ChartTitle(
          text: 'Appointment Schedule',
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3E50),
            letterSpacing: 0.5,
          ),
          alignment: ChartAlignment.near,
        ),
        // Legend is disabled - we show it in the filter section above instead
        legend: const Legend(
          isVisible: false,
        ),

        // 🛠️ FINAL FIX: Use NumericAxis with axisLabelFormatter for X-Axis (Time)
        primaryXAxis: NumericAxis(
          title: AxisTitle(
            text: 'Time of Day',
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          minimum: _getSafeMinTime().millisecondsSinceEpoch.toDouble(),
          maximum: _getSafeMaxTime().millisecondsSinceEpoch.toDouble(),
          interval: const Duration(hours: 2).inMilliseconds.toDouble(),

          // 🟢 CORRECTED PARAMETER: axisLabelFormatter
          axisLabelFormatter: (AxisLabelRenderDetails details) {
            final time =
                DateTime.fromMillisecondsSinceEpoch(details.value.toInt());
            return ChartAxisLabel(
              DateFormat('hh:mm a').format(time),
              const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF34495E),
              ),
            );
          },
          majorGridLines: const MajorGridLines(
            width: 1.0,
            color: Color(0xFFBDC3C7),
            dashArray: [5, 5],
          ),
          minorGridLines: const MinorGridLines(
            width: 0.5,
            color: Color(0xFFE8E8E8),
          ),
          axisLine: const AxisLine(
            width: 2,
            color: Color(0xFF34495E),
          ),
          majorTickLines: const MajorTickLines(
            size: 6,
            width: 2,
            color: Color(0xFF34495E),
          ),
          minorTickLines: const MinorTickLines(
            size: 3,
            width: 1,
            color: Color(0xFF95A5A6),
          ),
        ),

        // 🛠️ FINAL FIX: Use NumericAxis with axisLabelFormatter for Y-Axis (Date)
        primaryYAxis: NumericAxis(
          title: AxisTitle(
            text: 'Date',
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          minimum: _getSafeMinDate().millisecondsSinceEpoch.toDouble(),
          maximum: _getSafeMaxDate().millisecondsSinceEpoch.toDouble(),
          interval: const Duration(days: 1).inMilliseconds.toDouble(),

          // 🟢 CORRECTED PARAMETER: axisLabelFormatter
          axisLabelFormatter: (AxisLabelRenderDetails details) {
            final date =
                DateTime.fromMillisecondsSinceEpoch(details.value.toInt());
            return ChartAxisLabel(
              DateFormat('MMM dd').format(date),
              const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF34495E),
              ),
            );
          },
          majorGridLines: const MajorGridLines(
            width: 1.0,
            color: Color(0xFFBDC3C7),
            dashArray: [5, 5],
          ),
          minorGridLines: const MinorGridLines(
            width: 0.5,
            color: Color(0xFFE8E8E8),
          ),
          axisLine: const AxisLine(
            width: 2,
            color: Color(0xFF34495E),
          ),
          majorTickLines: const MajorTickLines(
            size: 6,
            width: 2,
            color: Color(0xFF34495E),
          ),
          minorTickLines: const MinorTickLines(
            size: 3,
            width: 1,
            color: Color(0xFF95A5A6),
          ),
        ),

        // 🛠️ INTERACTION: Enable Zoom and Pan
        zoomPanBehavior: ZoomPanBehavior(
          enablePanning: true, // Enable drag-to-pan/scroll
          enablePinching: true, // Enable pinch-to-zoom
          enableDoubleTapZooming: true,
          // 🟢 NOTE: Removed enableSelectionZooming to prevent conflicts with drag/pan
          zoomMode: ZoomMode.xy, // Enable scrolling/zooming on both axes
          maximumZoomLevel: 5.0,
        ),
        tooltipBehavior: TooltipBehavior(
          enable: false,
        ),
        plotAreaBackgroundColor: const Color(0xFFFAFAFA),
        backgroundColor: Colors.white,
        borderColor: const Color(0xFFE0E0E0),
        borderWidth: 1,
        series: <CartesianSeries>[
          // All series use the generic type 'num' and return milliseconds

          // Current Patient's Active Appointments
          if (_currentPatientActiveData.isNotEmpty)
            ScatterSeries<AppointmentChartData, num>(
              name: 'My Active Appointments',
              dataSource: _currentPatientActiveData,
              xValueMapper: (data, _) => _getXValue(data),
              yValueMapper: (data, _) => _getYValue(data),
              pointColorMapper: (AppointmentChartData data, _) =>
                  const Color(0xFF27AE60),
              markerSettings: MarkerSettings(
                isVisible: true,
                shape: DataMarkerType.triangle,
                height: 20,
                width: 20,
                borderWidth: 3,
                borderColor: const Color(0xFF1E8449),
              ),
              dataLabelSettings: const DataLabelSettings(
                isVisible: false,
              ),
            ),
          // Current Patient's Cancelled Appointments
          if (_currentPatientCancelledData.isNotEmpty)
            ScatterSeries<AppointmentChartData, num>(
              name: 'My Cancelled Appointments',
              dataSource: _currentPatientCancelledData,
              xValueMapper: (data, _) => _getXValue(data),
              yValueMapper: (data, _) => _getYValue(data),
              pointColorMapper: (AppointmentChartData data, _) =>
                  const Color(0xFFE74C3C),
              markerSettings: MarkerSettings(
                isVisible: true,
                shape: DataMarkerType.triangle,
                height: 20,
                width: 20,
                borderWidth: 3,
                borderColor: const Color(0xFFC0392B),
              ),
              dataLabelSettings: const DataLabelSettings(
                isVisible: false,
              ),
            ),
          // Other Patients' Active Appointments
          if (_otherPatientsActiveData.isNotEmpty)
            ScatterSeries<AppointmentChartData, num>(
              name: 'Other Active Appointments',
              dataSource: _otherPatientsActiveData,
              xValueMapper: (data, _) => _getXValue(data),
              yValueMapper: (data, _) => _getYValue(data),
              pointColorMapper: (AppointmentChartData data, _) =>
                  const Color(0xFF52BE80),
              markerSettings: const MarkerSettings(
                isVisible: true,
                shape: DataMarkerType.circle,
                height: 12,
                width: 12,
                borderWidth: 2,
                borderColor: Color(0xFFFFFFFF),
              ),
              dataLabelSettings: const DataLabelSettings(
                isVisible: false,
              ),
            ),
          // Other Patients' Cancelled Appointments
          if (_otherPatientsCancelledData.isNotEmpty)
            ScatterSeries<AppointmentChartData, num>(
              name: 'Other Cancelled Appointments',
              dataSource: _otherPatientsCancelledData,
              xValueMapper: (data, _) => _getXValue(data),
              yValueMapper: (data, _) => _getYValue(data),
              pointColorMapper: (AppointmentChartData data, _) =>
                  const Color(0xFFEC7063),
              markerSettings: const MarkerSettings(
                isVisible: true,
                shape: DataMarkerType.diamond,
                height: 12,
                width: 12,
                borderWidth: 2,
                borderColor: Color(0xFFFFFFFF),
              ),
              dataLabelSettings: const DataLabelSettings(
                isVisible: false,
              ),
            ),
        ],
      ),
    );
  }

  /// Build statistics section
  Widget _buildStatisticsSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard(
            'Total',
            _totalData.length.toString(),
            Colors.blue,
            Icons.calendar_today,
          ),
          _buildStatCard(
            'Active',
            _activeData.length.toString(),
            Colors.green,
            Icons.check_circle,
          ),
          _buildStatCard(
            'Cancelled',
            _cancelledData.length.toString(),
            Colors.red,
            Icons.cancel,
          ),
        ],
      ),
    );
  }

  /// Build a statistics card
  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

/// Chart data model for appointments
class AppointmentChartData {
  final DateTime appointmentDateTime;
  final DateTime date;
  final DateTime time;
  final String status;
  final String patientName;
  final String hospitalName;
  final String documentId;
  final String? userId; // User ID to identify current patient's appointments

  AppointmentChartData({
    required this.appointmentDateTime,
    required this.date,
    required this.time,
    required this.status,
    required this.patientName,
    required this.hospitalName,
    required this.documentId,
    this.userId,
  });
}

/// Bottom sheet widget for appointment details
Widget buildPersistentBottomSheet(
  BuildContext context,
  String appointmentDate,
  String appointmentTime,
  String status,
) {
  // Local variable declarations for parsing (using Date_Utils for correct format)
  String formattedTime;
  String formattedDate;

  try {
    // Use Date_Utils to parse date in 'dd-MM-yyyy' format
    DateTime parsedDate = Date_Utils.parseDate(appointmentDate);
    formattedDate = Date_Utils.formatDate(parsedDate);

    // Parse time using Date_Utils
    DateTime parsedTime = Date_Utils.parseTime(appointmentTime);
    formattedTime = Date_Utils.timeFormat.format(parsedTime);
  } catch (e) {
    // Fallback if parsing fails - use original values
    formattedTime = appointmentTime;
    formattedDate = appointmentDate;
  }

  return Container(
    height: 80,
    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 6,
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 🛠️ FIX: Use Expanded to prevent Text overflow in Row
        Expanded(
          child: Text(
            'Appointment on $formattedDate at $formattedTime (Status: ${status.toUpperCase()})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        const SizedBox(width: 8), // Small separator

        IconButton(
          icon: const Icon(Icons.show_chart, color: Colors.blueAccent),
          iconSize: 40,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AppointmentGraphScreen(),
              ),
            );
          },
        ),
      ],
    ),
  );
}
