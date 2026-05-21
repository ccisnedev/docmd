const test = require('node:test');
const assert = require('node:assert/strict');

const {
  renderMarkdownDocument,
  markdownFromDocumentHtml,
} = require('../out/modules/editor/documentCodec.js');

test('renderMarkdownDocument creates document HTML with headings and tables', () => {
  const html = renderMarkdownDocument([
    '# Title',
    '',
    'Paragraph text.',
    '',
    '| A | B |',
    '|---|---|',
    '| 1 | 2 |',
  ].join('\n'));

  assert.match(html, /<h1>Title<\/h1>/);
  assert.match(html, /<p>Paragraph text\.<\/p>/);
  assert.match(html, /<table>/);
  assert.match(html, /<td>1<\/td>/);
});

test('markdownFromDocumentHtml converts edited document HTML back to markdown', () => {
  const markdown = markdownFromDocumentHtml([
    '<h1>Title</h1>',
    '<p>Intro paragraph.</p>',
    '<table>',
    '<thead><tr><th>A</th><th>B</th></tr></thead>',
    '<tbody><tr><td>1</td><td>2</td></tr></tbody>',
    '</table>',
  ].join(''));

  assert.match(markdown, /^# Title/m);
  assert.match(markdown, /Intro paragraph\./);
  assert.match(markdown, /\| A \| B \|/);
  assert.match(markdown, /\| 1 \| 2 \|/);
});