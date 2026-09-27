const test = require('node:test');
const assert = require('node:assert/strict');

const { summarizeDoctorResult } = require('../out/modules/doctor/summarizeDoctorResult.js');

test('summarizeDoctorResult reports success when every check is ok', () => {
  const summary = summarizeDoctorResult({
    checks: [
      { name: 'pandoc', status: 'ok' },
      { name: 'libreoffice', status: 'ok' },
    ],
  });

  assert.deepEqual(summary, {
    level: 'info',
    message: 'DocMD doctor completed: all checks passed.',
  });
});

test('summarizeDoctorResult reports a warning when a check only warns', () => {
  const summary = summarizeDoctorResult({
    checks: [
      { name: 'pandoc', status: 'ok' },
      { name: 'libreoffice', status: 'warning', detail: 'old version' },
    ],
  });

  assert.deepEqual(summary, {
    level: 'warning',
    message: 'DocMD doctor completed with warnings: libreoffice.',
  });
});

test('summarizeDoctorResult reports a warning naming every failing check', () => {
  const summary = summarizeDoctorResult({
    checks: [
      { name: 'pandoc', status: 'error', detail: 'not found' },
      { name: 'libreoffice', status: 'error', detail: 'not found' },
    ],
  });

  assert.deepEqual(summary, {
    level: 'warning',
    message: 'DocMD doctor completed with failing checks: pandoc, libreoffice.',
  });
});

test('summarizeDoctorResult prioritizes failing checks over warnings', () => {
  const summary = summarizeDoctorResult({
    checks: [
      { name: 'pandoc', status: 'error', detail: 'not found' },
      { name: 'libreoffice', status: 'warning', detail: 'old version' },
    ],
  });

  assert.deepEqual(summary, {
    level: 'warning',
    message: 'DocMD doctor completed with failing checks: pandoc.',
  });
});
