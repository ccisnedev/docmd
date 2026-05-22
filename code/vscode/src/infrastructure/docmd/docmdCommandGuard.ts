import type { ExtensionServices } from '../../core/services';
import { DocmdCliNotFoundError } from './docmdErrors';

export interface DocmdGuardDeps {
  showMessage: (message: string, ...items: string[]) => Thenable<string | undefined>;
}

export async function withDocmdCli<T>(
  services: ExtensionServices,
  fn: () => Promise<T>,
  deps?: Partial<DocmdGuardDeps>,
): Promise<T | undefined> {
  try {
    return await fn();
  } catch (error) {
    if (!isMissingCliError(error)) {
      throw error;
    }

    const showMessage = deps?.showMessage ?? (() => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const vscode = require('vscode');
      return vscode.window.showInformationMessage.bind(vscode.window);
    })();

    const action = await showMessage(
      'DocMD CLI not found. Install the latest release now?',
      'Install',
    );

    if (action !== 'Install') {
      return undefined;
    }

    await services.installCli();
    return await fn();
  }
}

export async function ensureDocmdCliAvailable(
  services: ExtensionServices,
  deps?: Partial<DocmdGuardDeps>,
): Promise<boolean> {
  const result = await withDocmdCli(
    services,
    () => services.cli.run(['version']),
    deps,
  );

  return result !== undefined;
}

function isMissingCliError(error: unknown): boolean {
  if (error instanceof DocmdCliNotFoundError) {
    return true;
  }

  if (!(error instanceof Error)) {
    return false;
  }

  return [
    /'(docmd|dart)' is not recognized as an internal or external command/i,
    /the term ['"]?(docmd|dart)['"]? is not recognized/i,
    /(?:^|\b)(docmd|dart): not found(?:\b|$)/i,
    /command not found: (docmd|dart)/i,
  ].some((pattern) => pattern.test(error.message));
}