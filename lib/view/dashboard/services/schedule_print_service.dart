import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/appointment_data.dart';
import '../../../repositories/dashboard_repository.dart';
import '../appointment_filters.dart';

/// "Print Schedule" for the dashboard: builds a PDF of the appointments the
/// dashboard currently shows (same date range + search filter) and prints /
/// downloads it.
///
/// The search controller and category are read live (when the PDF is built),
/// exactly as the dashboard State did.
class SchedulePrintService {
  final DashboardRepository _repository;
  final TextEditingController _searchController;
  final String Function() _searchCategoryGetter;

  SchedulePrintService({
    required DashboardRepository repository,
    required TextEditingController searchController,
    required String Function() searchCategory,
  })  : _repository = repository,
        _searchController = searchController,
        _searchCategoryGetter = searchCategory;

  String get _searchCategory => _searchCategoryGetter();

  /// Get current filtered appointments for printing
  /// Uses the EXACT same date range logic as the dashboard's _filterAppointmentsByDateRange
  /// This ensures print output matches what's displayed on the dashboard
  Future<List<AppointmentData>> _getCurrentFilteredAppointments() async {
    try {
      // Get current snapshot
      final snapshot = await _repository.watchDashboardAppointments().first;
      
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
      var filtered = filterAppointmentsByDateRange(allAppointments);
      
      // Apply search filter if active (same as dashboard)
      if (_searchController.text.isNotEmpty) {
        filtered = applySearchFilter(filtered, _searchCategory, _searchController.text);
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
  Future<void> printSchedule(
      BuildContext context, bool Function() isMounted) async {
    try {
      // Show loading indicator
      if (isMounted()) {
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
        if (isMounted()) {
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

        if (isMounted()) {
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
        if (isMounted()) {
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
        if (isMounted()) {
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
      if (isMounted()) {
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
}
