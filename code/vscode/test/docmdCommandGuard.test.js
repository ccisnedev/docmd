const test = require('node:test');
const assert = require('node:assert/strict');

const { withDocmdCli } = require('../out/infrastructure/docmd/docmdCommandGuard.js');
const { DocmdCliNotFoundError } = require('../out/infrastructure/docmd/docmdErrors.js');

test('withDocmdCli installs and retries when the CLI is missing', async () => {
  let installCalls = 0;
  let attempts = 0;
  let installed = false;

  const result = await withDocmdCli(
    {
      installCli: async () => {
        installCalls += 1;
        installed = true;
      },
    },
    async () => {
      attempts += 1;
      if (!installed) {
        throw new DocmdCliNotFoundError('docmd');
      }

      return { status: 'ok' };
    },
    {
      showMessage: async () => 'Install',
    },
  );

  assert.deepEqual(result, { status: 'ok' });
  assert.equal(installCalls, 1);
  assert.equal(attempts, 2);
});

test('withDocmdCli returns without installing when the user declines', async () => {
  let installCalls = 0;

  const result = await withDocmdCli(
    {
      installCli: async () => {
        installCalls += 1;
      },
    },
    async () => {
      throw new DocmdCliNotFoundError('docmd');
    },
    {
      showMessage: async () => undefined,
    },
  );

  assert.equal(result, undefined);
  assert.equal(installCalls, 0);
});