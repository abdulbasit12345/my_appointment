/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });

const {onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const {
  BOOKED_STATUSES,
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
} = require("./lib/appointments");

// Initialize admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

// Helper function to get Twilio credentials
// Uses hardcoded values from Firebase config (migrated from functions.config())
// TODO: Migrate to proper environment variables or secrets for production
function getTwilioConfig() {
  // These values are from: firebase functions:config:get twilio
  // Using the values that were previously in Firebase config
  const finalAccountSid = "AC6c6474607c3b8298aa4e69eed421577a";
  const finalAuthToken = "b92fec67c37bc821055d9a9311964fff";
  const finalPhoneNumber = "+447414141704"; // Using phone_number from config
  
  // Try environment variables first (if set)
  const envAccountSid = process.env.TWILIO_ACCOUNT_SID;
  const envAuthToken = process.env.TWILIO_AUTH_TOKEN;
  const envPhoneNumber = process.env.TWILIO_PHONE_NUMBER;
  
  if (envAccountSid && envAuthToken && envPhoneNumber) {
    logger.info('Using environment variables for Twilio config');
    return {
      finalAccountSid: envAccountSid,
      finalAuthToken: envAuthToken,
      finalPhoneNumber: envPhoneNumber,
    };
  }
  
  // Fallback to hardcoded values
  logger.info('Using hardcoded Twilio config (from Firebase config)');
  return {
    finalAccountSid,
    finalAuthToken,
    finalPhoneNumber,
  };
}

/**
 * HTTP Callable function to send custom SMS messages
 * Used by Quick Actions menu in dashboard
 * 
 * Parameters:
 * - phone: Phone number in E.164 format (e.g., "+1234567890")
 * - message: Custom message text to send
 * 
 * Returns:
 * - success: boolean
 * - message: string
 */
exports.sendCustomSms = onCall(async (request) => {
  try {
    const {phone, message} = request.data;

    // Validate parameters
    if (!phone || !message) {
      return {
        success: false,
        message: 'Missing required parameters: phone and message are required',
      };
    }

    // Get Twilio configuration using helper function
    const twilioCreds = getTwilioConfig();
    
    if (!twilioCreds) {
      logger.error('Twilio configuration missing - checked module cache, dynamic load, and env vars');
      return {
        success: false,
        message: 'SMS service not configured. Please set Twilio credentials in Firebase config.',
      };
    }
    
    const { finalAccountSid, finalAuthToken, finalPhoneNumber } = twilioCreds;

    const twilio = require('twilio');
    const client = twilio(finalAccountSid, finalAuthToken);

    // Send SMS via Twilio
    try {
      const twilioMessage = await client.messages.create({
        body: message,
        from: finalPhoneNumber,
        to: phone,
      });

      logger.info('Custom SMS sent successfully', {
        sid: twilioMessage.sid,
        to: phone,
      });

      return {
        success: true,
        message: 'SMS sent successfully',
        sid: twilioMessage.sid,
      };
    } catch (twilioError) {
      logger.error('Twilio error sending SMS', twilioError);
      return {
        success: false,
        message: `Failed to send SMS: ${twilioError.message}`,
      };
    }
  } catch (error) {
    logger.error('Error in sendCustomSms', error);
    return {
      success: false,
      message: `Error: ${error.message}`,
    };
  }
});

/**
 * HTTP Callable function to send SMS reminders
 * Used by the "Send Reminder" button in dashboard
 * 
 * Parameters:
 * - patientPhone: Phone number in E.164 format (e.g., "+1234567890")
 * - slotStatus: Current appointment status
 * - patientId: Patient ID
 * - appointmentDate: Appointment date string
 * - appointmentTime: Appointment time string
 * 
 * Returns:
 * - success: boolean
 * - message: string
 */
exports.sendSmsReminder = onCall(async (request) => {
  try {
    const {patientPhone, slotStatus, patientId, appointmentDate, appointmentTime} = request.data;

    // Validate parameters
    if (!patientPhone || !appointmentDate || !appointmentTime) {
      return {
        success: false,
        message: 'Missing required parameters: patientPhone, appointmentDate, and appointmentTime are required',
      };
    }

    // Get Twilio configuration using helper function
    const twilioCreds = getTwilioConfig();
    
    if (!twilioCreds) {
      logger.error('Twilio configuration missing for sendSmsReminder');
      return {
        success: false,
        message: 'SMS service not configured. Please set Twilio credentials in Firebase config.',
      };
    }
    
    const { finalAccountSid, finalAuthToken, finalPhoneNumber } = twilioCreds;

    const twilio = require('twilio');
    const client = twilio(finalAccountSid, finalAuthToken);

    // Format the reminder message
    let messageBody = `Hi! This is a reminder for your medical appointment on ${appointmentDate} at ${appointmentTime}. `;
    messageBody += `Reply: 1 to confirm, 2 to cancel, or 3 to request a different time. `;
    messageBody += `Please reply within 24 hours.`;

    // Send SMS via Twilio
    try {
      const twilioMessage = await client.messages.create({
        body: messageBody,
        from: finalPhoneNumber,
        to: patientPhone,
      });

      logger.info('SMS reminder sent successfully', {
        sid: twilioMessage.sid,
        to: patientPhone,
        patientId: patientId,
      });

      // Update appointment status in Firestore if needed
      if (patientId && appointmentDate) {
        try {
          const appointmentsRef = admin.firestore().collection('Appointments');
          const querySnapshot = await appointmentsRef
            .where('patientID', '==', patientId)
            .where('date', '==', appointmentDate)
            .limit(1)
            .get();

          if (!querySnapshot.empty) {
            const appointmentDoc = querySnapshot.docs[0];
            await appointmentDoc.ref.update({
              status: 'reminder_sent_awaiting_reply',
              lastReminderSent: admin.firestore.FieldValue.serverTimestamp(),
            });
            logger.info('Updated appointment status to reminder_sent_awaiting_reply');
          }
        } catch (firestoreError) {
          logger.warn('Could not update appointment status in Firestore:', firestoreError);
          // Don't fail the function if Firestore update fails
        }
      }

      return {
        success: true,
        message: 'SMS reminder sent successfully',
        sid: twilioMessage.sid,
      };
    } catch (twilioError) {
      logger.error('Twilio error sending SMS reminder', twilioError);
      return {
        success: false,
        message: `Failed to send SMS: ${twilioError.message}`,
      };
    }
  } catch (error) {
    logger.error('Error in sendSmsReminder', error);
    return {
      success: false,
      message: `Error: ${error.message}`,
    };
  }
});

/**
 * Helper function to log activity to DashboardMetrics
 */
async function logActivity(message, activityType = 'sms_reply') {
  try {
    const metricsRef = admin.firestore()
      .collection('DashboardMetrics')
      .doc('metrics');
    
    await metricsRef.collection('activityLog').add({
      message: message,
      type: activityType,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    logger.info('Activity logged:', { message, activityType });
  } catch (error) {
    logger.error('Error logging activity:', error);
    // Don't fail if logging fails
  }
}

/**
 * Offer a freed slot to app patients booked after it.
 * Server-side replacement for the app's old client-side cancellation
 * cascade (same FCM payload, so tapping it opens the slot claim screen).
 * Returns the number of notifications sent.
 */
async function notifyPatientsOfFreedSlot(cancelledAppointmentId, cancelledData) {
  if (!parseAppointmentDateTime(cancelledData.date, cancelledData.time)) {
    logger.warn('Cannot offer freed slot: invalid date/time', {
      appointmentId: cancelledAppointmentId,
      date: cancelledData.date,
      time: cancelledData.time,
    });
    return 0;
  }

  const db = admin.firestore();
  const snapshot = await db
    .collection('Appointments')
    .where('status', 'in', BOOKED_STATUSES)
    .get();

  const patientIds = selectPatientIdsAfterSlot(
    snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()})),
    cancelledAppointmentId,
    cancelledData,
  );
  if (patientIds.size === 0) return 0;

  const tokenDocs = await Promise.all(
    [...patientIds].map((id) => db.collection('TokenData').doc(id).get()),
  );
  const tokens = [...new Set(
    tokenDocs
      .filter((doc) => doc.exists && doc.data().deviceToken)
      .map((doc) => String(doc.data().deviceToken)),
  )];
  if (tokens.length === 0) return 0;

  const messages = buildSlotOfferMessages(tokens, cancelledData);
  let sent = 0;
  for (let i = 0; i < messages.length; i += 500) {
    const response = await admin.messaging().sendEach(messages.slice(i, i + 500));
    sent += response.successCount;
  }
  return sent;
}

/**
 * Runs on every write to an appointment:
 * 1. Keeps `appointmentAt` (a Timestamp, UK clinic time) in sync with the
 *    'dd-MM-yyyy' date and 'hh:mm a' time strings, whoever wrote them
 *    (app, dashboard, CSV import, SMS). Removed if the strings are invalid.
 * 2. When an appointment goes from booked to cancelled (in the app, by SMS
 *    reply or from the dashboard), offers the freed slot to the patients
 *    booked after it.
 * Its own writes re-trigger it, but then nothing changes so it stops.
 */
exports.onAppointmentWritten = onDocumentWritten('Appointments/{appointmentId}', async (event) => {
  const after = event.data?.after;
  if (!after || !after.exists) return;

  const appointmentId = event.params.appointmentId;
  const afterData = after.data();
  const beforeData = event.data.before?.exists ? event.data.before.data() : null;

  // 1. appointmentAt
  try {
    const desired = desiredAppointmentAt(afterData);
    const currentMs = afterData.appointmentAt?.toDate?.().getTime() ?? null;
    const desiredMs = desired ? desired.getTime() : null;
    if (currentMs !== desiredMs) {
      await after.ref.update({
        appointmentAt: desired ?
          admin.firestore.Timestamp.fromDate(desired) :
          admin.firestore.FieldValue.delete(),
      });
    }
  } catch (error) {
    logger.error('Error syncing appointmentAt', {appointmentId, error: error.message});
  }

  // 2. Freed slot offers
  if (!isNewCancellation(beforeData, afterData)) return;
  try {
    // Triggers can be delivered more than once; offer once per event
    const firstDelivery = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(after.ref);
      if (snap.get('lastSlotOfferEventId') === event.id) return false;
      tx.update(after.ref, {lastSlotOfferEventId: event.id});
      return true;
    });
    if (!firstDelivery) return;

    const notified = await notifyPatientsOfFreedSlot(appointmentId, afterData);
    logger.info('Freed slot offered to later patients', {appointmentId, notified});
    if (notified > 0) {
      await logActivity(
        `Slot ${afterData.date} ${afterData.time} freed by a cancellation was offered to ${notified} patient(s)`,
        'slot_offer',
      );
    }
  } catch (error) {
    logger.error('Error offering freed slot', {appointmentId, error: error.message});
  }
});

/**
 * HTTP webhook endpoint to handle incoming SMS replies from Twilio
 * 
 * Twilio sends POST requests with:
 * - From: Phone number in E.164 format (e.g., "+447414141704")
 * - Body: Reply text (e.g., "1", "2", "3")
 * 
 * This function:
 * 1. Normalizes the phone number
 * 2. Finds the appointment in Firestore
 * 3. Processes the reply (1=confirm, 2=cancel, 3=reschedule)
 * 4. Updates appointment status and userResponse
 * 5. Logs activity
 * 
 * Returns TwiML response to Twilio
 */
exports.handleSmsReply = onRequest(async (req, res) => {
  try {
    logger.info('=== SMS REPLY HANDLER CALLED ===');
    
    // Twilio sends data as form-urlencoded
    const fromPhone = req.body.From || req.query.From;
    const bodyText = (req.body.Body || req.query.Body || '').trim();
    
    if (!fromPhone || !bodyText) {
      logger.warn('Missing From or Body in SMS reply', { fromPhone, bodyText });
      res.type('text/xml').send('<?xml version="1.0" encoding="UTF-8"?><Response></Response>');
      return;
    }
    
    logger.info('Received SMS', {
      from: fromPhone,
      body: bodyText,
    });
    
    // Normalize phone number to E.164 format
    const normalizedPhone = normalizePhoneNumber(fromPhone);
    logger.info('Normalized phone number', {
      original: fromPhone,
      normalized: normalizedPhone,
    });
    
    // Clean reply text (remove whitespace, convert to lowercase for comparison)
    const cleanReply = bodyText.trim().toLowerCase();
    logger.info('Processing reply', { cleanReply, original: bodyText });
    
    // Find appointment by phone number
    // Try multiple phone number formats for matching (incl. Pakistani numbers)
    const uniquePhoneVariations = phoneVariations(fromPhone);
    
    logger.info('Phone variations to try', {
      original: fromPhone,
      normalized: normalizedPhone,
      variations: uniquePhoneVariations,
    });
    
    let appointmentDoc = null;
    let appointmentData = null;
    
    // Query with multiple phone number variations
    const appointmentsRef = admin.firestore().collection('Appointments');
    
    // Collect booked appointments stored under any of the phone spellings
    // (previously the search stopped at the first spelling with a match).
    // Cancelled ones are left out so a reply can't reactivate them.
    const candidatesById = new Map();
    for (const phoneVar of uniquePhoneVariations) {
      try {
        const querySnapshot = await appointmentsRef
          .where('phone', '==', phoneVar)
          .where('status', 'in', BOOKED_STATUSES)
          .get();
        logger.info('Query result', { phoneVar, found: querySnapshot.size });
        for (const doc of querySnapshot.docs) {
          candidatesById.set(doc.id, {id: doc.id, data: doc.data(), doc, phoneVar});
        }
      } catch (queryError) {
        logger.warn('Error querying with phone variation', {
          phoneVar,
          error: queryError.message,
          stack: queryError.stack,
        });
      }
    }

    // Pick the appointment the reply is about (see pickAppointmentForReply)
    const picked = pickAppointmentForReply([...candidatesById.values()]);
    if (picked) {
      appointmentDoc = picked.doc;
      appointmentData = appointmentDoc.data();
      logger.info('Found appointment', {
        appointmentId: appointmentDoc.id,
        patientName: appointmentData.name,
        date: appointmentData.date,
        status: appointmentData.status,
        phoneInFirestore: appointmentData.phone,
        phoneMatched: picked.phoneVar,
        candidates: candidatesById.size,
      });
    }
    
    if (!appointmentDoc || !appointmentData) {
      logger.warn('No appointment found for phone number', {
        phone: fromPhone,
        normalized: normalizedPhone,
        triedVariations: uniquePhoneVariations,
      });
      
      await logActivity(
        `SMS reply received from ${fromPhone} but no appointment found. Reply: "${bodyText}"`,
        'sms_reply_no_match'
      );
      
      // Return TwiML response (silent, no reply to user)
      res.type('text/xml').send('<?xml version="1.0" encoding="UTF-8"?><Response></Response>');
      return;
    }
    
    const appointmentRef = appointmentDoc.ref;
    const patientId = appointmentData.patientID;
    const patientName = appointmentData.name || 'Patient';
    const appointmentDate = appointmentData.date;
    
    // Process reply based on content
    let updateData = {};
    let activityMessage = '';
    let replyMessage = '';
    
    const action = parseSmsReply(bodyText);
    updateData = buildReplyUpdate(action, admin.firestore.FieldValue.serverTimestamp());

    if (action === 'confirm') {
      // Reply 1: Confirm appointment
      activityMessage = `Patient ${patientName} (${shortId(patientId)}) confirmed appointment via SMS`;
      replyMessage = 'Thank you! Your appointment is confirmed.';
      logger.info('Processing reply "1" - CONFIRM', { patientId, appointmentDate });
      
    } else if (action === 'cancel') {
      // Reply 2: Cancel appointment
      // (onAppointmentWritten offers the freed slot to later patients)
      activityMessage = `Patient ${patientName} (${shortId(patientId)}) cancelled appointment via SMS`;
      replyMessage = 'Your appointment has been cancelled. We hope to see you soon!';
      logger.info('Processing reply "2" - CANCEL', { patientId, appointmentDate });
      
    } else if (action === 'priority') {
      // Reply 3: Request reschedule (join priority list)
      activityMessage = `Patient ${patientName} (${shortId(patientId)}) requested reschedule via SMS (joined priority list)`;
      replyMessage = 'You are on our priority list! We will offer you earlier slots as they become available. Your current appointment is safe.';
      logger.info('Processing reply "3" - RESCHEDULE/PRIORITY', { patientId, appointmentDate });
      
    } else {
      // Unknown reply
      logger.warn('Unknown reply received', {
        reply: cleanReply,
        original: bodyText,
        patientId,
      });
      
      await logActivity(
        `Unknown SMS reply from ${patientName} (${shortId(patientId)}): "${bodyText}"`,
        'sms_reply_unknown'
      );
      
      // Return TwiML response (silent, no reply to user)
      res.type('text/xml').send('<?xml version="1.0" encoding="UTF-8"?><Response></Response>');
      return;
    }
    
    // Update appointment in Firestore
    try {
      await appointmentRef.update(updateData);
      logger.info('Appointment status updated successfully', {
        appointmentId: appointmentDoc.id,
        updates: updateData,
      });
      
      // Log activity
      await logActivity(activityMessage, 'sms_reply');

      
      // Send confirmation SMS reply (optional - can be disabled if not needed)
      // Note: This requires Twilio to be configured, and may incur additional costs
      // Uncomment if you want to send automatic replies
      /*
      try {
        const twilioCreds = getTwilioConfig();
        if (twilioCreds) {
          const twilio = require('twilio');
          const client = twilio(twilioCreds.finalAccountSid, twilioCreds.finalAuthToken);
          
          await client.messages.create({
            body: replyMessage,
            from: twilioCreds.finalPhoneNumber,
            to: normalizedPhone || fromPhone,
          });
          
          logger.info('Confirmation SMS sent', { to: normalizedPhone || fromPhone });
        }
      } catch (smsError) {
        logger.warn('Could not send confirmation SMS', smsError);
        // Don't fail if confirmation SMS fails
      }
      */
      
      // Return TwiML response (silent, no reply to user)
      // If you want to send a reply, uncomment the <Message> section below
      res.type('text/xml').send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <!-- Uncomment to send automatic reply -->
  <!-- <Message>${replyMessage}</Message> -->
</Response>`);
      
    } catch (updateError) {
      logger.error('Error updating appointment', {
        error: updateError.message,
        appointmentId: appointmentDoc.id,
        updates: updateData,
      });
      
      await logActivity(
        `Error updating appointment from SMS reply: ${updateError.message}`,
        'error'
      );
      
      // Return TwiML response even on error
      res.type('text/xml').send('<?xml version="1.0" encoding="UTF-8"?><Response></Response>');
    }
    
  } catch (error) {
    logger.error('Error in handleSmsReply', error);
    
    // Return TwiML response even on error (to prevent Twilio retries)
    res.type('text/xml').send('<?xml version="1.0" encoding="UTF-8"?><Response></Response>');
  }
});

/**
 * Helper function to send initial reminder SMS
 * Used by both scheduled function and manual reminders
 */
async function sendInitialReminder(appointmentData, appointmentDoc) {
  try {
    const patientName = appointmentData.name || 'Patient';
    const patientPhone = appointmentData.phone;
    const appointmentDate = appointmentData.date; // Format: "dd-MM-yyyy"
    const appointmentTime = appointmentData.time; // Format: "hh:mm a"
    
    if (!patientPhone || !appointmentDate || !appointmentTime) {
      logger.warn('Missing required fields for reminder', {
        appointmentId: appointmentDoc.id,
        hasPhone: !!patientPhone,
        hasDate: !!appointmentDate,
        hasTime: !!appointmentTime,
      });
      return { success: false, message: 'Missing required fields' };
    }

    // Get Twilio configuration
    const twilioCreds = getTwilioConfig();
    if (!twilioCreds) {
      logger.error('Twilio configuration missing for sendInitialReminder');
      return { success: false, message: 'SMS service not configured' };
    }

    const { finalAccountSid, finalAuthToken, finalPhoneNumber } = twilioCreds;
    const twilio = require('twilio');
    const client = twilio(finalAccountSid, finalAuthToken);

    // Format date for message (convert from "dd-MM-yyyy" to readable format)
    // Example: "18-02-2026" -> "18 February 2026"
    let formattedDate = appointmentDate;
    try {
      const dateParts = appointmentDate.split('-');
      if (dateParts.length === 3) {
        const day = dateParts[0];
        const month = parseInt(dateParts[1]);
        const year = dateParts[2];
        const monthNames = [
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'
        ];
        formattedDate = `${day} ${monthNames[month - 1]} ${year}`;
      }
    } catch (e) {
      logger.warn('Could not format date, using original:', appointmentDate);
    }

    // Format the reminder message with patient name
    let messageBody = `Hi ${patientName}! This is a reminder for your medical appointment `;
    messageBody += `on ${formattedDate} at ${appointmentTime}. `;
    messageBody += `Reply: 1 to confirm, 2 to cancel, or 3 to request a different time. `;
    messageBody += `Please reply within 24 hours.`;

    // Send SMS via Twilio
    try {
      const twilioMessage = await client.messages.create({
        body: messageBody,
        from: finalPhoneNumber,
        to: patientPhone,
      });

      logger.info('48-hour reminder sent successfully', {
        sid: twilioMessage.sid,
        to: patientPhone,
        appointmentId: appointmentDoc.id,
        patientName: patientName,
        appointmentDate: appointmentDate,
      });

      // Update appointment status
      await appointmentDoc.ref.update({
        status: 'reminder_sent_awaiting_reply',
        lastReminderSent: admin.firestore.FieldValue.serverTimestamp(),
        initialReminderSent: true, // Flag to prevent duplicate reminders
      });

      // Log activity
      await logActivity(
        `48-hour automatic reminder sent to ${patientName} (${appointmentDate} @ ${appointmentTime})`,
        'automatic_reminder'
      );

      return {
        success: true,
        message: 'Reminder sent successfully',
        sid: twilioMessage.sid,
      };
    } catch (twilioError) {
      logger.error('Twilio error sending 48-hour reminder', {
        error: twilioError.message,
        appointmentId: appointmentDoc.id,
        phone: patientPhone,
      });
      return {
        success: false,
        message: `Failed to send SMS: ${twilioError.message}`,
      };
    }
  } catch (error) {
    logger.error('Error in sendInitialReminder', {
      error: error.message,
      stack: error.stack,
      appointmentId: appointmentDoc?.id,
    });
    return {
      success: false,
      message: `Error: ${error.message}`,
    };
  }
}

/**
 * Scheduled function to send 48-hour automatic reminders
 * Runs every hour to check for appointments exactly 48 hours away
 * 
 * How it works:
 * 1. Queries all active appointments
 * 2. Calculates time difference from appointment date/time
 * 3. If exactly 48 hours (or within 1 hour window: 47-49 hours), sends reminder
 * 4. Only sends once per appointment (checks initialReminderSent flag)
 */
exports.process48HourReminders = onSchedule({
  schedule: 'every 1 hours', // Run every hour
  timeZone: 'UTC',
  memory: '256MiB',
  timeoutSeconds: 540, // 9 minutes
}, async (event) => {
  try {
    logger.info('=== 48-HOUR REMINDER PROCESS STARTED ===');
    
    const now = new Date();
    const appointmentsRef = admin.firestore().collection('Appointments');
    
    // Query all active appointments that haven't received initial reminder
    // Status: active, BOOKED, ACTIVE, or reminder_sent_awaiting_reply (but no initialReminderSent flag)
    const querySnapshot = await appointmentsRef
      .where('status', 'in', [
        'active',
        'BOOKED',
        'ACTIVE',
        'CONFIRMED',
        'reminder_sent_awaiting_reply',
      ])
      .get();

    logger.info(`Found ${querySnapshot.size} active appointments to check`);

    let remindersSent = 0;
    let remindersSkipped = 0;
    let errors = 0;

    for (const doc of querySnapshot.docs) {
      try {
        const appointmentData = doc.data();
        
        // Skip if already sent initial reminder
        if (appointmentData.initialReminderSent === true) {
          remindersSkipped++;
          continue;
        }

        // Skip cancelled or unavailable appointments
        const status = appointmentData.status?.toLowerCase() || '';
        if (status === 'cancelled' || status === 'available' || status === 'AVAILABLE') {
          remindersSkipped++;
          continue;
        }

        const appointmentDate = appointmentData.date; // Format: "dd-MM-yyyy"
        const appointmentTime = appointmentData.time; // Format: "hh:mm a"
        
        if (!appointmentDate || !appointmentTime) {
          logger.warn('Appointment missing date or time', {
            appointmentId: doc.id,
            hasDate: !!appointmentDate,
            hasTime: !!appointmentTime,
          });
          continue;
        }

        // Parse appointment date and time (UK clinic time; handles AM/PM and 24h)
        const appointmentDateTime = parseAppointmentDateTime(appointmentDate, appointmentTime);
        if (!appointmentDateTime) {
          logger.warn('Invalid appointment date/time', {
            appointmentId: doc.id,
            date: appointmentDate,
            time: appointmentTime,
          });
          continue;
        }

        // Calculate time difference in hours
        const timeDiffMs = appointmentDateTime.getTime() - now.getTime();
        const timeDiffHours = timeDiffMs / (1000 * 60 * 60);

        // Check if appointment is exactly 48 hours away (within 1 hour window: 47-49 hours)
        // This accounts for the hourly schedule - we check every hour
        if (timeDiffHours >= 47 && timeDiffHours <= 49) {
          logger.info('Appointment is 48 hours away, sending reminder', {
            appointmentId: doc.id,
            patientName: appointmentData.name,
            appointmentDate: appointmentDate,
            appointmentTime: appointmentTime,
            hoursUntil: timeDiffHours.toFixed(2),
          });

          const result = await sendInitialReminder(appointmentData, doc);
          
          if (result.success) {
            remindersSent++;
            logger.info('✅ Reminder sent successfully', {
              appointmentId: doc.id,
              patientName: appointmentData.name,
            });
          } else {
            errors++;
            logger.error('❌ Failed to send reminder', {
              appointmentId: doc.id,
              error: result.message,
            });
          }
        } else {
          // Appointment is not 48 hours away yet, or already passed
          if (timeDiffHours < 0) {
            // Appointment already passed, mark as skipped
            remindersSkipped++;
          }
          // Otherwise, it's too early (more than 49 hours away) or too late (less than 47 hours)
        }
      } catch (appointmentError) {
        errors++;
        logger.error('Error processing appointment for reminder', {
          appointmentId: doc.id,
          error: appointmentError.message,
          stack: appointmentError.stack,
        });
      }
    }

    logger.info('=== 48-HOUR REMINDER PROCESS COMPLETED ===', {
      totalAppointments: querySnapshot.size,
      remindersSent: remindersSent,
      remindersSkipped: remindersSkipped,
      errors: errors,
    });

    return {
      success: true,
      remindersSent: remindersSent,
      remindersSkipped: remindersSkipped,
      errors: errors,
    };
  } catch (error) {
    logger.error('Fatal error in process48HourReminders', {
      error: error.message,
      stack: error.stack,
    });
    throw error;
  }
});
