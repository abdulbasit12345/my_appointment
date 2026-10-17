/**
 * Pure appointment helpers shared by the Cloud Functions in index.js.
 * No Firebase access here, so everything can be unit tested (test/).
 */

// Appointment date/time strings are UK clinic local time.
const CLINIC_TIME_ZONE = 'Europe/London';

// Every stored status meaning the patient still holds their slot.
// Keep in sync with AppointmentStatus.bookedValues in the Flutter app.
const BOOKED_STATUSES = [
  'active',
  'ACTIVE',
  'BOOKED',
  'CONFIRMED',
  'Confirmed_Priority',
  'reminder_sent_awaiting_reply',
  'REMINDER_SENT_AWAITING_REPLY',
  'awaitingReply',
  'no response',
];

// Keep in sync with AppointmentStatus.cancelledValues in the Flutter app.
const CANCELLED_STATUSES = ['cancelled', 'CANCELLED', 'Cancelled', 'canceled'];

const BOOKED_LOWER = new Set(BOOKED_STATUSES.map((s) => s.toLowerCase()));
const CANCELLED_LOWER = new Set(CANCELLED_STATUSES.map((s) => s.toLowerCase()));

function isBooked(status) {
  return typeof status === 'string' && BOOKED_LOWER.has(status.trim().toLowerCase());
}

function isCancelled(status) {
  return typeof status === 'string' && CANCELLED_LOWER.has(status.trim().toLowerCase());
}

/**
 * Short patient id for activity messages. Web/CSV bookings have no
 * patientID, which previously crashed the SMS reply handler.
 */
function shortId(patientId) {
  return patientId ? `${String(patientId).substring(0, 6)}...` : 'no app account';
}

/** Milliseconds [timeZone] is ahead of UTC at [date]. */
function timeZoneOffsetMs(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(date);
  const v = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  const asUtc = Date.UTC(+v.year, +v.month - 1, +v.day, +v.hour, +v.minute, +v.second);
  return asUtc - (date.getTime() - date.getMilliseconds());
}

/** The instant at which the wall-clock time happens in [timeZone]. */
function zonedTimeToDate(year, monthIndex, day, hours, minutes, timeZone) {
  const wallClockAsUtc = Date.UTC(year, monthIndex, day, hours, minutes);
  const offset = timeZoneOffsetMs(new Date(wallClockAsUtc), timeZone);
  let result = wallClockAsUtc - offset;
  // Around a DST change the offset at the result can differ from the guess
  const correctedOffset = timeZoneOffsetMs(new Date(result), timeZone);
  if (correctedOffset !== offset) result = wallClockAsUtc - correctedOffset;
  return new Date(result);
}

/**
 * Parse "dd-MM-yyyy" + "hh:mm a" / "HH:mm" / "HH:mm:ss" (clinic local time) into a Date,
 * or null if either part is invalid (no rolling over of e.g. 32-01-2025).
 */
function parseAppointmentDateTime(dateStr, timeStr, timeZone = CLINIC_TIME_ZONE) {
  if (typeof dateStr !== 'string' || typeof timeStr !== 'string') return null;

  const dateMatch = dateStr.trim().match(/^(\d{1,2})-(\d{1,2})-(\d{4})$/);
  if (!dateMatch) return null;
  const day = parseInt(dateMatch[1], 10);
  const monthIndex = parseInt(dateMatch[2], 10) - 1;
  const year = parseInt(dateMatch[3], 10);
  const check = new Date(Date.UTC(year, monthIndex, day));
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== monthIndex ||
      check.getUTCDate() !== day) {
    return null;
  }

  // Seconds are allowed and ignored ('14:30:00', e.g. from Excel CSVs)
  const timeMatch = timeStr.trim().match(/^(\d{1,2}):(\d{2})(?::[0-5]\d)?\s*(AM|PM)?$/i);
  if (!timeMatch) return null;
  let hours = parseInt(timeMatch[1], 10);
  const minutes = parseInt(timeMatch[2], 10);
  const period = timeMatch[3] ? timeMatch[3].toUpperCase() : null;
  if (minutes > 59) return null;
  if (period) {
    if (hours < 1 || hours > 12) return null;
    if (period === 'PM' && hours !== 12) hours += 12;
    if (period === 'AM' && hours === 12) hours = 0;
  } else if (hours > 23) {
    return null;
  }

  return zonedTimeToDate(year, monthIndex, day, hours, minutes, timeZone);
}

/** Value `appointmentAt` should hold for this document (Date or null). */
function desiredAppointmentAt(data) {
  if (!data) return null;
  return parseAppointmentDateTime(data.date, data.time);
}

/** True when this write moved an appointment from booked to cancelled. */
function isNewCancellation(beforeData, afterData) {
  return Boolean(beforeData && afterData &&
    isBooked(beforeData.status) && isCancelled(afterData.status));
}

/**
 * App patients (patientID set) booked after the freed slot, excluding the
 * cancelled appointment and its own patient.
 * @param {Array<{id: string, data: object}>} appointments booked appointments
 */
function selectPatientIdsAfterSlot(appointments, cancelledAppointmentId, cancelledData) {
  const slotDateTime = parseAppointmentDateTime(cancelledData.date, cancelledData.time);
  const patientIds = new Set();
  if (!slotDateTime) return patientIds;

  for (const {id, data} of appointments) {
    if (id === cancelledAppointmentId) continue;
    if (!data.patientID || data.patientID === cancelledData.patientID) continue;
    // CSV-imported patients have placeholder ids and no app (no device token)
    if (String(data.patientID).startsWith('csv-import-')) continue;
    if (!isBooked(data.status)) continue;
    const appointmentDateTime = parseAppointmentDateTime(data.date, data.time);
    if (appointmentDateTime && appointmentDateTime > slotDateTime) {
      patientIds.add(data.patientID);
    }
  }
  return patientIds;
}

/**
 * FCM messages offering a freed slot. Same payload the app used to send, so
 * tapping it opens the slot claim screen.
 */
function buildSlotOfferMessages(tokens, cancelledData) {
  const slotDate = cancelledData.date;
  const slotTime = cancelledData.time;
  const hospital = cancelledData.hospital || '';
  const operationType = cancelledData.operationType || '';
  return tokens.map((token) => ({
    token,
    notification: {
      title: 'Earlier Appointment Slot Available',
      body: `An earlier appointment slot has become available on ${slotDate} at ${slotTime} for ${operationType} at ${hospital}. You can claim this slot to move your appointment forward. Tap to view details.`,
    },
    android: {
      priority: 'high',
      notification: {channelId: 'slot_opportunities', sound: 'default'},
    },
    apns: {payload: {aps: {sound: 'default', badge: 1}}},
    data: {
      type: 'slot_available',
      availableDate: String(slotDate),
      availableTime: String(slotTime),
      hospital: String(hospital),
      operationType: String(operationType),
      slotDocumentId: '',
    },
  }));
}

/**
 * Helper function to normalize phone number to E.164 format
 * Handles various formats and ensures consistent matching
 */
function normalizePhoneNumber(phone) {
  if (!phone) return null;

  // Remove all non-digit characters except +
  const cleaned = phone.replace(/[^\d+]/g, '').trim();

  // If already in E.164 format (starts with +), return as is
  if (cleaned.startsWith('+')) {
    return cleaned;
  }

  // If starts with 00 (international format), replace with +
  if (cleaned.startsWith('00')) {
    return '+' + cleaned.substring(2);
  }

  // Handle Pakistan mobile numbers (country code 92)
  // Pakistan mobile: 03XX XXXXXXX -> +92 3XX XXXXXXX
  if (cleaned.startsWith('0') && cleaned.length === 11) {
    if (cleaned.startsWith('03')) {
      return '+92' + cleaned.substring(1);
    }
  }

  // If starts with 92 and is 12 digits, add +
  if (cleaned.startsWith('92') && cleaned.length === 12) {
    return '+' + cleaned;
  }

  // If we can't determine, try to add + prefix if it looks valid
  if (cleaned.length >= 10 && cleaned.length <= 15 && !cleaned.startsWith('0')) {
    return '+' + cleaned;
  }

  // Return original if we can't normalize
  return phone;
}

/** Phone spellings an appointment may be stored under, most likely first. */
function phoneVariations(fromPhone) {
  const normalizedPhone = normalizePhoneNumber(fromPhone);
  const variations = [
    normalizedPhone,
    fromPhone,
    normalizedPhone?.replace('+', ''),
    fromPhone?.replace('+', ''),
    // Pakistani number variations
    normalizedPhone?.replace(/^\+92/, '0'), // +923477974809 -> 03477974809
    normalizedPhone?.replace(/^\+92/, '92'), // +923477974809 -> 923477974809
    fromPhone?.replace(/^\+92/, '0'), // Direct from Twilio
    fromPhone?.replace(/^\+92/, '92'), // Direct from Twilio without +
    // Also try with spaces removed (in case of formatting)
    normalizedPhone?.replace(/\s/g, ''),
    fromPhone?.replace(/\s/g, ''),
  ].filter(Boolean);
  return [...new Set(variations)];
}

/** 'confirm' | 'cancel' | 'priority' | null for an SMS reply body. */
function parseSmsReply(bodyText) {
  const cleanReply = (bodyText || '').trim().toLowerCase();
  if (['1', 'confirm', 'yes'].includes(cleanReply)) return 'confirm';
  if (['2', 'cancel', 'no'].includes(cleanReply)) return 'cancel';
  if (['3', 'reschedule', 'change'].includes(cleanReply)) return 'priority';
  return null;
}

/** Firestore update for a reply action; [serverTimestamp] is FieldValue.serverTimestamp(). */
function buildReplyUpdate(action, serverTimestamp) {
  switch (action) {
    case 'confirm':
      return {
        status: 'CONFIRMED', // Uppercase to match UI query
        userResponse: 'Confirmed',
        lastUpdated: serverTimestamp,
      };
    case 'cancel':
      return {
        status: 'cancelled',
        userResponse: 'Cancelled',
        lastUpdated: serverTimestamp,
      };
    case 'priority':
      return {
        status: 'Confirmed_Priority',
        userResponse: 'Priority_Request',
        isPriority: true,
        priorityJoinedAt: serverTimestamp,
        lastUpdated: serverTimestamp,
      };
    default:
      return null;
  }
}

/**
 * Which of a phone number's appointments an SMS reply is about.
 * Cancelled appointments are never picked (a "1" must not reactivate a slot
 * that may already be reallocated). Prefers one awaiting a reminder reply,
 * then the nearest upcoming one, then the most recent past one. (Sorting by
 * the 'dd-MM-yyyy' string, as before, ordered by day of month.)
 * @param {Array<{id: string, data: object}>} candidates
 */
function pickAppointmentForReply(candidates, now = new Date()) {
  candidates = candidates.filter(({data}) => !isCancelled(data.status));
  if (!candidates.length) return null;

  const awaiting = candidates.filter(({data}) =>
    ['reminder_sent_awaiting_reply', 'awaitingreply']
      .includes(String(data.status || '').toLowerCase()));
  const pool = awaiting.length ? awaiting : candidates;

  const withTime = pool.map((c) => ({
    candidate: c,
    at: parseAppointmentDateTime(c.data.date, c.data.time),
  }));
  const upcoming = withTime
    .filter((x) => x.at && x.at >= now)
    .sort((a, b) => a.at - b.at);
  if (upcoming.length) return upcoming[0].candidate;

  const past = withTime
    .filter((x) => x.at)
    .sort((a, b) => b.at - a.at);
  if (past.length) return past[0].candidate;

  return pool[0];
}

module.exports = {
  CLINIC_TIME_ZONE,
  BOOKED_STATUSES,
  CANCELLED_STATUSES,
  isBooked,
  isCancelled,
  shortId,
  parseAppointmentDateTime,
  desiredAppointmentAt,
  isNewCancellation,
  selectPatientIdsAfterSlot,
  buildSlotOfferMessages,
  normalizePhoneNumber,
  phoneVariations,
  parseSmsReply,
  buildReplyUpdate,
  pickAppointmentForReply,
};
