import * as vscode from 'vscode';

import { splitLogLines } from './logLines';

export class OutputChannelLogger {
  readonly channel: vscode.OutputChannel;

  constructor(name: string) {
    this.channel = vscode.window.createOutputChannel(name);
  }

  info(message: string): void {
    this.appendMultiline('[info]', message);
  }

  error(message: string): void {
    this.appendMultiline('[error]', message);
  }

  show(): void {
    this.channel.show(true);
  }

  private appendMultiline(prefix: string, message: string): void {
    for (const line of splitLogLines(message)) {
      this.channel.appendLine(`${prefix} ${line}`);
    }
  }
}
