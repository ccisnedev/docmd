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

// A CLI installed before the modular_cli_sdk DoctorPlugin migration still
// answers `doctor --json` with `checks` as a name-to-boolean map. The
// extension must keep reading it the way it did before.
test('summarizeDoctorResult accepts the legacy checks map when every tool is present', () => {
  const summary = summarizeDoctorResult({
    checks: { pandoc: true, libreoffice: true },
  });

  assert.deepEqual(summary, {
    level: 'info',
    message: 'DocMD doctor completed: all checks passed.',
  });
});

test('summarizeDoctorResult names missing tools from the legacy checks map', () => {
  const summary = summarizeDoctorResult({
    checks: { pandoc: true, libreoffice: false },
  });

  assert.deepEqual(summary, {
    level: 'warning',
    message: 'DocMD doctor completed with failing checks: libreoffice.',
  });
});
