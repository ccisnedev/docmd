import { existsSync } from 'node:fs';
import * as path from 'node:path';

import * as vscode from 'vscode';

import type { ExtensionServices } from '../../core/services';
import { ensureDocmdCliAvailable, withDocmdCli } from '../../infrastructure/docmd/docmdCommandGuard';
import type { DocmdImportOptions } from '../../infrastructure/docmd/docmdCli';
import { presentCommandError } from '../../shared/errors';
import { inferDocmdPackagePathForImport } from '../../shared/canonicalPath';

export function registerImportModule(
  context: vscode.ExtensionContext,
  services: ExtensionServices,
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand('docmd.importFile', async () => {
      if (!(await ensureDocmdCliAvailable(services))) {
        return;
      }

      const selection = await vscode.window.showOpenDialog({
        canSelectMany: false,
        canSelectFiles: true,
        canSelectFolders: false,
        openLabel: 'Import into DocMD',
        filters: {
          Documents: ['docx', 'pptx', 'xlsx', 'pdf'],
        },
      });

      if (!selection?.length) {
        return;
      }

      const sourcePath = selection[0].fsPath;
      const destination = await vscode.window.showOpenDialog({
        canSelectMany: false,
        canSelectFiles: false,
        canSelectFolders: true,
        defaultUri: vscode.Uri.file(path.dirname(sourcePath)),
        openLabel: 'Create DocMD package here',
      });

      if (!destination?.length) {
        return;
      }

      const outputDir = destination[0].fsPath;
      const importOptions = await resolveImportOptions(sourcePath, outputDir);
      if (!importOptions) {
        return;
      }

      if (importOptions.openExistingPackagePath) {
        await vscode.commands.executeCommand(
          'docmd.openDocumentEditor',
          importOptions.openExistingPackagePath,
        );
        return;
      }

      services.logger.show();

      try {
        const result = await withDocmdCli(
          services,
          () => services.cli.importFile(sourcePath, importOptions),
        );
        if (!result) {
          return;
        }

        await vscode.commands.executeCommand(
          'docmd.openDocumentEditor',
          result.canonicalDocumentPath,
        );
        const detail = importOptions.suffix
          ? 'DocMD import completed as a new copy.'
          : importOptions.overwrite
            ? 'DocMD import completed and replaced the existing package.'
            : 'DocMD import completed.';
        await vscode.window.showInformationMessage(detail);
      } catch (error) {
        await presentCommandError('DocMD import failed', error, services.logger);
      }
    }),
  );
}

interface ImportResolution extends DocmdImportOptions {
  openExistingPackagePath?: string;
}

async function resolveImportOptions(
  sourcePath: string,
  outputDir: string,
): Promise<ImportResolution | undefined> {
  const packagePath = inferDocmdPackagePathForImport(sourcePath, outputDir);
  if (!existsSync(packagePath)) {
    return { outputDir };
  }

  const action = await vscode.window.showWarningMessage(
    `A DocMD package already exists at the selected destination for ${sourcePath}.`,
    {
      modal: true,
      detail: packagePath,
    },
    'Open Existing',
    'Overwrite',
    'Create Copy',
  );

  if (!action) {
    return undefined;
  }

  if (action === 'Open Existing') {
    return { outputDir, openExistingPackagePath: packagePath };
  }

  if (action === 'Overwrite') {
    return { outputDir, overwrite: true };
  }

  return { outputDir, suffix: true };
}
