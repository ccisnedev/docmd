const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('VSIX packaging keeps runtime dependencies available at activation time', () => {
  const packageJsonPath = path.resolve(__dirname, '../package.json');
  const vscodeIgnorePath = path.resolve(__dirname, '../.vscodeignore');

  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
  const runtimeDependencies = Object.keys(packageJson.dependencies ?? {});
  const vscodeIgnore = fs
    .readFileSync(vscodeIgnorePath, 'utf-8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'));

  assert.ok(
    runtimeDependencies.length > 0,
    'Expected the extension to declare at least one runtime dependency for this packaging guard.',
  );

  assert.equal(
    vscodeIgnore.includes('node_modules/**'),
    false,
    'The VSIX excludes node_modules even though the extension has runtime dependencies. This breaks activation in the published package.',
  );
});