import * as path from 'node:path';

import * as vscode from 'vscode';

import { DocmdCli } from '../infrastructure/docmd/docmdCli';
import {
  getManagedDocmdBinDir,
  installDocmdCli,
} from '../infrastructure/docmd/docmdInstaller';
import { OutputChannelLogger } from '../infrastructure/logging/outputChannelLogger';
import { registerDoctorModule } from '../modules/doctor/register';
import { registerEditorModule } from '../modules/editor/register';
import { registerImportModule } from '../modules/import/register';
import { registerRenderModule } from '../modules/render/register';
import { presentCommandError } from '../shared/errors';
import type { ExtensionServices } from './services';

export function activate(context: vscode.ExtensionContext): void {
  const logger = new OutputChannelLogger('DocMD');
  const cli = new DocmdCli(logger, context.extensionPath);

  const managedBinDir = getManagedDocmdBinDir();
  if (managedBinDir) {
    const envCollection = context.environmentVariableCollection;
    envCollection.prepend('PATH', `${managedBinDir}${path.delimiter}`);
    envCollection.description = 'Adds DocMD CLI to terminal PATH';
  }

  const installCli = async (): Promise<void> => {
    logger.show();
    logger.info('Installing DocMD CLI from GitHub Releases');
    await installDocmdCli();
    logger.info('DocMD CLI installed successfully');
    await vscode.window.showInformationMessage('DocMD CLI installed successfully.');
  };

  const services: ExtensionServices = { cli, logger, installCli };

  logger.info('Activating DocMD extension');

  context.subscriptions.push(logger.channel);
  context.subscriptions.push(
    vscode.commands.registerCommand('docmd.installCli', async () => {
      try {
        await installCli();
      } catch (error) {
        await presentCommandError('DocMD CLI installation failed', error, logger);
      }
    }),
    vscode.commands.registerCommand('docmd.showOutput', () => {
      logger.show();
    }),
  );

  registerDoctorModule(context, services);
  registerEditorModule(context, services);
  registerImportModule(context, services);
  registerRenderModule(context, services);
}

export function deactivate(): void {}
