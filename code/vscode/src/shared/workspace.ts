import * as path from 'node:path';

import * as vscode from 'vscode';

import { toCanonicalDocumentPath } from './canonicalPath';

export function getPreferredWorkingDirectory(): string | undefined {
  const editorPath = vscode.window.activeTextEditor?.document.uri.fsPath;
  if (editorPath) {
    return path.dirname(editorPath);
  }

  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}

export async function resolveCanonicalDocumentPath(
  inputPath?: string,
): Promise<string | undefined> {
  if (inputPath) {
    return toCanonicalDocumentPath(inputPath);
  }

  const activePath = vscode.window.activeTextEditor?.document.uri.fsPath;
  if (activePath) {
    const activeCanonicalPath = toCanonicalDocumentPath(activePath);
    if (activeCanonicalPath) {
      return activeCanonicalPath;
    }
  }

  const selection = await vscode.window.showOpenDialog({
    canSelectMany: false,
    canSelectFiles: true,
    canSelectFolders: true,
    openLabel: 'Open DocMD Document',
    filters: {
      Markdown: ['md', 'markdown'],
    },
  });

  return toCanonicalDocumentPath(selection?.[0]?.fsPath);
}

export function resolveRenderInputPath(canonicalDocumentPath: string): string {
  const contentDir = path.dirname(canonicalDocumentPath);
  const packageRoot = path.dirname(contentDir);

  if (path.basename(contentDir) === 'content') {
    return packageRoot;
  }

  return canonicalDocumentPath;
}
