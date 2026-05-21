import * as os from 'node:os';
import * as path from 'node:path';

const GITHUB_REPO = 'ccisnedev/docmd';
const RELEASES_URL = `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`;

export function getDocmdAssetName(platform: string): string {
  if (platform === 'win32') {
    return 'docmd-windows-x64.zip';
  }

  if (platform === 'linux') {
    return 'docmd-linux-x64.tar.gz';
  }

  throw new Error(`Unsupported platform: ${platform}`);
}

export function getManagedDocmdInstallDir(platform: string = process.platform): string | undefined {
  if (platform === 'win32') {
    return path.join(
      process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'),
      'docmd',
    );
  }

  if (platform === 'linux') {
    return path.join(os.homedir(), '.docmd');
  }

  return undefined;
}

export function getManagedDocmdBinDir(platform: string = process.platform): string | undefined {
  const installDir = getManagedDocmdInstallDir(platform);
  return installDir ? path.join(installDir, 'bin') : undefined;
}

export function getManagedDocmdBinaryPath(platform: string = process.platform): string | undefined {
  const binDir = getManagedDocmdBinDir(platform);
  if (!binDir) {
    return undefined;
  }

  return path.join(binDir, platform === 'win32' ? 'docmd.exe' : 'docmd');
}

interface CancellationTokenLike {
  onCancellationRequested(listener: () => void): void;
  isCancellationRequested?: boolean;
}

export interface InstallerDeps {
  platform: string;
  fetchJson(url: string): Promise<any>;
  downloadFile(url: string, destPath: string): Promise<void>;
  extractZip(zipPath: string, destDir: string): Promise<void>;
  extractTarGz(tarPath: string, destDir: string): Promise<void>;
  execFile(cmd: string, args: string[]): Promise<string>;
  mkdirp(dir: string): Promise<void>;
  rmrf(dir: string): Promise<void>;
  chmod(filePath: string, mode: string): Promise<void>;
  symlink(target: string, linkPath: string): Promise<void>;
  getEnvPath(): string;
  setEnvPath(newPath: string): void;
  withProgress(
    options: { location: number; title: string; cancellable: boolean },
    task: (progress: { report(value: { message?: string }): void }, token: CancellationTokenLike) => Promise<void>,
  ): Promise<void>;
  tmpdir(): string;
}

function defaultFetchJson(url: string): Promise<any> {
  return new Promise((resolve, reject) => {
    const https = require('https');
    const options = {
      headers: {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'docmd-vscode',
      },
    };

    https.get(url, options, (response: any) => {
      if (response.statusCode !== 200) {
        reject(new Error(`GitHub API request failed: HTTP ${response.statusCode}`));
        return;
      }

      let body = '';
      response.on('data', (chunk: string) => {
        body += chunk;
      });
      response.on('end', () => {
        try {
          resolve(JSON.parse(body));
        } catch {
          reject(new Error('Invalid JSON from GitHub API'));
        }
      });
    }).on('error', (error: Error) => reject(error));
  });
}

function defaultDownloadFile(url: string, destPath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const fs = require('fs');
    const https = require('https');
    const options = {
      headers: {
        'User-Agent': 'docmd-vscode',
      },
    };

    const doRequest = (requestUrl: string) => {
      https.get(requestUrl, options, (response: any) => {
        if (response.statusCode === 301 || response.statusCode === 302) {
          doRequest(response.headers.location);
          return;
        }

        if (response.statusCode !== 200) {
          reject(new Error(`Download failed: HTTP ${response.statusCode}`));
          return;
        }

        const file = fs.createWriteStream(destPath);
        response.pipe(file);
        file.on('finish', () => {
          file.close(resolve);
        });
        file.on('error', (error: Error) => {
          try {
            fs.unlinkSync(destPath);
          } catch {
            // Ignore cleanup failures.
          }
          reject(error);
        });
      }).on('error', (error: Error) => {
        try {
          fs.unlinkSync(destPath);
        } catch {
          // Ignore cleanup failures.
        }
        reject(error);
      });
    };

    doRequest(url);
  });
}

async function defaultExtractZip(zipPath: string, destDir: string): Promise<void> {
  const { execFile } = require('child_process');
  const { promisify } = require('util');
  const run = promisify(execFile);

  await run('powershell', [
    '-NoProfile',
    '-Command',
    `Expand-Archive -Path '${zipPath}' -DestinationPath '${destDir}' -Force`,
  ]);
}

async function defaultExtractTarGz(tarPath: string, destDir: string): Promise<void> {
  const { execFile } = require('child_process');
  const { promisify } = require('util');
  const run = promisify(execFile);
  await run('tar', ['xzf', tarPath, '-C', destDir]);
}

async function defaultExecFile(cmd: string, args: string[]): Promise<string> {
  const { execFile } = require('child_process');
  const { promisify } = require('util');
  const run = promisify(execFile);
  const { stdout } = await run(cmd, args);
  return stdout.toString().trim();
}

export async function installDocmdCli(deps?: Partial<InstallerDeps>): Promise<void> {
  const platform = deps?.platform ?? process.platform;
  const assetName = getDocmdAssetName(platform);
  const installDir = getManagedDocmdInstallDir(platform);
  const binDir = getManagedDocmdBinDir(platform);
  const binaryPath = getManagedDocmdBinaryPath(platform);

  if (!installDir || !binDir || !binaryPath) {
    throw new Error(`Unsupported platform: ${platform}`);
  }

  const fetchJson = deps?.fetchJson ?? defaultFetchJson;
  const downloadFile = deps?.downloadFile ?? defaultDownloadFile;
  const extractZip = deps?.extractZip ?? defaultExtractZip;
  const extractTarGz = deps?.extractTarGz ?? defaultExtractTarGz;
  const execFileFn = deps?.execFile ?? defaultExecFile;
  const tmpdir = deps?.tmpdir ?? (() => os.tmpdir());
  const withProgress = deps?.withProgress ?? (() => {
    const vscode = require('vscode');
    return vscode.window.withProgress.bind(vscode.window);
  })();

  const fs = require('fs').promises;
  const mkdirp = deps?.mkdirp ?? ((dir: string) => fs.mkdir(dir, { recursive: true }));
  const rmrf = deps?.rmrf ?? ((dir: string) => fs.rm(dir, { recursive: true, force: true }));
  const chmod = deps?.chmod ?? ((filePath: string, mode: string) => fs.chmod(filePath, mode));
  const symlink = deps?.symlink ?? ((target: string, linkPath: string) =>
    fs.symlink(target, linkPath).catch(async () => {
      try {
        await fs.unlink(linkPath);
      } catch {
        // Ignore cleanup failures.
      }
      return fs.symlink(target, linkPath);
    }));
  const getEnvPath = deps?.getEnvPath ?? (() => process.env.PATH || '');
  const setEnvPath = deps?.setEnvPath ?? ((newPath: string) => {
    process.env.PATH = newPath;
  });

  await withProgress(
    { location: 15, title: 'Installing DocMD CLI...', cancellable: true },
    async (
      progress: { report(value: { message?: string }): void },
      token: CancellationTokenLike,
    ) => {
      let cancelled = false;
      token.onCancellationRequested(() => {
        cancelled = true;
      });

      progress.report({ message: 'Fetching latest release...' });
      const release = await fetchJson(RELEASES_URL);
      const asset = release.assets?.find((candidate: any) => candidate.name === assetName);
      if (!asset) {
        throw new Error(`No ${assetName} asset found in release ${release.tag_name}`);
      }
      if (cancelled) {
        throw new Error('Installation cancelled');
      }

      progress.report({ message: `Downloading ${release.tag_name}...` });
      const tempFile = path.join(
        tmpdir(),
        `docmd-${release.tag_name}${platform === 'win32' ? '.zip' : '.tar.gz'}`,
      );
      await downloadFile(asset.browser_download_url, tempFile);
      if (cancelled) {
        throw new Error('Installation cancelled');
      }

      progress.report({ message: 'Preparing installation directory...' });
      await rmrf(installDir);
      await mkdirp(installDir);

      progress.report({ message: 'Extracting...' });
      if (platform === 'win32') {
        await extractZip(tempFile, installDir);
      } else {
        await extractTarGz(tempFile, installDir);
      }

      try {
        const fss = require('fs');
        fss.unlinkSync(tempFile);
      } catch {
        // Ignore cleanup failures.
      }

      if (platform === 'linux') {
        progress.report({ message: 'Configuring Linux binary...' });
        await chmod(binaryPath, '755');

        const linkDir = path.join(os.homedir(), '.local', 'bin');
        await mkdirp(linkDir);
        await symlink(binaryPath, path.join(linkDir, 'docmd'));
      } else {
        progress.report({ message: 'Updating PATH...' });
        try {
          await execFileFn('powershell', [
            '-NoProfile',
            '-Command',
            `$p = [Environment]::GetEnvironmentVariable('PATH','User'); if ($p -notlike '*${binDir}*') { [Environment]::SetEnvironmentVariable('PATH', "$p;${binDir}", 'User') }`,
          ]);
        } catch {
          // Users can still use the CLI in the current session via PATH injection.
        }
      }

      const currentPath = getEnvPath();
      if (!currentPath.includes(binDir)) {
        setEnvPath(`${binDir}${path.delimiter}${currentPath}`);
      }

      progress.report({ message: 'Verifying installation...' });
      const version = await execFileFn(binaryPath, ['version']);
      progress.report({ message: `Installed ${version}` });
    },
  );
}