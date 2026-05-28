const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const {
  inferDocmdPackagePathForImport,
  toCanonicalDocumentPath,
} = require('../out/shared/canonicalPath.js');

test('toCanonicalDocumentPath resolves an existing DocMD package folder', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'docmd-workspace-package-'));

  try {
    const packageDir = path.join(tempDir, 'sample.docmd');
    const contentDir = path.join(packageDir, 'content');
    const documentPath = path.join(contentDir, 'document.md');

    fs.mkdirSync(contentDir, { recursive: true });
    fs.writeFileSync(documentPath, '# Sample');

    assert.equal(toCanonicalDocumentPath(packageDir), documentPath);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('toCanonicalDocumentPath returns markdown files directly', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'docmd-workspace-md-'));

  try {
    const markdownPath = path.join(tempDir, 'notes.md');
    fs.writeFileSync(markdownPath, '# Notes');

    assert.equal(toCanonicalDocumentPath(markdownPath), markdownPath);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('toCanonicalDocumentPath ignores binary office files', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'docmd-workspace-docx-'));

  try {
    const docxPath = path.join(tempDir, 'sample.docx');
    fs.writeFileSync(docxPath, 'binary');

    assert.equal(toCanonicalDocumentPath(docxPath), undefined);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('inferDocmdPackagePathForImport targets the selected output directory', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'docmd-workspace-import-'));

  try {
    const inputPath = path.join(tempDir, 'incoming', 'sample.docx');
    const outputDir = path.join(tempDir, 'imports');

    assert.equal(
      inferDocmdPackagePathForImport(inputPath, outputDir),
      path.join(outputDir, 'sample.docmd'),
    );
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});