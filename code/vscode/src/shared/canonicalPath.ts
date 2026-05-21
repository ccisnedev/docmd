import { existsSync, statSync } from 'node:fs';
import * as path from 'node:path';

export function toCanonicalDocumentPath(inputPath?: string): string | undefined {
  if (!inputPath || !existsSync(inputPath)) {
    return undefined;
  }

  const stats = statSync(inputPath);
  if (stats.isDirectory()) {
    const candidate = path.join(inputPath, 'content', 'document.md');
    return existsSync(candidate) ? candidate : undefined;
  }

  if (path.basename(inputPath) === 'document.md') {
    return inputPath;
  }

  const extension = path.extname(inputPath).toLowerCase();
  if (extension === '.md' || extension === '.markdown') {
    return inputPath;
  }

  return undefined;
}

export function inferDocmdPackagePathForImport(inputPath: string): string {
  const absoluteInputPath = path.resolve(inputPath);
  return path.join(
    path.dirname(absoluteInputPath),
    `${path.parse(absoluteInputPath).name}.docmd`,
  );
}