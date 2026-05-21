import * as vscode from 'vscode';

import type { ExtensionServices } from '../../core/services';
import { presentCommandError } from '../../shared/errors';
import { resolveCanonicalDocumentPath } from '../../shared/workspace';
import { DocumentEditorPanel } from './webview/documentEditorPanel';

export function registerEditorModule(
  context: vscode.ExtensionContext,
  services: ExtensionServices,
): void {
  context.subscriptions.push(
    vscode.commands.registerCommand(
      'docmd.openDocumentEditor',
      async (inputPath?: string | vscode.Uri) => {
      try {
        const resolvedInputPath = inputPath instanceof vscode.Uri ? inputPath.fsPath : inputPath;
        const canonicalDocumentPath = await resolveCanonicalDocumentPath(resolvedInputPath);
        if (!canonicalDocumentPath) {
          return;
        }

        await DocumentEditorPanel.createOrShow(context, services, canonicalDocumentPath);
      } catch (error) {
        await presentCommandError('Failed to open DocMD editor', error, services.logger);
      }
      },
    ),
  );
}
