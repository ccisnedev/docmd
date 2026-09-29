import type { DocmdDoctorCheck, DocmdDoctorResult } from '../../infrastructure/docmd/docmdCli';

export interface DoctorSummary {
  level: 'info' | 'warning';
  message: string;
}

/**
 * Turns a {@link DocmdDoctorResult} into a presentation decision, kept free
 * of any `vscode` dependency so it can be unit tested directly.
 *
 * An `error` status takes priority over a `warning` status: any failing
 * check is surfaced as a warning naming the failures, regardless of whether
 * other checks only warned.
 */
export function summarizeDoctorResult(result: DocmdDoctorResult): DoctorSummary {
  const checks = normalizeDoctorChecks(result.checks);
  const failed = checks.filter((check) => check.status === 'error');
  if (failed.length > 0) {
    return {
      level: 'warning',
      message: `DocMD doctor completed with failing checks: ${failed.map((check) => check.name).join(', ')}.`,
    };
  }

  const warnings = checks.filter((check) => check.status === 'warning');
  if (warnings.length > 0) {
    return {
      level: 'warning',
      message: `DocMD doctor completed with warnings: ${warnings.map((check) => check.name).join(', ')}.`,
    };
  }

  return {
    level: 'info',
    message: 'DocMD doctor completed: all checks passed.',
  };
}

/**
 * Reads both `checks` shapes: the current array of per-check statuses, and
 * the legacy name-to-boolean map a CLI installed before the DoctorPlugin
 * migration still prints, where a missing tool is a failing check.
 */
export function normalizeDoctorChecks(
  checks: DocmdDoctorResult['checks'],
): DocmdDoctorCheck[] {
  if (Array.isArray(checks)) {
    return checks;
  }

  return Object.entries(checks).map(([name, found]) => ({
    name,
    status: found ? 'ok' : 'error',
  }));
}
