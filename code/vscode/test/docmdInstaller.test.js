const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const {
  getDocmdAssetName,
  getManagedDocmdBinaryPath,
  installDocmdCli,
} = require('../out/infrastructure/docmd/docmdInstaller.js');

test('getDocmdAssetName maps supported platforms', () => {
  assert.equal(getDocmdAssetName('win32'), 'docmd-windows-x64.zip');
  assert.equal(getDocmdAssetName('linux'), 'docmd-linux-x64.tar.gz');
  assert.throws(() => getDocmdAssetName('darwin'), /Unsupported platform: darwin/);
});

test('getManagedDocmdBinaryPath returns the managed binary layout', () => {
  assert.match(
    getManagedDocmdBinaryPath('win32'),
    new RegExp(`${path.join('docmd', 'bin', 'docmd.exe').replace(/\\/g, '\\\\')}$`),
  );
  assert.match(
    getManagedDocmdBinaryPath('linux'),
    new RegExp(`${path.join('.docmd', 'bin', 'docmd').replace(/\\/g, '\\\\')}$`),
  );
  assert.equal(getManagedDocmdBinaryPath('darwin'), undefined);
});

test('installDocmdCli installs the Windows release asset and prepends PATH', async () => {
  const calls = [];
  const progressMessages = [];
  let envPath = 'C:\\Windows\\System32';

  await installDocmdCli({
    platform: 'win32',
    fetchJson: async () => ({
      tag_name: 'v0.0.1',
      assets: [
        {
          name: 'docmd-windows-x64.zip',
          browser_download_url: 'https://example.com/docmd-windows-x64.zip',
        },
      ],
    }),
    downloadFile: async (url, destPath) => {
      calls.push(['downloadFile', url, destPath]);
    },
    extractZip: async (zipPath, destDir) => {
      calls.push(['extractZip', zipPath, destDir]);
    },
    extractTarGz: async () => {
      throw new Error('Unexpected tar extraction on Windows');
    },
    execFile: async (cmd, args) => {
      calls.push(['execFile', cmd, args]);
      return cmd.endsWith('docmd.exe') ? '0.0.1' : '';
    },
    mkdirp: async (dir) => {
      calls.push(['mkdirp', dir]);
    },
    rmrf: async (dir) => {
      calls.push(['rmrf', dir]);
    },
    chmod: async () => {
      throw new Error('Unexpected chmod on Windows');
    },
    symlink: async () => {
      throw new Error('Unexpected symlink on Windows');
    },
    getEnvPath: () => envPath,
    setEnvPath: (value) => {
      envPath = value;
    },
    withProgress: async (_options, task) => {
      await task(
        {
          report: ({ message }) => {
            if (message) {
              progressMessages.push(message);
            }
          },
        },
        {
          onCancellationRequested() {},
        },
      );
    },
    tmpdir: () => 'C:\\Temp',
  });

  assert.ok(calls.some(([name]) => name === 'downloadFile'));
  assert.ok(calls.some(([name]) => name === 'extractZip'));
  assert.ok(calls.some(([name, cmd]) => name === 'execFile' && cmd === 'powershell'));
  assert.ok(calls.some(([name, cmd]) => name === 'execFile' && String(cmd).endsWith('docmd.exe')));
  assert.match(envPath, /docmd/i);
  assert.ok(progressMessages.includes('Verifying installation...'));
});