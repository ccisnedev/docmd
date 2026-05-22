import * as path from 'node:path';

import * as vscode from 'vscode';

import type { ExtensionServices } from '../../../core/services';
import { ensureDocmdCliAvailable, withDocmdCli } from '../../../infrastructure/docmd/docmdCommandGuard';
import { presentCommandError } from '../../../shared/errors';
import { resolveRenderInputPath } from '../../../shared/workspace';
import { markdownFromDocumentHtml, renderMarkdownDocument } from '../documentCodec';

type EditorMessage =
  | { type: 'ready' }
  | { type: 'save'; documentHtml: string }
  | { type: 'openRaw' }
  | { type: 'export'; format: 'docx' | 'pdf'; documentHtml: string };

export class DocumentEditorPanel {
  private static readonly panels = new Map<string, DocumentEditorPanel>();

  static async createOrShow(
    context: vscode.ExtensionContext,
    services: ExtensionServices,
    canonicalDocumentPath: string,
  ): Promise<void> {
    const existing = this.panels.get(canonicalDocumentPath);
    if (existing) {
      existing.panel.reveal(vscode.ViewColumn.One);
      await existing.refresh();
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      'docmdDocumentEditor',
      `DocMD: ${path.basename(canonicalDocumentPath)}`,
      vscode.ViewColumn.One,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
      },
    );

    const editor = new DocumentEditorPanel(panel, context, services, canonicalDocumentPath);
    this.panels.set(canonicalDocumentPath, editor);

    panel.onDidDispose(() => {
      this.panels.delete(canonicalDocumentPath);
    });

    await editor.refresh();
  }

  private constructor(
    readonly panel: vscode.WebviewPanel,
    private readonly context: vscode.ExtensionContext,
    private readonly services: ExtensionServices,
    private readonly canonicalDocumentPath: string,
  ) {
    this.panel.webview.onDidReceiveMessage((message: EditorMessage) => {
      void this.handleMessage(message);
    });
  }

  async refresh(): Promise<void> {
    const markdown = await this.readMarkdown();
    this.panel.webview.html = this.getHtml(renderMarkdownDocument(markdown));
  }

  private async handleMessage(message: EditorMessage): Promise<void> {
    switch (message.type) {
      case 'ready':
        return;
      case 'save':
        await this.saveDocumentHtml(message.documentHtml);
        await vscode.window.showInformationMessage('DocMD package saved.');
        return;
      case 'openRaw':
        await vscode.window.showTextDocument(vscode.Uri.file(this.canonicalDocumentPath));
        return;
      case 'export':
        if (!(await ensureDocmdCliAvailable(this.services))) {
          return;
        }

        await this.saveDocumentHtml(message.documentHtml);
        await this.exportDocument(message.format);
        return;
      default:
        return;
    }
  }

  private async exportDocument(format: 'docx' | 'pdf'): Promise<void> {
    try {
      const renderInput = resolveRenderInputPath(this.canonicalDocumentPath);
      const result = await withDocmdCli(
        this.services,
        () => this.services.cli.renderFile(renderInput, format, {
          cwd: path.dirname(this.canonicalDocumentPath),
        }),
      );
      if (!result) {
        return;
      }

      const action = await vscode.window.showInformationMessage(
        `DocMD export completed: ${format.toUpperCase()}`,
        'Open Output',
      );

      if (action === 'Open Output') {
        await vscode.env.openExternal(vscode.Uri.file(result.outputPath));
      }
    } catch (error) {
      await presentCommandError('DocMD export failed', error, this.services.logger);
    }
  }

  private async readMarkdown(): Promise<string> {
    const bytes = await vscode.workspace.fs.readFile(vscode.Uri.file(this.canonicalDocumentPath));
    return Buffer.from(bytes).toString('utf8');
  }

  private async saveMarkdown(markdown: string): Promise<void> {
    await vscode.workspace.fs.writeFile(
      vscode.Uri.file(this.canonicalDocumentPath),
      Buffer.from(markdown, 'utf8'),
    );
  }

  private async saveDocumentHtml(documentHtml: string): Promise<void> {
    await this.saveMarkdown(markdownFromDocumentHtml(documentHtml));
  }

  private getHtml(documentHtml: string): string {
    const nonce = createNonce();
    const documentHtmlJson = JSON.stringify(documentHtml);

    return String.raw`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>DocMD Editor</title>
  <style>
    :root {
      --app-bg: var(--vscode-editor-background);
      --chrome-bg: var(--vscode-editorWidget-background, var(--vscode-sideBar-background, var(--vscode-editor-background)));
      --chrome-border: var(--vscode-panel-border, var(--vscode-widget-border, rgba(127, 127, 127, 0.35)));
      --chrome-text: var(--vscode-foreground);
      --muted: var(--vscode-descriptionForeground, var(--vscode-foreground));
      --button-bg: var(--vscode-button-secondaryBackground, transparent);
      --button-fg: var(--vscode-button-secondaryForeground, var(--vscode-foreground));
      --button-hover: var(--vscode-button-secondaryHoverBackground, var(--vscode-toolbar-hoverBackground, rgba(127, 127, 127, 0.16)));
      --primary-bg: var(--vscode-button-background);
      --primary-fg: var(--vscode-button-foreground);
      --primary-hover: var(--vscode-button-hoverBackground);
      --focus: var(--vscode-focusBorder, #007fd4);
      --page-bg: #ffffff;
      --page-text: #111827;
      --page-muted: #4b5563;
      --page-border: rgba(15, 23, 42, 0.08);
      --page-shadow: 0 24px 60px rgba(0, 0, 0, 0.18);
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      background: var(--app-bg);
      color: var(--chrome-text);
      font: 13px/1.5 var(--vscode-font-family, "Segoe UI", sans-serif);
    }

    .toolbar {
      position: sticky;
      top: 0;
      z-index: 10;
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
      padding: 14px 18px;
      background: var(--chrome-bg);
      border-bottom: 1px solid var(--chrome-border);
    }

    .toolbar-title {
      font-weight: 700;
      letter-spacing: 0.02em;
      margin-right: 14px;
    }

    .toolbar-meta {
      color: var(--muted);
      margin-right: auto;
    }

    .toolbar button {
      border: 1px solid var(--chrome-border);
      background: var(--button-bg);
      color: var(--button-fg);
      padding: 8px 12px;
      border-radius: 999px;
      cursor: pointer;
      font: inherit;
    }

    .toolbar button:hover {
      background: var(--button-hover);
    }

    .toolbar button.primary {
      background: var(--primary-bg);
      border-color: var(--primary-bg);
      color: var(--primary-fg);
    }

    .toolbar button.primary:hover {
      background: var(--primary-hover);
      border-color: var(--primary-hover);
    }

    .stage {
      min-height: calc(100vh - 66px);
      padding: 28px 24px 72px;
      display: flex;
      justify-content: center;
    }

    .page-frame {
      width: min(100%, 9.4in);
      padding: 24px;
      border: 1px solid var(--chrome-border);
      border-radius: 22px;
      background: var(--chrome-bg);
    }

    .page-note {
      color: var(--muted);
      font-size: 12px;
      margin: 0 0 14px;
    }

    .page {
      width: 8.27in;
      min-height: 11.69in;
      margin: 0 auto;
      background: var(--page-bg);
      color: var(--page-text);
      border: 1px solid var(--page-border);
      border-radius: 8px;
      box-shadow: var(--page-shadow);
      padding: 0.9in 0.85in;
    }

    .document-surface {
      min-height: calc(11.69in - 1.8in);
      outline: none;
      font: 12pt/1.65 "Aptos", "Calibri", "Segoe UI", sans-serif;
    }

    .document-surface:focus {
      box-shadow: 0 0 0 2px var(--focus);
      border-radius: 2px;
    }

    .document-surface > :first-child {
      margin-top: 0;
    }

    .document-surface h1,
    .document-surface h2,
    .document-surface h3,
    .document-surface h4 {
      font-family: "Aptos Display", "Aptos", "Calibri", "Segoe UI", sans-serif;
      color: var(--page-text);
      line-height: 1.2;
      margin-top: 1.45em;
      margin-bottom: 0.55em;
      page-break-after: avoid;
    }

    .document-surface h1 { font-size: 20pt; }
    .document-surface h2 { font-size: 16pt; }
    .document-surface h3 { font-size: 13pt; }
    .document-surface h4 { font-size: 12pt; }

    .document-surface p,
    .document-surface li,
    .document-surface td,
    .document-surface th {
      color: var(--page-text);
    }

    .document-surface p,
    .document-surface ul,
    .document-surface ol,
    .document-surface table,
    .document-surface hr,
    .document-surface blockquote {
      margin-top: 0;
      margin-bottom: 1em;
    }

    .document-surface ul,
    .document-surface ol {
      padding-left: 1.5em;
    }

    .document-surface table {
      width: 100%;
      border-collapse: collapse;
      font-size: 10.5pt;
    }

    .document-surface th,
    .document-surface td {
      padding: 8px 10px;
      border: 1px solid #cbd5e1;
      vertical-align: top;
    }

    .document-surface th {
      background: #f8fafc;
      font-weight: 700;
    }

    .document-surface hr {
      border: none;
      border-top: 1px solid #cbd5e1;
    }

    .document-surface blockquote {
      padding-left: 1em;
      border-left: 3px solid #cbd5e1;
      color: var(--page-muted);
    }

    .document-surface code {
      font-family: Consolas, "SFMono-Regular", monospace;
      font-size: 0.92em;
      background: #f3f4f6;
      border-radius: 4px;
      padding: 0.08em 0.3em;
    }

    .document-surface pre {
      overflow-x: auto;
      padding: 12px 14px;
      border-radius: 8px;
      background: #f8fafc;
      border: 1px solid #e5e7eb;
    }

    .document-surface a {
      color: #1d4ed8;
      text-decoration: underline;
    }

    .document-surface [data-placeholder]:empty::before {
      content: attr(data-placeholder);
      color: #94a3b8;
    }

    .document-surface :focus {
      outline: none;
    }

    @media (max-width: 980px) {
      .stage {
        padding: 16px 10px 48px;
      }

      .page-frame {
        width: 100%;
        padding: 12px;
        border-radius: 14px;
      }

      .page {
        width: 100%;
        min-height: auto;
        padding: 32px 24px;
      }
    }
  </style>
</head>
<body>
  <div class="toolbar">
    <div class="toolbar-title">DocMD Editor</div>
    <div class="toolbar-meta">The app chrome follows your VS Code theme. Only the page stays white, like a document sheet.</div>
    <button id="openRaw">Open Raw</button>
    <button id="exportDocx">Export DOCX</button>
    <button id="exportPdf">Export PDF</button>
    <button id="save" class="primary">Save</button>
  </div>
  <div class="stage">
    <div class="page-frame">
      <p class="page-note">Edit the imported document directly on the page. Use Open Raw only when you need the canonical Markdown source.</p>
      <article
        id="document"
        class="page document-surface"
        contenteditable="true"
        spellcheck="true"
        data-placeholder="Imported content will appear here."
      ></article>
    </div>
  </div>

  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const documentSurface = document.getElementById('document');

    documentSurface.innerHTML = ${documentHtmlJson};

    function currentDocumentHtml() {
      return documentSurface.innerHTML;
    }

    document.getElementById('save').addEventListener('click', () => {
      vscode.postMessage({ type: 'save', documentHtml: currentDocumentHtml() });
    });

    document.getElementById('openRaw').addEventListener('click', () => {
      vscode.postMessage({ type: 'openRaw' });
    });

    document.getElementById('exportDocx').addEventListener('click', () => {
      vscode.postMessage({ type: 'export', format: 'docx', documentHtml: currentDocumentHtml() });
    });

    document.getElementById('exportPdf').addEventListener('click', () => {
      vscode.postMessage({ type: 'export', format: 'pdf', documentHtml: currentDocumentHtml() });
    });

    window.addEventListener('keydown', (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') {
        event.preventDefault();
        vscode.postMessage({ type: 'save', documentHtml: currentDocumentHtml() });
      }
    });

    vscode.postMessage({ type: 'ready' });
  </script>
</body>
</html>`;
  }
}

function createNonce(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let value = '';
  for (let index = 0; index < 32; index += 1) {
    value += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return value;
}
