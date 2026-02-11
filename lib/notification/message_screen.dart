import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';
import 'package:my_appointment/view/patient-views/appointment_graph_screen.dart';
import 'package:my_appointment/view/patient-views/slot_claim_screen.dart';

class MessageScreen extends StatelessWidget {
  final RemoteMessage message;
  
  const MessageScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Details'),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notification Title
            if (message.notification?.title != null)
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Title',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.notification!.title!,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            
            // Notification Body
            if (message.notification?.body != null)
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.notification!.body!,
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            
            // Notification Type
            if (message.data['type'] != null)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notification Type',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getTypeLabel(message.data['type']),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            
            // Additional Data
            if (message.data.isNotEmpty)
              Card(
                color: Colors.purple.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Additional Information',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...message.data.entries.map((entry) {
                        if (entry.key == 'type') return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${entry.key}:',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            
            // Message ID
            Card(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Message ID',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message.messageId ?? 'N/A',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _handleNotificationAction(context, message);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('View Details'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'appointment_cancellation':
        return 'Appointment Cancellation';
      case 'appointment_reminder':
        return 'Appointment Reminder';
      case 'view_graph':
        return 'Graph Update';
      case 'slot_available':
        return 'Slot Available';
      case 'cascaded_slot_available':
        return 'Cascaded Slot Available';
      default:
        return type ?? 'Unknown';
    }
  }

  void _handleNotificationAction(BuildContext context, RemoteMessage message) {
    final type = message.data['type'];
    
    // Close the current screen first
    Navigator.pop(context);
    
    // Then navigate to the appropriate screen
    if (type == 'appointment_cancellation' || type == 'appointment_reminder') {
      // Navigate to patient home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const PatientHomeViewNew(),
        ),
      );
    } else if (type == 'view_graph') {
      // Navigate to graph screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AppointmentGraphScreen(),
        ),
      );
    } else if (type == 'slot_available' || type == 'cascaded_slot_available') {
      // Enhanced deep linking: Check for newSlotId in payload
      final newSlotId = message.data['newSlotId'];
      
      // If newSlotId is provided, fetch slot details from Firestore
      if (newSlotId != null && newSlotId.isNotEmpty) {
        // Navigate to slot claiming screen with newSlotId
        // The SlotClaimScreen will fetch details using the slot ID
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SlotClaimScreen(
              availableDate: message.data['availableDate'] ?? '',
              availableTime: message.data['availableTime'] ?? '',
              hospital: message.data['hospital'] ?? '',
              operationType: message.data['operationType'] ?? '',
              notificationType: type,
              newSlotId: newSlotId, // Pass newSlotId for deep linking
            ),
          ),
        );
      } else {
        // Fallback: Use provided date/time data directly
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SlotClaimScreen(
              availableDate: message.data['availableDate'] ?? '',
              availableTime: message.data['availableTime'] ?? '',
              hospital: message.data['hospital'] ?? '',
              operationType: message.data['operationType'] ?? '',
              notificationType: type,
            ),
          ),
        );
      }
    }
  }
}
