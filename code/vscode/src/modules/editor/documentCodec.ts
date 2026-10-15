import MarkdownIt from 'markdown-it';
import { NodeHtmlMarkdown } from 'node-html-markdown';

const markdownRenderer = new MarkdownIt({
  html: false,
  breaks: true,
  linkify: true,
  typographer: false,
});

const htmlToMarkdown = new NodeHtmlMarkdown({
  bulletMarker: '-',
  codeFence: '```',
  textReplace: [
    [new RegExp(String.raw`\u00a0`, 'g'), ' '],
  ],
});

/** Carries the canonical `src` across the display rewrite, so saving can undo it. */
const ORIGINAL_SRC_ATTRIBUTE = 'data-docmd-src';

export interface RenderOptions {
  /**
   * Maps a package-relative image path to something the display surface can
   * actually load. A webview cannot resolve `../assets/media/x.png` against its
   * own origin, so without this every image renders broken.
   */
  resolveSrc?: (src: string) => string;
}

export interface ParseOptions {
  /**
   * Last-resort reverse of {@link RenderOptions.resolveSrc}, used only when the
   * `data-docmd-src` attribute did not survive the round trip. Without it a
   * display URI would be written into the canonical Markdown, which points the
   * package at a location that exists only inside one webview session.
   */
  restoreSrc?: (src: string) => string;
}

interface RenderEnvironment {
  resolveSrc?: (src: string) => string;
}

// markdown-it's default image rule, plus the display rewrite. Overriding the
// rule rather than post-processing the HTML keeps the transformation on the
// token, where the original `src` is unambiguous.
markdownRenderer.renderer.rules.image = (tokens, index, options, env, self) => {
  const token = tokens[index];
  const altIndex = token.attrIndex('alt');
  if (altIndex >= 0 && token.attrs) {
    token.attrs[altIndex][1] = self.renderInlineAsText(token.children ?? [], options, env);
  }

  const resolveSrc = (env as RenderEnvironment | undefined)?.resolveSrc;
  const src = token.attrGet('src');
  if (resolveSrc && src && !isExternalSource(src)) {
    token.attrSet(ORIGINAL_SRC_ATTRIBUTE, src);
    token.attrSet('src', resolveSrc(src));
  }

  return self.renderToken(tokens, index, options);
};

export function renderMarkdownDocument(markdown: string, options: RenderOptions = {}): string {
  const environment: RenderEnvironment = { resolveSrc: options.resolveSrc };
  return markdownRenderer.render(normalizeMarkdownForDisplay(markdown), environment);
}

export function markdownFromDocumentHtml(
  documentHtml: string,
  options: ParseOptions = {},
): string {
  const restored = restoreImageSources(normalizeDocumentHtml(documentHtml), options.restoreSrc);
  const markdown = htmlToMarkdown.translate(restored);
  return `${normalizeMarkdownOutput(markdown)}\n`;
}

/** Sources that are already loadable as written and must be left alone. */
function isExternalSource(src: string): boolean {
  return /^(https?:|data:|vscode-webview:|vscode-resource:|file:)/i.test(src);
}

/**
 * Puts the canonical path back on every `<img>` before the HTML becomes Markdown.
 *
 * The editor surface is `contenteditable`, so what comes back is whatever the
 * browser made of the injected HTML. Attributes survive, but nothing guarantees
 * it, which is why a missing `data-docmd-src` falls through to the caller's
 * reverse map instead of writing the display URI into the package.
 */
function restoreImageSources(
  documentHtml: string,
  restoreSrc?: (src: string) => string,
): string {
  return documentHtml.replace(/<img\b[^>]*>/gi, (tag) => {
    const original = new RegExp(`\\s${ORIGINAL_SRC_ATTRIBUTE}="([^"]*)"`, 'i').exec(tag);
    const stripped = tag.replace(
      new RegExp(`\\s${ORIGINAL_SRC_ATTRIBUTE}="[^"]*"`, 'gi'),
      '',
    );

    if (original) {
      return stripped.replace(/\ssrc="[^"]*"/i, ` src="${original[1]}"`);
    }

    if (!restoreSrc) {
      return stripped;
    }

    return stripped.replace(/\ssrc="([^"]*)"/i, (match, src: string) => {
      const canonical = restoreSrc(src);
      return canonical === src ? match : ` src="${canonical}"`;
    });
  });
}

function normalizeMarkdownForDisplay(markdown: string): string {
  return markdown.replace(/\\\r?\n/g, '  \n');
}

function normalizeDocumentHtml(documentHtml: string): string {
  return documentHtml
    .replace(/<div><br\s*\/?><\/div>/gi, '<p></p>')
    .replace(/<div>/gi, '<p>')
    .replace(/<\/div>/gi, '</p>')
    .replace(/&nbsp;/gi, ' ');
}

function normalizeMarkdownOutput(markdown: string): string {
  return markdown
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trimEnd();
}
