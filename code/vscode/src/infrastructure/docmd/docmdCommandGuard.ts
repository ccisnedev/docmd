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
    if (!(error instanceof DocmdCliNotFoundError)) {
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