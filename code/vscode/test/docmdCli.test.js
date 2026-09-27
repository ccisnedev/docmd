const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const childProcess = require('node:child_process');

const { DocmdCli } = require('../out/infrastructure/docmd/docmdCli.js');

function fakeLogger() {
  return {
    info: () => {},
    error: () => {},
    show: () => {},
  };
}

function fakeChildProcess() {
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  return child;
}

function stubSpawn(t, { stdout = '', stderr = '', exitCode = 0 } = {}) {
  const calls = [];

  t.mock.method(childProcess, 'spawn', (command, args, options) => {
    calls.push({ command, args, options });
    const child = fakeChildProcess();

    process.nextTick(() => {
      if (stdout) {
        child.stdout.emit('data', Buffer.from(stdout));
      }
      if (stderr) {
        child.stderr.emit('data', Buffer.from(stderr));
      }
      child.emit('close', exitCode);
    });

    return child;
  });

  return calls;
}

test('importFile places every option before the operand and --json last of the options', async (t) => {
  const calls = stubSpawn(t, {
    stdout: JSON.stringify({
      inputPath: 'a.md',
      packagePath: 'p',
      manifestPath: 'm',
      canonicalDocumentPath: 'c',
      originalSourcePath: 'a.md',
      status: 'ok',
    }),
  });

  const cli = new DocmdCli(fakeLogger());
  await cli.importFile('a.md', { outputDir: 'out', overwrite: true, cwd: '/work' });

  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].args, ['import', '--output-dir', 'out', '--overwrite', '--json', 'a.md']);
});

test('importFile with the suffix option keeps the operand last', async (t) => {
  const calls = stubSpawn(t, {
    stdout: JSON.stringify({
      inputPath: 'a.md',
      packagePath: 'p',
      manifestPath: 'm',
      canonicalDocumentPath: 'c',
      originalSourcePath: 'a.md',
      status: 'ok',
    }),
  });

  const cli = new DocmdCli(fakeLogger());
  await cli.importFile('a.md', { suffix: true, cwd: '/work' });

  assert.deepEqual(calls[0].args, ['import', '--suffix', '--json', 'a.md']);
});

test('importFile with no options only appends --json before the operand', async (t) => {
  const calls = stubSpawn(t, {
    stdout: JSON.stringify({
      inputPath: 'a.md',
      packagePath: 'p',
      manifestPath: 'm',
      canonicalDocumentPath: 'c',
      originalSourcePath: 'a.md',
      status: 'ok',
    }),
  });

  const cli = new DocmdCli(fakeLogger());
  await cli.importFile('a.md', { cwd: '/work' });

  assert.deepEqual(calls[0].args, ['import', '--json', 'a.md']);
});

test('renderFile for docx places --json before the operand', async (t) => {
  const calls = stubSpawn(t, {
    stdout: JSON.stringify({
      inputPath: 'a.md',
      sourceMarkdownPath: 'a.md',
      outputPath: 'a.docx',
      format: 'docx',
      status: 'ok',
    }),
  });

  const cli = new DocmdCli(fakeLogger());
  await cli.renderFile('a.md', 'docx', { cwd: '/work' });

  assert.deepEqual(calls[0].args, ['render', '--json', 'a.md']);
});

test('renderFile for pdf places --pdf and --json before the operand', async (t) => {
  const calls = stubSpawn(t, {
    stdout: JSON.stringify({
      inputPath: 'a.md',
      sourceMarkdownPath: 'a.md',
      outputPath: 'a.pdf',
      format: 'pdf',
      status: 'ok',
    }),
  });

  const cli = new DocmdCli(fakeLogger());
  await cli.renderFile('a.md', 'pdf', { cwd: '/work' });

  assert.deepEqual(calls[0].args, ['render', '--pdf', '--json', 'a.md']);
});

test('doctor has no operand and only appends --json', async (t) => {
  const calls = stubSpawn(t, {
    stdout: JSON.stringify({ checks: [{ name: 'pandoc', status: 'ok' }] }),
  });

  const cli = new DocmdCli(fakeLogger());
  const result = await cli.doctor({ cwd: '/work' });

  assert.deepEqual(calls[0].args, ['doctor', '--json']);
  assert.deepEqual(result, { checks: [{ name: 'pandoc', status: 'ok' }] });
});

test('doctor returns the checks carried by a doctor-check-failed error envelope instead of throwing', async (t) => {
  stubSpawn(t, {
    stderr: JSON.stringify({
      error: {
        id: 'doctor-check-failed',
        message: '1 check(s) failed: pandoc',
        exitCode: 78,
        checks: [
          { name: 'pandoc', status: 'error', detail: 'not found' },
          { name: 'libreoffice', status: 'ok' },
        ],
      },
    }),
    exitCode: 78,
  });

  const cli = new DocmdCli(fakeLogger());
  const result = await cli.doctor({ cwd: '/work' });

  assert.deepEqual(result, {
    checks: [
      { name: 'pandoc', status: 'error', detail: 'not found' },
      { name: 'libreoffice', status: 'ok' },
    ],
  });
});

test('doctor still throws when the failure is not a doctor-check-failed envelope', async (t) => {
  stubSpawn(t, { stderr: 'docmd: command not found', exitCode: 127 });

  const cli = new DocmdCli(fakeLogger());
  await assert.rejects(() => cli.doctor({ cwd: '/work' }), /command not found/);
});
