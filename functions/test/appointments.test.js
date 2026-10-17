const test = require('node:test');
const assert = require('node:assert/strict');
const a = require('../lib/appointments');

test('parseAppointmentDateTime uses UK time (GMT in winter, BST in summer)', () => {
  assert.equal(a.parseAppointmentDateTime('12-12-2025', '02:00 PM').toISOString(),
    '2025-12-12T14:00:00.000Z');
  assert.equal(a.parseAppointmentDateTime('15-07-2025', '02:00 PM').toISOString(),
    '2025-07-15T13:00:00.000Z');
  assert.equal(a.parseAppointmentDateTime('15-07-2025', '14:00').toISOString(),
    '2025-07-15T13:00:00.000Z');
});

test('parseAppointmentDateTime handles 12 AM/PM and lowercase', () => {
  assert.equal(a.parseAppointmentDateTime('12-12-2025', '12:30 AM').toISOString(),
    '2025-12-12T00:30:00.000Z');
  assert.equal(a.parseAppointmentDateTime('12-12-2025', '12:30 pm').toISOString(),
    '2025-12-12T12:30:00.000Z');
});

test('parseAppointmentDateTime rejects invalid values', () => {
  for (const [d, t] of [['32-01-2025', '10:00 AM'], ['2025-12-12', '10:00 AM'],
    ['12-12-2025', '25:00'], ['12-12-2025', '13:00 PM'], ['12-12-2025', 'xx'],
    [null, '10:00'], ['12-12-2025', undefined]]) {
    assert.equal(a.parseAppointmentDateTime(d, t), null, `${d} ${t}`);
  }
});

test('status helpers cover every stored spelling', () => {
  for (const s of a.BOOKED_STATUSES) assert.ok(a.isBooked(s), s);
  for (const s of a.CANCELLED_STATUSES) assert.ok(a.isCancelled(s), s);
  assert.ok(!a.isBooked('cancelled'));
  assert.ok(!a.isCancelled('CONFIRMED'));
  assert.ok(a.BOOKED_STATUSES.length <= 30); // Firestore 'in' limit
});

test('isNewCancellation only for booked -> cancelled', () => {
  assert.ok(a.isNewCancellation({status: 'CONFIRMED'}, {status: 'cancelled'}));
  assert.ok(!a.isNewCancellation({status: 'cancelled'}, {status: 'cancelled'}));
  assert.ok(!a.isNewCancellation(null, {status: 'cancelled'}));
  assert.ok(!a.isNewCancellation({status: 'active'}, {status: 'CONFIRMED'}));
});

test('shortId tolerates missing patientID (web/CSV bookings)', () => {
  assert.equal(a.shortId(null), 'no app account');
  assert.equal(a.shortId('abcdefgh'), 'abcdef...');
});

test('selectPatientIdsAfterSlot picks later app patients only', () => {
  const cancelled = {date: '10-12-2025', time: '10:00 AM', patientID: 'p0'};
  const ids = a.selectPatientIdsAfterSlot([
    {id: 'x', data: {...cancelled, status: 'cancelled'}},
    {id: 'a', data: {patientID: 'p1', date: '10-12-2025', time: '02:00 PM', status: 'CONFIRMED'}},
    {id: 'b', data: {patientID: 'p2', date: '09-12-2025', time: '11:00 AM', status: 'active'}},
    {id: 'c', data: {patientID: null, date: '11-12-2025', time: '10:00 AM', status: 'active'}},
    {id: 'd', data: {patientID: 'p0', date: '12-12-2025', time: '10:00 AM', status: 'active'}},
    {id: 'e', data: {patientID: 'p3', date: '11-12-2025', time: '10:00 AM', status: 'cancelled'}},
    {id: 'f', data: {patientID: 'p4', date: 'bad', time: '10:00 AM', status: 'active'}},
  ], 'x', cancelled);
  assert.deepEqual([...ids], ['p1']);
});

test('buildSlotOfferMessages keeps the app payload', () => {
  const [m] = a.buildSlotOfferMessages(['tok'], {date: '10-12-2025', time: '10:00 AM'});
  assert.equal(m.token, 'tok');
  assert.equal(m.data.type, 'slot_available');
  assert.equal(m.data.availableDate, '10-12-2025');
  assert.equal(m.android.notification.channelId, 'slot_opportunities');
  for (const v of Object.values(m.data)) assert.equal(typeof v, 'string');
});

test('parseSmsReply', () => {
  assert.equal(a.parseSmsReply(' 1 '), 'confirm');
  assert.equal(a.parseSmsReply('YES'), 'confirm');
  assert.equal(a.parseSmsReply('2'), 'cancel');
  assert.equal(a.parseSmsReply('Cancel'), 'cancel');
  assert.equal(a.parseSmsReply('3'), 'priority');
  assert.equal(a.parseSmsReply('change'), 'priority');
  assert.equal(a.parseSmsReply('hello'), null);
  assert.equal(a.parseSmsReply(''), null);
});

test('buildReplyUpdate writes the statuses the dashboard expects', () => {
  const ts = 'TS';
  assert.deepEqual(a.buildReplyUpdate('confirm', ts),
    {status: 'CONFIRMED', userResponse: 'Confirmed', lastUpdated: ts});
  assert.deepEqual(a.buildReplyUpdate('cancel', ts),
    {status: 'cancelled', userResponse: 'Cancelled', lastUpdated: ts});
  assert.equal(a.buildReplyUpdate('priority', ts).status, 'Confirmed_Priority');
  assert.equal(a.buildReplyUpdate(null, ts), null);
});

test('phoneVariations covers Pakistani local formats', () => {
  const v = a.phoneVariations('+923477974809');
  assert.ok(v.includes('+923477974809'));
  assert.ok(v.includes('03477974809'));
  assert.ok(v.includes('923477974809'));
  assert.equal(a.normalizePhoneNumber('03477974809'), '+923477974809');
  assert.equal(a.normalizePhoneNumber('00447414141704'), '+447414141704');
});

test('pickAppointmentForReply prefers awaiting reply, then nearest upcoming', () => {
  const now = new Date('2025-12-01T00:00:00Z');
  const c = (id, date, status = 'active') => ({id, data: {date, time: '10:00 AM', status}});

  // Old string sort ('31-01-2026' > '15-12-2025') would have picked j
  assert.equal(a.pickAppointmentForReply([c('j', '31-01-2026'), c('d', '15-12-2025')], now).id, 'd');
  assert.equal(a.pickAppointmentForReply(
    [c('d', '15-12-2025'), c('r', '20-12-2025', 'reminder_sent_awaiting_reply')], now).id, 'r');
  assert.equal(a.pickAppointmentForReply([c('p1', '01-10-2025'), c('p2', '01-11-2025')], now).id, 'p2');
  assert.equal(a.pickAppointmentForReply([], now), null);
});

test('times with seconds are accepted (e.g. Excel CSV "14:30:00")', () => {
  assert.equal(a.parseAppointmentDateTime('12-12-2025', '14:30:00').toISOString(),
    '2025-12-12T14:30:00.000Z');
  assert.equal(a.parseAppointmentDateTime('12-12-2025', '02:30:00 PM').toISOString(),
    '2025-12-12T14:30:00.000Z');
  assert.equal(a.parseAppointmentDateTime('12-12-2025', '14:30:99'), null);
});

test('pickAppointmentForReply never picks a cancelled appointment', () => {
  const now = new Date('2025-12-01T00:00:00Z');
  const c = (id, date, status) => ({id, data: {date, time: '10:00 AM', status}});
  assert.equal(a.pickAppointmentForReply(
    [c('x', '05-12-2025', 'CANCELLED'), c('b', '20-12-2025', 'active')], now).id, 'b');
  assert.equal(a.pickAppointmentForReply([c('x', '05-12-2025', 'cancelled')], now), null);
});

test('selectPatientIdsAfterSlot skips CSV-import placeholder ids', () => {
  const ids = a.selectPatientIdsAfterSlot([
    {id: 'a', data: {patientID: 'csv-import-123-1', date: '11-12-2025', time: '10:00 AM', status: 'active'}},
  ], 'x', {date: '10-12-2025', time: '10:00 AM', patientID: 'p0'});
  assert.equal(ids.size, 0);
});
