import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class MobileBookingForm extends StatefulWidget {
  final Function(String)? onSuccess;

  const MobileBookingForm({super.key, this.onSuccess});

  @override
  State<MobileBookingForm> createState() => _MobileBookingFormState();
}

class _MobileBookingFormState extends State<MobileBookingForm> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  String? _phoneE164;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().add(const Duration(days: 1));
    _selectedDate = now;
    _dateController.text = DateFormat('dd-MM-yyyy').format(now);
    _timeController.text = '10:00 AM';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd-MM-yyyy').format(picked);
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) {
      final dt = DateTime(0, 1, 1, picked.hour, picked.minute);
      final formatted = DateFormat('hh:mm a').format(dt);
      setState(() {
        _timeController.text = formatted;
      });
    }
  }

  void _clearAll() {
    setState(() {
      _nameController.clear();
      _phoneE164 = null;
      final now = DateTime.now().add(const Duration(days: 1));
      _selectedDate = now;
      _dateController.text = DateFormat('dd-MM-yyyy').format(now);
      _timeController.text = '10:00 AM';
    });
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneE164 == null ||
        _dateController.text.isEmpty ||
        _timeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, phone, date, and time are required')),
      );
      return;
    }

    final patientName = _nameController.text.trim();
    final docId =
        'web-${DateTime.now().millisecondsSinceEpoch}-${_dateController.text}-${_timeController.text}';

    await FirebaseFirestore.instance.collection('Appointments').doc(docId).set({
      'patientID': null,
      'email': null,
      'name': patientName,
      'address': null,
      'location': null,
      'date': _dateController.text,
      'time': _timeController.text,
      'status': 'active',
      'phone': _phoneE164,
      'operationType': null,
      'hospital': null,
      'reallocationStatus': 'Original',
      'userResponse': null,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Appointment Confirmed for $patientName!'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      
      if (widget.onSuccess != null) {
        widget.onSuccess!(patientName);
      }
      
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Book Appointment',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear All',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: AutofillGroup(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.all(32.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Section
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1976D2).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calendar_today,
                              color: Color(0xFF1976D2),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'New Appointment',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Fill in the details below',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF666666),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      const Divider(height: 1),
                      const SizedBox(height: 32),
                      
                      // Name Field
                      _buildProfessionalField(
                        label: 'Full Name',
                        icon: Icons.person_outline,
                        child: TextField(
                          controller: _nameController,
                          autofillHints: const [AutofillHints.name],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your full name',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 15,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF1976D2),
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Phone Field
                      _buildProfessionalField(
                        label: 'Phone Number',
                        icon: Icons.phone_outlined,
                        child: IntlPhoneField(
                          decoration: InputDecoration(
                            hintText: 'Enter phone number',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 15,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF1976D2),
                                width: 2,
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                          ),
                          initialCountryCode: 'GB',
                          keyboardType: TextInputType.phone,
                          onChanged: (phone) => _phoneE164 = phone.completeNumber,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Date and Time Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildProfessionalField(
                              label: 'Date',
                              icon: Icons.calendar_month_outlined,
                              child: TextField(
                                controller: _dateController,
                                readOnly: true,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1A1A1A),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Select date',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 15,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1976D2),
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.calendar_today,
                                      color: Color(0xFF1976D2),
                                    ),
                                    onPressed: _pickDate,
                                  ),
                                ),
                                onTap: _pickDate,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildProfessionalField(
                              label: 'Time',
                              icon: Icons.access_time,
                              child: TextField(
                                controller: _timeController,
                                readOnly: true,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1A1A1A),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Select time',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 15,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1976D2),
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.access_time,
                                      color: Color(0xFF1976D2),
                                    ),
                                    onPressed: _pickTime,
                                  ),
                                ),
                                onTap: _pickTime,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      
                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.check_circle_outline, size: 24),
                          label: const Text(
                            'Book Appointment',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shadowColor: const Color(0xFF1976D2).withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalField({
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: const Color(0xFF1976D2),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

