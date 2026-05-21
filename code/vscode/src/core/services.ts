import type { DocmdCli } from '../infrastructure/docmd/docmdCli';
import type { OutputChannelLogger } from '../infrastructure/logging/outputChannelLogger';

export interface ExtensionServices {
  cli: DocmdCli;
  logger: OutputChannelLogger;
  installCli(): Promise<void>;
}
