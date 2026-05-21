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

export function renderMarkdownDocument(markdown: string): string {
  return markdownRenderer.render(normalizeMarkdownForDisplay(markdown));
}

export function markdownFromDocumentHtml(documentHtml: string): string {
  const markdown = htmlToMarkdown.translate(normalizeDocumentHtml(documentHtml));
  return `${normalizeMarkdownOutput(markdown)}\n`;
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