import * as vscode from 'vscode';

import type { ExtensionServices } from '../../core/services';
import { ensureDocmdCliAvailable, withDocmdCli } from '../../infrastructure/docmd/docmdCommandGuard';
import { presentCommandError } from '../../shared/errors';
import { getPreferredWorkingDirectory } from '../../shared/workspace';

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

        const missing = Object.entries(result.checks)
          .filter(([, passed]) => !passed)
          .map(([name]) => name);

        if (missing.length == 0) {
          await vscode.window.showInformationMessage('DocMD doctor completed: all checks passed.');
          return;
        }

        await vscode.window.showWarningMessage(
          `DocMD doctor completed with missing tools: ${missing.join(', ')}`,
        );
      } catch (error) {
        await presentCommandError('DocMD doctor failed', error, services.logger);
      }
    }),
  );
}
