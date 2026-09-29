import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/render_file.dart';

void buildRenderModule(ModuleBuilder m) {
  m.query<RenderInput, RenderOutput>(
    '<input>',
    (req) => RenderCommand(RenderInput.fromCliRequest(req)),
    // globals: true so this route accepts the SDK's --json (the VS Code
    // extension always spawns `docmd render <path> ... --json`).
    globals: true,
    contract: RenderInput.contract,
    description: 'Render canonical content to DOCX, PPTX, or PDF',
  );
}
