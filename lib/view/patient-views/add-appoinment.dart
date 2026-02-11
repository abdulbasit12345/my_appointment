import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../res/color.dart';

class AddAppointmentScreen extends StatefulWidget {
  const AddAppointmentScreen({super.key});

  @override
  State<AddAppointmentScreen> createState() => _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends State<AddAppointmentScreen> {
  DateTime? _selectedDate;
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String? _normalizedPhoneNumber; // Store E.164 formatted phone number
  List<DateTime> _disabledDates = [];

  String? _selectedOperationType;

  String? _selectedHospital;

  @override
  void dispose() {
    _dateController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchPatientData();
    _fetchDisabledDates();
  }

  Future<void> _fetchPatientData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user logged in')),
      );
      return;
    }

    String email = user.email!;
    DocumentSnapshot patientDataDoc = await FirebaseFirestore.instance
        .collection('PatientData')
        .doc(email)
        .get();

    if (!patientDataDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient data not found')),
      );
      return;
    }

    _emailController.text = patientDataDoc.get('email');
    _nameController.text = patientDataDoc.get('name');
  }

  Future<List<DateTime>> _fetchFullyBookedDates() async {
    List<DateTime> fullyBookedDates = [];

    QuerySnapshot snapshot =
        await FirebaseFirestore.instance.collection('Appointments').get();

    // Use a map to count operations per date
    Map<String, int> operationsPerDate = {};

    for (var doc in snapshot.docs) {
      String date = doc['date'];

      if (operationsPerDate.containsKey(date)) {
        operationsPerDate[date] = operationsPerDate[date]! + 1;
      } else {
        operationsPerDate[date] = 1;
      }

      // If the date reaches 20 operations, mark it as fully booked
      if (operationsPerDate[date]! >= 5) {
        DateTime dateTime = DateFormat('dd-MM-yyyy').parse(date);
        fullyBookedDates.add(dateTime);
      }
    }

    return fullyBookedDates;
  }

  Future<void> _fetchDisabledDates() async {
    try {
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance.collection('Appointments').get();

      List<DateTime> disabledDates = [];
      DateTime today = DateTime.now();

      for (var doc in snapshot.docs) {
        DateTime date = DateFormat('dd-MM-yyyy').parse(doc.id);
        disabledDates.add(date);
      }

      // If today's date is in the disabled dates list, find the next available date
      if (disabledDates.contains(today)) {
        DateTime nextAvailableDate = today.add(const Duration(days: 1));
        while (disabledDates.contains(nextAvailableDate)) {
          nextAvailableDate = nextAvailableDate.add(const Duration(days: 1));
        }
        setState(() {
          _disabledDates = disabledDates;
          _selectedDate = nextAvailableDate;
          _dateController.text =
              DateFormat('dd-MM-yyyy').format(nextAvailableDate);
        });
      } else {
        setState(() {
          _disabledDates = disabledDates;
        });
      }
    } catch (e) {
      print("Error in _fetchDisabledDates: $e");
    }
  }

  final Set<DateTime> _usedDates =
      {}; // Populate this with your actual used dates

  Future<void> _selectDate(BuildContext context) async {
    List<DateTime> fullyBookedDates = await _fetchFullyBookedDates();

    DateTime initialDate = _getNextAvailableDate(DateTime.now());

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
      selectableDayPredicate: (DateTime date) {
        // Disable fully booked dates
        return !fullyBookedDates.contains(date);
      },
    );

    // Check if a date was picked and if it is different from the currently selected date
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd-MM-yyyy').format(picked);
        //_usedDates.add(picked); // Mark this date as used
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    // Check if a date is selected
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date first')),
      );
      return;
    }

    // Check if a hospital is selected
    if (_selectedHospital == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a hospital first')),
      );
      return;
    }

    // Show time picker dialog
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    // If a time is picked, proceed to check if it's available
    if (pickedTime != null) {
      bool isAvailable = await _isTimeSlotAvailable(
          _selectedDate!, pickedTime, _selectedHospital!);

      if (isAvailable) {
        setState(() {
          _timeController.text = pickedTime.format(context);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected time slot is not available')),
        );
      }
    }
  }

  DateTime _getNextAvailableDate(DateTime currentDate) {
    // Increment by one day until we find a date not in the disabled or used list
    while (_disabledDates.contains(currentDate) ||
        _usedDates.contains(currentDate)) {
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return currentDate;
  }

  Future<void> _saveAppointment() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (_selectedDate == null ||
        _selectedHospital == null ||
        _timeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    // Check if there are available slots
    int operationsCount = await _getOperationsCountForDay(_selectedDate!);
    if (operationsCount >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more slots available for this date')),
      );
      return;
    }

    TimeOfDay selectedTime = TimeOfDay(
      hour: int.parse(_timeController.text.split(":")[0]),
      minute: 0,
    );

    // Check if the time slot is available
    bool isAvailable = await _isTimeSlotAvailable(
        _selectedDate!, selectedTime, _selectedHospital!);

    if (!isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected time slot is not available')),
      );
      return;
    }

    // Save the appointment in Firestore (Appointments collection)
    // CRITICAL FIX: Include patientID in document ID to prevent collisions
    // If two patients book same date/time, they won't overwrite each other
    String dateStr = DateFormat('dd-MM-yyyy').format(_selectedDate!);
    String timeStr = _timeController.text.replaceAll(':', '-');
    String patientId = user?.uid ?? 'unknown';
    String docId = '$patientId-$dateStr-$timeStr-${DateTime.now().millisecondsSinceEpoch}';

    await FirebaseFirestore.instance.collection('Appointments').doc(docId).set({
      'patientID': user?.uid,
      'email': _emailController.text,
      'name': _nameController.text,
      'address': _addressController.text,
      'location': _locationController.text,
      'date': dateStr,
      'time': _timeController.text,
      'status': 'active',
      'phone': _normalizedPhoneNumber ?? _phoneController.text.trim(),
      'operationType': _selectedOperationType,
      'hospital': _selectedHospital,
      'reallocationStatus': 'Original', // New appointment is original
      'userResponse': null, // No response yet
    });

    // Log for debugging
    print('Appointment saved to Appointments collection.');

    // Save the appointment to the AppointmentGraph collection
    await _saveAppointmentToGraph(user?.uid, _selectedDate!);

    // Log success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appointment saved')),
    );

    // Close the screen
    Navigator.pop(context);
  }

  Future<void> _saveAppointmentToGraph(
      String? userId, DateTime appointmentDate) async {
    if (userId == null) {
      print("Error: User ID is null.");
      return;
    }

    // Format the date and time as a unique identifier
    String formattedDate = DateFormat('dd-MM-yyyy').format(appointmentDate);
    String formattedTime = _timeController.text.toString();
    String docId =
        '$userId-$formattedDate-${appointmentDate.millisecondsSinceEpoch}'; // Unique doc ID based on date and time
    String patientName = _nameController.text.trim();
    //String hospitalName = _selectedHospital;

    try {
      // Create a new document for this specific appointment in the AppointmentGraph collection
      await FirebaseFirestore.instance
          .collection('AppointmentGraph')
          .doc(docId)
          .set({
        'userId': userId,
        'appointmentDate': formattedDate,
        'time': formattedTime,
        'status': 'active',
        'patientName': patientName,
        'hospitalName': _selectedHospital
      });
      print('Appointment successfully saved to graph.');
    } catch (e) {
      print('Error saving appointment to graph: $e');
    }
  }

  final TextEditingController _timeController = TextEditingController();

  //for getting location work
  Future<void> _getUserLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location services are disabled.')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location permissions are permanently denied')),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    _locationController.text = '${position.latitude}, ${position.longitude}';
    await FirebaseFirestore.instance
        .collection('PatientData')
        .doc(_emailController.text)
        .update({
      'location': GeoPoint(position.latitude, position.longitude),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Location saved successfully')),
    );
  }

  //operation per day
  Future<int> _getOperationsCountForDay(DateTime date) async {
    String formattedDate = DateFormat('dd-MM-yyyy').format(date);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('Appointments')
        .where('date', isEqualTo: formattedDate)
        .get();

    return snapshot.docs.length; // Return the count of operations
  }

  //check if time slot is available and every operation have tow hours gape
  Future<bool> _isTimeSlotAvailable(
      DateTime date, TimeOfDay time, String selectedHospital) async {
    String formattedDate = DateFormat('dd-MM-yyyy').format(date);

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('Appointments')
        .where('date', isEqualTo: formattedDate)
        .get();

    DateTime selectedDateTime =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);

    for (var doc in snapshot.docs) {
      DateTime existingTime =
          DateFormat('dd-MM-yyyy HH:mm').parse('${doc['date']} ${doc['time']}');
      String existingHospital = doc['hospital'];

      // Check if the selected time is within 2 hours of any existing time for the same hospital
      if ((selectedDateTime.isBefore(existingTime.add(Duration(hours: 2))) &&
              selectedDateTime
                  .isAfter(existingTime.subtract(Duration(hours: 2)))) &&
          selectedHospital == existingHospital) {
        return false; // Time slot is not available
      }
    }

    return true; // Time slot is available
  }

  @override
  Widget build(BuildContext context) {
    //String? _selectedOperationType;
    final List<String> _operationTypes = [
      'Surgery',
      'Consultation',
      'Follow-up'
    ];
    final List<String> _hospitalsType = [
      'h1',
      'h2',
      'h3'
    ]; // To store hospital names
    DropdownButtonFormField<String> _buildOperationTypeDropdown() {
      return DropdownButtonFormField<String>(
        value: _selectedOperationType,
        decoration: InputDecoration(
          labelText: 'Operation Type',
          labelStyle: TextStyle(color: AppColors.blackColor),
        ),
        items: _operationTypes.map((String type) {
          return DropdownMenuItem<String>(
            value: type,
            child: Text(type),
          );
        }).toList(),
        onChanged: (String? newValue) {
          setState(() {
            _selectedOperationType = newValue!;
          });
        },
      );
    }

    DropdownButtonFormField<String> _buildHospitalTypeDropdown() {
      return DropdownButtonFormField<String>(
        value: _selectedHospital,
        decoration: InputDecoration(
          labelText: 'Hospital',
          labelStyle: TextStyle(color: AppColors.blackColor),
        ),
        items: _hospitalsType.map((String type) {
          return DropdownMenuItem<String>(
            value: type,
            child: Text(type),
          );
        }).toList(),
        onChanged: (String? newValue) {
          setState(() {
            _selectedHospital = newValue!;
          });
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Appointment',
            style: TextStyle(color: AppColors.whiteColor)),
        iconTheme: const IconThemeData(color: AppColors.whiteColor),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            //Select Date
            TextField(
              controller: _dateController,
              style: const TextStyle(color: AppColors.blackColor),
              decoration: InputDecoration(
                labelText: 'Date',
                labelStyle: const TextStyle(color: AppColors.blackColor),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, color: Colors.red),
                  onPressed: () => _selectDate(context),
                ),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 20),
            //select hospital
            _buildHospitalTypeDropdown(),

            const SizedBox(height: 20),
            //select operation type
            _buildOperationTypeDropdown(),

            const SizedBox(height: 20),
            //Select Time
            TextField(
              controller: _timeController,
              style: const TextStyle(color: AppColors.blackColor),
              decoration: InputDecoration(
                labelText: 'Time',
                labelStyle: const TextStyle(color: AppColors.blackColor),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time, color: Colors.red),
                  onPressed: () => _selectTime(context),
                ),
              ),
              readOnly: true,
            ),
            //select Email
            TextField(
              controller: _emailController,
              style: const TextStyle(color: AppColors.blackColor),
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: AppColors.blackColor),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 20),
            //select Name
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppColors.blackColor),
              decoration: const InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: AppColors.blackColor),
              ),
              readOnly: true,
            ),
            const SizedBox(height: 20),
            //select Address
            TextField(
              controller: _addressController,
              autofocus: false,
              style: const TextStyle(color: AppColors.blackColor),
              decoration: InputDecoration(
                  labelText: 'Address',
                  labelStyle: TextStyle(color: AppColors.blackColor),
                  suffixIcon: IconButton(
                      onPressed: _getUserLocation,
                      icon: Icon(
                        Icons.location_on,
                        color: Colors.red,
                      ))),
            ),
            const SizedBox(height: 20),
            //select Phone Number
            IntlPhoneField(
              controller: _phoneController,
              autofocus: false,
              decoration: const InputDecoration(
                labelText: 'Phone',
                labelStyle: TextStyle(color: AppColors.blackColor),
              ),
              initialCountryCode: 'US',
              onChanged: (phone) {
                // Store the complete number in E.164 format for proper SMS matching
                _normalizedPhoneNumber = phone.completeNumber;
                print('Phone number (E.164): ${phone.completeNumber}');
              },
            ),
            const SizedBox(height: 20),
            //save Appointment
            ElevatedButton(
              onPressed: _saveAppointment,
              child: const Text('Save Appointment'),
            ),
          ],
        ),
      ),
    );
  }
}
