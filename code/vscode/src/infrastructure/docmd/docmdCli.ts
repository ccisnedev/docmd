import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import * as path from 'node:path';

import * as vscode from 'vscode';

import { DocmdCliNotFoundError } from './docmdErrors';
import { getManagedDocmdBinaryPath } from './docmdInstaller';
import type { OutputChannelLogger } from '../logging/outputChannelLogger';

export interface DocmdRunOptions {
  cwd?: string;
}

export interface DocmdRunResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

interface ResolvedDocmdInvocation {
  command: string;
  args: string[];
  cwd?: string;
  displayCommand: string;
}

export interface DocmdImportResult {
  inputPath: string;
  packagePath: string;
  manifestPath: string;
  canonicalDocumentPath: string;
  originalSourcePath: string;
  status: string;
}

export interface DocmdImportOptions extends DocmdRunOptions {
  overwrite?: boolean;
  suffix?: boolean;
}

export interface DocmdRenderResult {
  inputPath: string;
  sourceMarkdownPath: string;
  outputPath: string;
  format: string;
  status: string;
}

export interface DocmdDoctorResult {
  checks: Record<string, boolean>;
}

export class DocmdCli {
  constructor(
    private readonly logger: OutputChannelLogger,
    private readonly extensionPath?: string,
  ) {}

  async doctor(options: DocmdRunOptions = {}): Promise<DocmdDoctorResult> {
    return this.runJson<DocmdDoctorResult>(['doctor'], options);
  }

  async importFile(
    inputPath: string,
    options: DocmdImportOptions = {},
  ): Promise<DocmdImportResult> {
    const args = ['import', inputPath];
    if (options.overwrite) {
      args.push('--overwrite');
    }
    if (options.suffix) {
      args.push('--suffix');
    }

    return this.runJson<DocmdImportResult>(args, options);
  }

  async renderFile(
    inputPath: string,
    format: 'docx' | 'pdf',
    options: DocmdRunOptions = {},
  ): Promise<DocmdRenderResult> {
    const args = format === 'docx' ? ['render', inputPath] : ['render', inputPath, `--${format}`];
    return this.runJson<DocmdRenderResult>(args, options);
  }

  async run(args: string[], options: DocmdRunOptions = {}): Promise<DocmdRunResult> {
    const invocation = this.resolveInvocation(args, options);
    this.logger.info(`Running: ${invocation.displayCommand}`);

    return new Promise<DocmdRunResult>((resolve, reject) => {
      const child = spawn(invocation.command, invocation.args, {
        cwd: invocation.cwd,
        shell: process.platform === 'win32' && !path.isAbsolute(invocation.command),
      });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (chunk: Buffer | string) => {
        const text = chunk.toString();
        stdout += text;
        this.logger.info(text.trimEnd());
      });

      child.stderr.on('data', (chunk: Buffer | string) => {
        const text = chunk.toString();
        stderr += text;
        this.logger.error(text.trimEnd());
      });

      child.on('error', (error) => {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
          reject(new DocmdCliNotFoundError(invocation.command));
          return;
        }

        reject(new Error(`Failed to start docmd: ${error.message}`));
      });

      child.on('close', (exitCode) => {
        const result: DocmdRunResult = {
          exitCode: exitCode ?? 1,
          stdout,
          stderr,
        };

        if (result.exitCode == 0) {
          resolve(result);
          return;
        }

        reject(
          new Error(
            result.stderr.trim() || result.stdout.trim() || `docmd exited with code ${result.exitCode}`,
          ),
        );
      });
    });
  }

  private resolveInvocation(
    args: string[],
    options: DocmdRunOptions,
  ): ResolvedDocmdInvocation {
    const overridePath = process.env.DOCMD_CLI_PATH?.trim();
    if (overridePath) {
      return {
        command: overridePath,
        args,
        cwd: options.cwd ?? getWorkspaceRoot(),
        displayCommand: `${overridePath} ${args.join(' ')}`.trim(),
      };
    }

    const localBuildPath = this.resolveLocalBuildPath();
    if (localBuildPath) {
      return {
        command: localBuildPath,
        args,
        cwd: options.cwd ?? getWorkspaceRoot(),
        displayCommand: `${localBuildPath} ${args.join(' ')}`.trim(),
      };
    }

    const localCliSource = this.resolveLocalCliSourcePath();
    if (localCliSource) {
      return {
        command: 'dart',
        args: ['run', 'bin/main.dart', ...args],
        cwd: localCliSource,
        displayCommand: `dart run bin/main.dart ${args.join(' ')}`.trim(),
      };
    }

    const managedInstallPath = this.resolveManagedInstallPath();
    if (managedInstallPath) {
      return {
        command: managedInstallPath,
        args,
        cwd: options.cwd ?? getWorkspaceRoot(),
        displayCommand: `${managedInstallPath} ${args.join(' ')}`.trim(),
      };
    }

    return {
      command: 'docmd',
      args,
      cwd: options.cwd ?? getWorkspaceRoot(),
      displayCommand: `docmd ${args.join(' ')}`.trim(),
    };
  }

  private resolveLocalBuildPath(): string | undefined {
    if (!this.extensionPath) {
      return undefined;
    }

    const executableName = process.platform === 'win32' ? 'docmd.exe' : 'docmd';
    const candidate = path.join(this.extensionPath, '..', 'cli', 'build', 'bin', executableName);
    return existsSync(candidate) ? candidate : undefined;
  }

  private resolveLocalCliSourcePath(): string | undefined {
    if (!this.extensionPath) {
      return undefined;
    }

    const candidate = path.join(this.extensionPath, '..', 'cli');
    const pubspec = path.join(candidate, 'pubspec.yaml');
    const entrypoint = path.join(candidate, 'bin', 'main.dart');
    return existsSync(pubspec) && existsSync(entrypoint) ? candidate : undefined;
  }

  private resolveManagedInstallPath(): string | undefined {
    const candidate = getManagedDocmdBinaryPath();
    return candidate && existsSync(candidate) ? candidate : undefined;
  }

  async runJson<T>(args: string[], options: DocmdRunOptions = {}): Promise<T> {
    const result = await this.run([...args, '--json'], options);

    try {
      return JSON.parse(result.stdout) as T;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Failed to parse docmd JSON output: ${message}`);
    }
  }
}

function getWorkspaceRoot(): string | undefined {
  return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
}
