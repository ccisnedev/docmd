import 'package:modular_cli_sdk/modular_cli_sdk.dart';

import 'commands/render_file.dart';

void buildRenderModule(ModuleBuilder m) {
  m.command<RenderInput, RenderOutput>(
    '<input>',
    (req) => RenderCommand(RenderInput.fromCliRequest(req)),
    description: 'Render canonical content to DOCX or PDF',
    params: RenderInput.params,
  );
}
