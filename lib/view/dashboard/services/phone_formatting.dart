/// Format phone number to E.164 format
/// Handles various formats and preserves existing E.164 format
/// Convert scientific notation to regular number string
/// Handles Excel's scientific notation like "9.27E+11" -> "927000000000"
String convertScientificNotation(String value) {
  if (value.isEmpty) return value;
  
  // Check if it's in scientific notation (contains 'E' or 'e' followed by + or -)
  if (RegExp(r'[Ee][\+\-]?\d+').hasMatch(value)) {
    try {
      // Try to parse as double first (handles scientific notation)
      final numValue = double.parse(value);
      // Convert to integer string (remove decimal if any)
      return numValue.toInt().toString();
    } catch (e) {
      print('⚠️ Warning: Could not parse scientific notation: $value');
      return value; // Return original if parsing fails
    }
  }
  return value; // Not scientific notation, return as is
}

/// Normalises a phone number to E.164 for a Pakistan + UK clinic.
///
/// Used by the CSV import, the SMS senders and the edit-appointment dialog.
/// Rules (after stripping everything except digits and '+'):
/// - already '+...'                       -> kept
/// - '00...'                              -> '+...'
/// - '03' + 9 digits (PK local mobile)    -> '+92' + number without the 0
/// - '07' + 9 digits (UK local mobile)    -> '+44' + number without the 0
/// - '92' + 10 digits                     -> '+92...'
/// - '44' + 10 digits                     -> '+44...'
/// - '3' + 9 digits (PK mobile, no 0)     -> '+92...'
/// - '7' + 9 digits (UK mobile, no 0)     -> '+44...'
/// - otherwise the older fallbacks below (US 10/11 digits, '+' prefix, ...).
String formatPhoneToE164(String phone) {
  if (phone.isEmpty) return phone;

  // First, convert scientific notation if present (Excel format)
  phone = convertScientificNotation(phone);

  // Remove all non-digit characters except +
  String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '').trim();

  // If already in E.164 format (starts with +), return as is
  if (cleaned.startsWith('+')) {
    return cleaned;
  }

  // If starts with 00 (international format), replace with +
  if (cleaned.startsWith('00')) {
    return '+' + cleaned.substring(2);
  }

  // Local mobile formats (11 digits with leading 0)
  if (cleaned.length == 11) {
    if (cleaned.startsWith('03')) {
      return '+92' + cleaned.substring(1); // Pakistan: 03XX XXXXXXX
    }
    if (cleaned.startsWith('07')) {
      return '+44' + cleaned.substring(1); // UK: 07XXX XXXXXX
    }
    if (cleaned.startsWith('0')) {
      return '+44' + cleaned.substring(1); // UK landline: 020 XXXX XXXX
    }
  }

  // Country code without '+' (12 digits)
  if (cleaned.length == 12 &&
      (cleaned.startsWith('92') || cleaned.startsWith('44'))) {
    return '+' + cleaned;
  }

  // Mobile numbers missing both the leading 0 and the country code
  if (cleaned.length == 10) {
    if (cleaned.startsWith('3')) {
      return '+92' + cleaned; // Pakistan: 3XX XXXXXXX
    }
    if (cleaned.startsWith('7')) {
      return '+44' + cleaned; // UK: 7XXX XXXXXX
    }
  }

  // If starts with 0 and longer than 11, might be UK or other country
  if (cleaned.startsWith('0') && cleaned.length > 11) {
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

  // For 12-digit numbers starting with 9 (but not 92, handled above)
  if (cleaned.length == 12 && cleaned.startsWith('9')) {
    return '+92' + cleaned; // Add country code, Twilio will validate
  }

  // If we can't determine, try to return with + prefix if it looks like a valid number
  if (cleaned.length >= 10 && cleaned.length <= 15 && !cleaned.startsWith('0')) {
    // Assume it might be a valid international number missing the +
    return '+' + cleaned;
  }

  // If we can't determine, try to add + prefix if it looks like a valid international number
  // This is more aggressive for CSV imports to ensure Twilio-acceptable format
  if (cleaned.length >= 10 && cleaned.length <= 15) {
    // For numbers that look valid but don't match specific patterns, add + prefix
    // This ensures CSV-imported numbers are in E.164 format
    print('Info: Adding + prefix to phone number: $phone -> +$cleaned');
    return '+' + cleaned;
  }

  // If we still can't determine, return original (might already be in correct format)
  // Log a warning in production
  print('Warning: Could not normalize phone number: $phone (cleaned: $cleaned, length: ${cleaned.length})');
  // Try to add + anyway if it doesn't have one and looks numeric
  if (!phone.startsWith('+') && cleaned.isNotEmpty) {
    return '+' + cleaned;
  }
  return phone; // Return original as last resort
}
