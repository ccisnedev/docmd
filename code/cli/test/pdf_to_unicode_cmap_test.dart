import 'package:test/test.dart';

import 'package:docmd_cli/src/ingestion/pdf/to_unicode_cmap.dart';

void main() {
  group('ToUnicodeCMap.parse', () {
    test('maps single glyph codes from a bfchar block', () {
      // Real shape from a Word-generated PDF: <glyph> <utf16be>.
      final cmap = ToUnicodeCMap.parse('''
9 beginbfchar
<001A> <0042>
<001C> <0043>
<0028> <0045>
<003E> <0046>
endbfchar
''');

      expect(cmap[0x003E], equals('F'));
      expect(cmap[0x001A], equals('B'));
      expect(cmap[0x0028], equals('E'));
      expect(cmap[0x9999], isNull);
    });

    test('expands a bfrange with an incrementing destination', () {
      // <0001> <0002> [<0041> <00C1>] gives explicit entries; the plain form
      // <lo> <hi> <dst> increments dst across the range.
      final cmap = ToUnicodeCMap.parse('''
1 beginbfrange
<0061> <0063> <004D>
endbfrange
''');

      expect(cmap[0x0061], equals('M')); // U+004D
      expect(cmap[0x0062], equals('N')); // U+004E
      expect(cmap[0x0063], equals('O')); // U+004F
    });

    test('expands a bfrange with an explicit destination array', () {
      final cmap = ToUnicodeCMap.parse('''
1 beginbfrange
<0001> <0002> [<0041> <00C1>]
endbfrange
''');

      expect(cmap[0x0001], equals('A')); // U+0041
      expect(cmap[0x0002], equals('Á')); // U+00C1
    });

    test('decodes a multi-code-unit destination (e.g. a ligature)', () {
      // fi ligature mapped back to the two letters: <0066><0069>.
      final cmap = ToUnicodeCMap.parse('''
1 beginbfchar
<00AA> <00660069>
endbfchar
''');

      expect(cmap[0x00AA], equals('fi'));
    });

    test('handles both blocks in one CMap and ignores surrounding noise', () {
      final cmap = ToUnicodeCMap.parse('''
/CIDInit /ProcSet findresource begin
12 dict begin begincmap
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
2 beginbfchar
<0003> <0020>
<0024> <0044>
endbfchar
1 beginbfrange
<0068> <0069> <0055>
endbfrange
endcmap
''');

      expect(cmap[0x0003], equals(' '));
      expect(cmap[0x0024], equals('D'));
      expect(cmap[0x0068], equals('U'));
      expect(cmap[0x0069], equals('V'));
    });

    test('is empty for a CMap with no mappings', () {
      final cmap = ToUnicodeCMap.parse('begincmap endcmap');
      expect(cmap.isEmpty, isTrue);
      expect(cmap[0x0041], isNull);
    });

    test('reports a two-byte code width from the codespace range', () {
      // Word/Identity-H style: 2-byte codes.
      final cmap = ToUnicodeCMap.parse('''
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
1 beginbfchar
<003E> <0046>
endbfchar
''');
      expect(cmap.codeByteLength, equals(2));
    });

    test('reports a one-byte code width from the codespace range', () {
      // LibreOffice simple-TrueType style: 1-byte codes.
      final cmap = ToUnicodeCMap.parse('''
1 begincodespacerange
<00> <FF>
endcodespacerange
1 beginbfchar
<01> <0048>
endbfchar
''');
      expect(cmap.codeByteLength, equals(1));
      expect(cmap[0x01], equals('H'));
    });

    test('infers the code width from mapping keys when no codespace range', () {
      final cmap = ToUnicodeCMap.parse('''
1 beginbfchar
<0D> <0048>
endbfchar
''');
      expect(cmap.codeByteLength, equals(1));
    });
  });
}
