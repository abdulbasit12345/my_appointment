import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../services/appointment_service.dart';
import '../../res/color.dart';
import '../../utils/appointment_status.dart';
import '../../utils/date_utils.dart';
import 'patientHomeViewNew.dart';

class SlotClaimScreen extends StatefulWidget {
  final String availableDate;
  final String availableTime;
  final String hospital;
  final String operationType;
  final String notificationType;
  final String? newSlotId; // For deep linking from notifications

  const SlotClaimScreen({
    super.key,
    required this.availableDate,
    required this.availableTime,
    required this.hospital,
    required this.operationType,
    required this.notificationType,
    this.newSlotId, // Optional: used when navigating from notification with slot ID
  });

  @override
  State<SlotClaimScreen> createState() => _SlotClaimScreenState();
}

class _SlotClaimScreenState extends State<SlotClaimScreen> {
  final AppointmentService _appointmentService = AppointmentService();
  bool _isLoading = false;
  bool _isClaiming = false;
  String? _currentAppointmentId;
  Map<String, dynamic>? _currentAppointmentData;

  @override
  void initState() {
    super.initState();
    // If newSlotId is provided, load slot details from Firestore
    if (widget.newSlotId != null && widget.newSlotId!.isNotEmpty) {
      _loadSlotDetailsFromId(widget.newSlotId!);
    } else {
      _loadCurrentAppointment();
    }
  }

  /// Load slot details from Firestore using newSlotId (for deep linking)
  Future<void> _loadSlotDetailsFromId(String slotId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch slot details from Appointments collection using the slot ID
      final slotDoc = await FirebaseFirestore.instance
          .collection('Appointments')
          .doc(slotId)
          .get();

      if (slotDoc.exists) {
        final slotData = slotDoc.data()!;
        // Update the widget's available date/time with fetched data
        // Note: This requires state management or callback to parent
        if (kDebugMode) {
          print('Loaded slot details from ID: $slotId');
          print('Slot data: $slotData');
        }
        // The slot details are now available in the document
        // You can use this to pre-fill the claim screen
      } else {
        if (kDebugMode) {
          print('Slot not found with ID: $slotId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading slot details: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load the current active appointment for the logged-in patient
  Future<void> _loadCurrentAppointment() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('No user logged in');
        }
        return;
      }

      // Find the patient's current active appointment
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('Appointments')
          .where('patientID', isEqualTo: user.uid)
          .where('status', whereIn: AppointmentStatus.bookedValues)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Get the earliest appointment (first in chronological queue)
        final appointments = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  'data': doc.data() as Map<String, dynamic>,
                })
            .toList();

        // Sort by date and time
        appointments.sort((a, b) {
          final aData = a['data'] as Map<String, dynamic>?;
          final bData = b['data'] as Map<String, dynamic>?;
          
          if (aData == null || bData == null) return 0;
          
          final aDate = aData['date'] as String? ?? '';
          final aTime = aData['time'] as String? ?? '';
          final bDate = bData['date'] as String? ?? '';
          final bTime = bData['time'] as String? ?? '';

          final aDateTime = _parseDateTime(aDate, aTime);
          final bDateTime = _parseDateTime(bDate, bTime);

          return aDateTime.compareTo(bDateTime);
        });

        setState(() {
          _currentAppointmentId = appointments.first['id'] as String;
          _currentAppointmentData = appointments.first['data'] as Map<String, dynamic>;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading current appointment: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading appointment: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Parse date and time strings into DateTime
  DateTime _parseDateTime(String dateStr, String timeStr) {
    final parsedDate = Date_Utils.parseDate(dateStr);
    // Handles 'hh:mm a' including PM, and 'HH:mm'
    final parsedTime = Date_Utils.tryParseTimeFlexible(timeStr);
    if (parsedTime != null) {
      return DateTime(parsedDate.year, parsedDate.month, parsedDate.day,
          parsedTime.hour, parsedTime.minute);
    }
    final timeParts = timeStr.split(':');
    final hour = int.parse(timeParts[0].trim());
    final minute = int.parse(timeParts[1].split(' ')[0].trim());
    return DateTime(parsedDate.year, parsedDate.month, parsedDate.day, hour, minute);
  }

  /// Claim the available slot
  Future<void> _claimSlot() async {
    if (_currentAppointmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No current appointment found')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to claim a slot')),
      );
      return;
    }

    setState(() {
      _isClaiming = true;
    });

    try {
      if (kDebugMode) {
        print('Attempting to claim slot:');
        print('  Patient ID: ${user.uid}');
        print('  New Date: ${widget.availableDate}');
        print('  New Time: ${widget.availableTime}');
        print('  Hospital: ${widget.hospital}');
        print('  Operation Type: ${widget.operationType}');
        print('  Old Appointment ID: $_currentAppointmentId');
      }

      final success = await _appointmentService.claimSlot(
        patientId: user.uid,
        newDate: widget.availableDate,
        newTime: widget.availableTime,
        newHospital: widget.hospital,
        newOperationType: widget.operationType,
        oldAppointmentDocumentId: _currentAppointmentId!,
        context: context,
      );

      if (kDebugMode) {
        print('Claim slot result: $success');
      }

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Slot claimed successfully! You now have two appointments. You can cancel either one later if needed.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        // Wait a bit longer to ensure Firestore has synced the new appointment
        // This ensures the StreamBuilder on the home screen will show the new appointment
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const PatientHomeViewNew(),
              ),
              (route) => false, // Remove all previous routes
            );
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to claim slot. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error claiming slot: $e');
      }
      
      // Provide user-friendly error messages
      String errorMessage;
      if (e.toString().contains('SLOT_ALREADY_TAKEN')) {
        errorMessage = '⚠️ This slot has already been claimed by another patient. Please try another slot.';
      } else if (e.toString().contains('not found')) {
        errorMessage = '❌ Appointment not found. Please refresh and try again.';
      } else if (e.toString().contains('not active')) {
        errorMessage = '❌ This appointment is no longer active.';
      } else {
        errorMessage = '❌ Failed to claim slot. Please try again.';
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _isClaiming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Claim Available Slot',
          style: TextStyle(color: AppColors.whiteColor),
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: AppColors.whiteColor),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Card
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            widget.notificationType == 'cascaded_slot_available'
                                ? Icons.refresh
                                : Icons.event_available,
                            size: 48,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.notificationType == 'cascaded_slot_available'
                                ? '🔄 Cascaded Slot Available'
                                : '🎯 New Slot Available',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.notificationType == 'cascaded_slot_available'
                                ? 'This slot was freed by another patient moving up'
                                : 'An earlier appointment slot has become available',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Available Slot Details
                  const Text(
                    'Available Slot Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow(
                            Icons.calendar_today,
                            'Date',
                            widget.availableDate,
                          ),
                          const Divider(),
                          _buildDetailRow(
                            Icons.access_time,
                            'Time',
                            widget.availableTime,
                          ),
                          const Divider(),
                          _buildDetailRow(
                            Icons.local_hospital,
                            'Hospital',
                            widget.hospital,
                          ),
                          const Divider(),
                          _buildDetailRow(
                            Icons.medical_services,
                            'Operation Type',
                            widget.operationType,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Current Appointment (if exists)
                  if (_currentAppointmentData != null) ...[
                    const Text(
                      'Your Current Appointment',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              Icons.calendar_today,
                              'Current Date',
                              _currentAppointmentData!['date'] as String,
                            ),
                            const Divider(),
                            _buildDetailRow(
                              Icons.access_time,
                              'Current Time',
                              _currentAppointmentData!['time'] as String,
                            ),
                            const Divider(),
                            _buildDetailRow(
                              Icons.local_hospital,
                              'Current Hospital',
                              _currentAppointmentData!['hospital'] as String? ?? 'N/A',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Benefits Card
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                'Benefits of Claiming This Slot',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildBenefitItem('✓ Get an earlier appointment date'),
                          _buildBenefitItem('✓ Reduce waiting time'),
                          _buildBenefitItem('✓ Your old slot will be offered to others'),
                          if (widget.notificationType == 'cascaded_slot_available')
                            _buildBenefitItem('✓ This is a cascaded opportunity'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Action Buttons
                  ElevatedButton.icon(
                    onPressed: _isClaiming ? null : _claimSlot,
                    icon: _isClaiming
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(_isClaiming ? 'Claiming Slot...' : 'Claim This Slot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blueAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

