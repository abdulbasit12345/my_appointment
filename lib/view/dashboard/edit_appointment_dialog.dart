import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/appointment_data.dart';
import '../../utils/date_utils.dart';

/// Professional Edit Appointment Dialog for Admin Dashboard
class EditAppointmentDialog extends StatefulWidget {
  final AppointmentData appointment;
  final BoxConstraints constraints;

  const EditAppointmentDialog({
    super.key,
    required this.appointment,
    required this.constraints,
  });

  @override
  State<EditAppointmentDialog> createState() => _EditAppointmentDialogState();
}

class _EditAppointmentDialogState extends State<EditAppointmentDialog> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _dateController;
  late TextEditingController _timeController;
  
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.appointment.name);
    _phoneController = TextEditingController(text: widget.appointment.phone);
    _dateController = TextEditingController(text: widget.appointment.formattedDate);
    _timeController = TextEditingController(text: widget.appointment.formattedTime);
    _selectedDate = widget.appointment.date;
    _selectedTime = TimeOfDay.fromDateTime(widget.appointment.appointmentDateTime);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = Date_Utils.formatDate(picked);
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
        _timeController.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  String _normalizePhoneNumber(String phone) {
    String cleaned = phone.trim();
    if (cleaned.isEmpty) return cleaned;
    
    // Remove all non-digit characters except +
    cleaned = cleaned.replaceAll(RegExp(r'[^\d+]'), '');
    
    // If already in E.164 format (starts with +), return as is
    if (cleaned.startsWith('+')) {
      return cleaned;
    }
    
    // If starts with 00 (international format), replace with +
    if (cleaned.startsWith('00')) {
      return '+' + cleaned.substring(2);
    }
    
    // If starts with 0 (local format), try to detect country
    if (cleaned.startsWith('0') && cleaned.length > 10) {
      // UK format: 0XXXXXXXXX -> +44XXXXXXXXX
      return '+44' + cleaned.substring(1);
    }
    
    // If 10 digits, assume US number
    if (cleaned.length == 10) {
      return '+1' + cleaned;
    }
    
    // If 11 digits starting with 1, assume US
    if (cleaned.length == 11 && cleaned.startsWith('1')) {
      return '+' + cleaned;
    }
    
    // Return with + prefix if not already present
    return cleaned.startsWith('+') ? cleaned : '+' + cleaned;
  }

  Future<void> _saveChanges() async {
    // Validate inputs
    if (_nameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter patient name')),
        );
      }
      return;
    }
    
    if (_phoneController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter phone number')),
        );
      }
      return;
    }
    
    if (_selectedDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a date')),
        );
      }
      return;
    }
    
    if (_selectedTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a time')),
        );
      }
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Format date and time
      final formattedDate = Date_Utils.formatDate(_selectedDate!);
      final formattedTime = '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
      
      // Normalize phone number
      final normalizedPhone = _normalizePhoneNumber(_phoneController.text.trim());
      
      // Update Firestore
      await FirebaseFirestore.instance
          .collection('Appointments')
          .doc(widget.appointment.documentId)
          .update({
        'name': _nameController.text.trim(),
        'phone': normalizedPhone,
        'date': formattedDate,
        'time': formattedTime,
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedBy': 'admin',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating appointment: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = widget.constraints.maxWidth < 600;
    
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit, color: Color(0xFF1976D2), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Edit Appointment',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: isSmallScreen ? double.maxFinite : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient Name
              Text(
                'Patient Name *',
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Enter patient name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              
              // Phone Number
              Text(
                'Phone Number *',
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  hintText: '+1234567890',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: const Icon(Icons.phone, size: 20),
                ),
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              
              // Date
              Text(
                'Date *',
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dateController.text,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Time
              Text(
                'Time *',
                style: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _selectTime(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _timeController.text,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Cancel Button
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.grey[700],
            ),
          ),
        ),
        // Save Button
        ElevatedButton(
          onPressed: _isSaving ? null : _saveChanges,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Save Changes',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }
}

