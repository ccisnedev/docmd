const test = require('node:test');
const assert = require('node:assert/strict');

const { splitLogLines } = require('../out/infrastructure/logging/logLines.js');

test('splitLogLines preserves all CRLF-delimited lines', () => {
  assert.deepEqual(
    splitLogLines('line1\r\nline2\r\nline3'),
    ['line1', 'line2', 'line3'],
  );
});

test('splitLogLines preserves blank interior lines', () => {
  assert.deepEqual(
    splitLogLines('line1\n\nline3'),
    ['line1', '', 'line3'],
  );
});