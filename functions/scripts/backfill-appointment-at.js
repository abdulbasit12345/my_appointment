/**
 * One-off: sets `appointmentAt` on existing Appointments documents.
 * New and edited appointments get it from the onAppointmentWritten trigger;
 * this fills in documents written before that function was deployed.
 *
 * Run from the functions/ folder with credentials for the project, e.g.:
 *   gcloud auth application-default login
 *   node scripts/backfill-appointment-at.js            # dry run
 *   node scripts/backfill-appointment-at.js --write     # apply
 */
const admin = require('firebase-admin');
const {desiredAppointmentAt} = require('../lib/appointments');

admin.initializeApp({projectId: 'myappointment-6843e'});

async function main() {
  const write = process.argv.includes('--write');
  const db = admin.firestore();
  const snapshot = await db.collection('Appointments').get();

  let toSet = 0;
  let invalid = 0;
  let batch = db.batch();
  let batchSize = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const desired = desiredAppointmentAt(data);
    if (!desired) {
      invalid++;
      console.log(`Invalid date/time: ${doc.id} "${data.date}" "${data.time}"`);
      // Same as the trigger: no appointmentAt for an invalid date/time
      if (data.appointmentAt !== undefined && write) {
        batch.update(doc.ref, {appointmentAt: admin.firestore.FieldValue.delete()});
        if (++batchSize === 400) {
          await batch.commit();
          batch = db.batch();
          batchSize = 0;
        }
      }
      continue;
    }
    const current = data.appointmentAt?.toDate?.().getTime() ?? null;
    if (current === desired.getTime()) continue;

    toSet++;
    if (write) {
      batch.update(doc.ref, {appointmentAt: admin.firestore.Timestamp.fromDate(desired)});
      if (++batchSize === 400) {
        await batch.commit();
        batch = db.batch();
        batchSize = 0;
      }
    }
  }
  if (write && batchSize > 0) await batch.commit();

  console.log(`${snapshot.size} appointments, ${toSet} ${write ? 'updated' : 'would be updated'}, ${invalid} with invalid date/time`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
