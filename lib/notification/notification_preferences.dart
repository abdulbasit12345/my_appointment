import 'package:shared_preferences/shared_preferences.dart';

/// Manages notification preferences and settings
class NotificationPreferences {
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keySoundEnabled = 'notification_sound_enabled';
  static const String _keyVibrationEnabled = 'notification_vibration_enabled';
  static const String _keyAppointmentReminders = 'appointment_reminders_enabled';
  static const String _keyCancellationAlerts = 'cancellation_alerts_enabled';
  static const String _keyGraphUpdates = 'graph_updates_enabled';

  static Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  // General notification settings
  static Future<bool> areNotificationsEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyNotificationsEnabled) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyNotificationsEnabled, enabled);
  }

  // Sound settings
  static Future<bool> isSoundEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keySoundEnabled) ?? true;
  }

  static Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keySoundEnabled, enabled);
  }

  // Vibration settings
  static Future<bool> isVibrationEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyVibrationEnabled) ?? true;
  }

  static Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyVibrationEnabled, enabled);
  }

  // Notification type preferences
  static Future<bool> areAppointmentRemindersEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyAppointmentReminders) ?? true;
  }

  static Future<void> setAppointmentRemindersEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyAppointmentReminders, enabled);
  }

  static Future<bool> areCancellationAlertsEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyCancellationAlerts) ?? true;
  }

  static Future<void> setCancellationAlertsEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyCancellationAlerts, enabled);
  }

  static Future<bool> areGraphUpdatesEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_keyGraphUpdates) ?? true;
  }

  static Future<void> setGraphUpdatesEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_keyGraphUpdates, enabled);
  }

  // Check if a specific notification type should be shown
  static Future<bool> shouldShowNotification(String notificationType) async {
    if (!await areNotificationsEnabled()) return false;

    switch (notificationType) {
      case 'appointment_reminder':
        return await areAppointmentRemindersEnabled();
      case 'appointment_cancellation':
        return await areCancellationAlertsEnabled();
      case 'view_graph':
        return await areGraphUpdatesEnabled();
      default:
        return true;
    }
  }
}

