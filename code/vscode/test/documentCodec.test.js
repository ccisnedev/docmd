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

// A webview cannot load a package-relative path against its own origin, so the
// editor swaps in a display URI. That swap has to be undone on save: writing a
// `vscode-webview://` URI into content/document.md points the package at a
// location that exists only inside one session.
test('an imported image survives the display rewrite round trip', () => {
  const canonical = '../assets/media/image16.png';
  const displayUri = 'https://file+.vscode-resource.vscode-cdn.net/c%3A/pkg/assets/media/image16.png';

  const html = renderMarkdownDocument(`![](${canonical})`, {
    resolveSrc: (src) => (src === canonical ? displayUri : src),
  });

  assert.match(html, /src="https:\/\/file\+\.vscode-resource[^"]*image16\.png"/);
  assert.match(html, /data-docmd-src="\.\.\/assets\/media\/image16\.png"/);

  const markdown = markdownFromDocumentHtml(html);

  assert.match(markdown, /!\[\]\(\.\.\/assets\/media\/image16\.png\)/);
  assert.doesNotMatch(markdown, /vscode-resource|vscode-webview/);
});

// contenteditable hands back whatever the browser made of the injected HTML.
// Attributes do survive in practice, but the package must not be corrupted if
// one does not.
test('a display URI is restored even when the marker attribute is lost', () => {
  const displayUri = 'https://file+.vscode-resource.vscode-cdn.net/c%3A/pkg/assets/media/image16.png';

  const markdown = markdownFromDocumentHtml(`<p><img src="${displayUri}" alt=""></p>`, {
    restoreSrc: (src) => (src === displayUri ? '../assets/media/image16.png' : src),
  });

  assert.match(markdown, /!\[\]\(\.\.\/assets\/media\/image16\.png\)/);
  assert.doesNotMatch(markdown, /vscode-resource/);
});

test('renderMarkdownDocument leaves external image sources alone', () => {
  const html = renderMarkdownDocument('![](https://example.com/logo.png)', {
    resolveSrc: () => 'SHOULD NOT BE USED',
  });

  assert.match(html, /src="https:\/\/example\.com\/logo\.png"/);
  assert.doesNotMatch(html, /data-docmd-src/);
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