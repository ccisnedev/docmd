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

test('command titles do not duplicate the DocMD category prefix', () => {
  const packageJsonPath = path.resolve(__dirname, '../package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
  const commands = packageJson.contributes?.commands ?? [];

  for (const command of commands) {
    if (!command.category || !command.title) {
      continue;
    }

    assert.equal(
      command.title.startsWith(`${command.category}: `),
      false,
      `Command ${command.command} duplicates its category prefix in the title.`,
    );
  }
});

test('marketplace workflow publishes with runtime dependencies included', () => {
  const workflowPath = path.resolve(__dirname, '../../../.github/workflows/vscode-marketplace.yml');
  const workflow = fs.readFileSync(workflowPath, 'utf-8');

  assert.doesNotMatch(
    workflow,
    /vsce publish --no-dependencies/,
    'Marketplace publishing skips runtime dependencies, which breaks extension activation after install.',
  );
});

test('launch.json provides a managed-cli debug configuration', () => {
  const launchPath = path.resolve(__dirname, '../../../.vscode/launch.json');
  const launch = JSON.parse(fs.readFileSync(launchPath, 'utf-8'));
  const configurations = launch.configurations ?? [];
  const managedConfig = configurations.find(
    (config) => config.name === 'Run Extension (Managed CLI)',
  );

  assert.ok(
    managedConfig,
    'Expected a dedicated debug configuration that uses the managed DocMD CLI path.',
  );
  assert.equal(
    managedConfig.env?.DOCMD_CLI_PATH,
    '${env:LOCALAPPDATA}\\docmd\\bin\\docmd.exe',
    'Managed CLI debug configuration must force the extension to use the managed Windows CLI path.',
  );
});

test('package.json declares explicit activation events for debug and command flows', () => {
  const packageJsonPath = path.resolve(__dirname, '../package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf-8'));
  const activationEvents = packageJson.activationEvents ?? [];

  assert.ok(
    activationEvents.includes('onStartupFinished'),
    'DocMD should activate on startup in the Extension Development Host so its output channel and commands are registered early.',
  );

  for (const commandId of [
    'docmd.doctor',
    'docmd.importFile',
    'docmd.installCli',
    'docmd.openDocumentEditor',
    'docmd.renderFile',
    'docmd.showOutput',
  ]) {
    assert.ok(
      activationEvents.includes(`onCommand:${commandId}`),
      `Missing explicit activation event for ${commandId}.`,
    );
  }
});