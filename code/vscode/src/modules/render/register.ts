import * as vscode from 'vscode';

import type { ExtensionServices } from '../../core/services';
import { withDocmdCli } from '../../infrastructure/docmd/docmdCommandGuard';
import { presentCommandError } from '../../shared/errors';
import { getPreferredWorkingDirectory } from '../../shared/workspace';

export function registerRenderModule(
  context: vscode.ExtensionContext,
  services: ExtensionServices,
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('docmd.renderFile', async () => {
      const inputPath = await resolveRenderInputPath();
      if (!inputPath) {
        return;
      }

      const formats = ['docx', 'pdf'] as const;
      const selectedFormat = await vscode.window.showQuickPick(formats, {
        placeHolder: 'Choose the output format',
      });
      const format = selectedFormat as 'docx' | 'pdf' | undefined;

      if (!format) {
        return;
      }

      services.logger.show();

      try {
        const result = await withDocmdCli(
          services,
          () => services.cli.renderFile(inputPath, format, {
            cwd: getPreferredWorkingDirectory(),
          }),
        );
        if (!result) {
          return;
        }

        const action = await vscode.window.showInformationMessage(
          `DocMD render completed: ${format.toUpperCase()}`,
          'Open Output',
        );

        if (action === 'Open Output') {
          await vscode.env.openExternal(vscode.Uri.file(result.outputPath));
        }
      } catch (error) {
        await presentCommandError('DocMD render failed', error, services.logger);
      }
    }),
  );
}

async function resolveRenderInputPath(): Promise<string | undefined> {
  const activeFile = vscode.window.activeTextEditor?.document.uri.fsPath;
  if (activeFile) {
    return activeFile;
  }

  const selection = await vscode.window.showOpenDialog({
    canSelectMany: false,
    canSelectFiles: true,
    canSelectFolders: true,
    openLabel: 'Render with DocMD',
    filters: {
      Canonical: ['md', 'markdown'],
    },
  });

  return selection?.[0]?.fsPath;
}