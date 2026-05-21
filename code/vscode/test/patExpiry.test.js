const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('PAT expiration tracking is present and still valid', () => {
  const patExpiresPath = path.resolve(__dirname, '../.pat-expires');

  if (!fs.existsSync(patExpiresPath)) {
    assert.fail('Missing or invalid .pat-expires file');
  }

  const raw = fs.readFileSync(patExpiresPath, 'utf-8').trim();
  const expirationDate = new Date(`${raw}T00:00:00`);

  if (Number.isNaN(expirationDate.getTime())) {
    assert.fail('Missing or invalid .pat-expires file');
  }

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const diffMs = expirationDate.getTime() - today.getTime();
  const daysRemaining = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

  if (daysRemaining <= 0) {
    assert.fail(`VSCE PAT has expired on ${raw}. Rotate immediately.`);
  }

  if (daysRemaining <= 7) {
    assert.fail(`VSCE PAT expires in ${daysRemaining} days (${raw}). Rotate now.`);
  }

  if (daysRemaining <= 30) {
    console.warn(`VSCE PAT expires in ${daysRemaining} days (${raw}). Plan rotation.`);
  }
});