import * as vscode from 'vscode';

import type { OutputChannelLogger } from '../infrastructure/logging/outputChannelLogger';

export async function presentCommandError(
  title: string,
  error: unknown,
  logger: OutputChannelLogger,
): Promise<void> {
  const message = error instanceof Error ? error.message : String(error);
  logger.error(message);
  logger.show();
  await vscode.window.showErrorMessage(`${title}: ${message}`);
}
