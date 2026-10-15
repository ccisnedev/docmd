import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/pdf/content_stream_text.dart';
import 'package:docmd_cli/src/ingestion/pdf/to_unicode_cmap.dart';

void main() {
  // A font whose glyph codes decode to letters, a space, and a couple of extras.
  final latin = ToUnicodeCMap.parse('''
6 beginbfchar
<0001> <0048>
<0002> <0069>
<0003> <0020>
<0004> <0057>
<0005> <006F>
<0006> <0072>
<0007> <006C>
<0008> <0064>
endbfchar
''');

  ToUnicodeCMap? only(String want, String name) => name == want ? latin : null;

  group('extractTextFromContentStream', () {
    test('decodes a Tj hex string through the active font CMap', () {
      // /F1 Tf, then show <0001 0002> => "Hi".
      const stream = 'BT /F1 12 Tf <00010002> Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('Hi'));
    });

    test('decodes a TJ array, honouring glyph-encoded spaces', () {
      // "Hi World" via glyphs, with the space as its own glyph <0003>.
      const stream =
          'BT /F1 12 Tf [<0001><0002>]TJ [<0003>]TJ [<0004><0005><0006><0007><0008>]TJ ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('Hi World'));
    });

    test('starts a new line on a text-positioning move', () {
      const stream =
          'BT /F1 12 Tf <0001> Tj 0 -14 Td <0002> Tj T* <0003> Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      final lines = text.trim().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.first, equals('H'));
      expect(lines[1], equals('i'));
    });

    test('breaks lines when the text matrix drops to a new y', () {
      // Word-style PDFs position each line with Tm rather than Td; a change in
      // the y translation (6th operand) is a new line.
      const stream = 'BT /F1 12 Tf '
          '1 0 0 1 72 700 Tm <0001> Tj '
          '1 0 0 1 72 686 Tm <0002> Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      final lines = text.trim().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, equals(['H', 'i']));
    });

    test('keeps text on one line when the text matrix y does not change', () {
      const stream = 'BT /F1 12 Tf '
          '1 0 0 1 72 700 Tm <0001> Tj '
          '1 0 0 1 90 700 Tm <0002> Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('Hi'));
    });

    test('switches CMap when the font changes', () {
      final other = ToUnicodeCMap.parse('''
1 beginbfchar
<0001> <005A>
endbfchar
''');
      ToUnicodeCMap? cmapFor(String name) => name == 'F2' ? other : latin;

      const stream = 'BT /F1 12 Tf <0001> Tj /F2 12 Tf <0001> Tj ET';
      final text = extractTextFromContentStream(stream, cmapFor);
      // F1: <0001>->H, F2: <0001>->Z.
      expect(text.replaceAll(RegExp(r'\s+'), ''), equals('HZ'));
    });

    test('drops a glyph the CMap does not map rather than emitting garbage', () {
      const stream = 'BT /F1 12 Tf <00010099> Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      // <0099> is unmapped; only the mapped H survives.
      expect(text.trim(), equals('H'));
    });

    test('inserts a space for a large negative TJ kerning adjustment', () {
      // Two words with no space glyph, separated only by positioning.
      const stream = 'BT /F1 12 Tf [<0001>-400<0002>]TJ ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('H i'));
    });

    // Typst shows 2-byte Identity-H codes as literal strings with octal and
    // control escapes: glyph 1 is (\000\001), glyph 8 is (\000\b).
    test('decodes 2-byte codes in a literal string through octal escapes', () {
      const stream = r'BT /F1 12 Tf (\000\001\000\002) Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('Hi'));
    });

    test('decodes the control escapes of a literal string', () {
      // \b is byte 8: "d" in this CMap.
      const stream = r'BT /F1 12 Tf [(\000\004\000\005\000\006\000\007\000\b)] TJ ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('World'));
    });

    // Glyph 0x5D is "]": a bracket inside a string must not end the TJ array.
    test('keeps a TJ array whole when a string holds a bracket byte', () {
      final brackets = ToUnicodeCMap.parse('''
2 beginbfchar
<005D> <0021>
<0001> <0048>
endbfchar
''');
      const stream = r'BT /F1 12 Tf [(\000\001) -50 (\000]) -50 (\000\001)] TJ ET';
      final text = extractTextFromContentStream(stream, (_) => brackets);
      expect(text.trim(), equals('H!H'));
    });

    // Typst positions every run with the CTM (`cm` inside q/Q) and leaves Tm
    // at the same value, so lines and separate runs are only visible in `cm`.
    test('breaks lines when the CTM moves to a new y', () {
      const stream =
          'q 1 0 0 -1 70 760 cm BT /F1 12 Tf 1 0 0 -1 0 0 Tm <0001> Tj ET Q '
          'q 1 0 0 -1 70 745 cm BT /F1 12 Tf 1 0 0 -1 0 0 Tm <0002> Tj ET Q';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      final lines = text.trim().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, equals(['H', 'i']));
    });

    test('separates runs placed apart on the same line by the CTM', () {
      // "i", then "Hi", then " W" (a run that already starts with a space
      // glyph gets no extra one).
      const stream = 'q 1 0 0 -1 70 760 cm BT /F1 12 Tf <0002> Tj ET Q '
          'q 1 0 0 -1 83 760 cm BT /F1 12 Tf <00010002> Tj ET Q '
          'q 1 0 0 -1 99 760 cm BT /F1 12 Tf <00030004> Tj ET Q';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('i Hi W'));
    });

    // Typst reuses a glyph whose ToUnicode says "ó" for a plain "o" and wraps
    // that use in `/Span << /ActualText (o) >> BDC ... EMC`: the marked text,
    // not the glyph's mapping, is what the run says.
    test('prefers a marked-content ActualText over the glyph mapping', () {
      const stream = 'BT /F1 12 Tf <0001> Tj '
          '/Span << /ActualText (o) >> BDC <0002> Tj EMC '
          '<0001> Tj ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('HoH'));
    });

    test('decodes a UTF-16BE ActualText and ignores spans without one', () {
      // FE FF 00 F3 is "ó"; the outer span has only an MCID.
      const stream = r'BT /F1 12 Tf /Span << /MCID 0 >> BDC <0001> Tj '
          r'/Span << /ActualText (\376\377\000\363) >> BDC <0002> Tj EMC EMC ET';
      final text = extractTextFromContentStream(stream, (n) => only('F1', n));
      expect(text.trim(), equals('Hó'));
    });

    test('returns empty text when there is no font to decode with', () {
      const stream = 'BT <0001> Tj ET';
      final text = extractTextFromContentStream(stream, (_) => null);
      expect(text.trim(), isEmpty);
    });
  });
}
