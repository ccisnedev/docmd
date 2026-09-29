import * as vscode from 'vscode';

import type { ExtensionServices } from '../../core/services';
import { ensureDocmdCliAvailable, withDocmdCli } from '../../infrastructure/docmd/docmdCommandGuard';
import { presentCommandError } from '../../shared/errors';
import { getPreferredWorkingDirectory } from '../../shared/workspace';
import { summarizeDoctorResult } from './summarizeDoctorResult';

export function registerDoctorModule(
  context: vscode.ExtensionContext,
  services: ExtensionServices,
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('docmd.doctor', async () => {
      if (!(await ensureDocmdCliAvailable(services))) {
        return;
      }

      services.logger.show();

      try {
        const result = await withDocmdCli(
          services,
          () => services.cli.doctor({
            cwd: getPreferredWorkingDirectory(),
          }),
        );
        if (!result) {
          return;
        }

        const summary = summarizeDoctorResult(result);
        if (summary.level === 'warning') {
          await vscode.window.showWarningMessage(summary.message);
          return;
        }

        await vscode.window.showInformationMessage(summary.message);
      } catch (error) {
        await presentCommandError('DocMD doctor failed', error, services.logger);
      }
    }),
  );
}
