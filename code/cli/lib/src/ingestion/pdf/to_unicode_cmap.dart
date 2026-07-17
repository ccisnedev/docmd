library;

/// Maps font glyph codes back to Unicode using a font's `/ToUnicode` CMap.
///
/// PDF content streams show text as glyph codes (indices into a subset font),
/// not characters. The `/ToUnicode` CMap is the table that turns those codes
/// back into readable text; without it, the codes are unrecoverable. This parses
/// the two block types PDFs actually emit — `bfchar` (single mappings) and
/// `bfrange` (ranges, either incrementing or with an explicit array) — and
/// ignores the PostScript boilerplate around them.
class ToUnicodeCMap {
  final Map<int, String> _map;

  /// Bytes per glyph code in this font's encoding: 1 for simple byte-encoded
  /// fonts, 2 for Identity-H CID fonts. Content-stream hex strings are split
  /// into codes of this width. Defaults to 2 when the CMap gives no hint.
  final int codeByteLength;

  ToUnicodeCMap(this._map, {this.codeByteLength = 2});

  bool get isEmpty => _map.isEmpty;

  /// The Unicode string for [code], or null if the CMap does not map it.
  String? operator [](int code) => _map[code];

  factory ToUnicodeCMap.parse(String source) {
    final map = <int, String>{};
    _parseBfChar(source, map);
    _parseBfRange(source, map);
    return ToUnicodeCMap(map, codeByteLength: _codeWidth(source, map));
  }

  static final _bfCharBlock =
      RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true);
  static final _bfRangeBlock =
      RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true);
  static final _codespaceBlock =
      RegExp(r'begincodespacerange(.*?)endcodespacerange', dotAll: true);
  static final _hex = RegExp(r'<([0-9A-Fa-f]+)>');

  /// The code width is authoritative from the codespace range (`<00> <FF>` = 1
  /// byte, `<0000> <FFFF>` = 2); if absent, inferred from a mapping key's width.
  static int _codeWidth(String source, Map<int, String> map) {
    final codespace = _codespaceBlock.firstMatch(source);
    if (codespace != null) {
      final bound = _hex.firstMatch(codespace.group(1)!);
      if (bound != null) {
        return (bound.group(1)!.length / 2).ceil().clamp(1, 4);
      }
    }
    // Fall back to the first source code seen in a mapping block.
    for (final block in [
      ..._bfCharBlock.allMatches(source),
      ..._bfRangeBlock.allMatches(source),
    ]) {
      final first = _hex.firstMatch(block.group(1)!);
      if (first != null) {
        return (first.group(1)!.length / 2).ceil().clamp(1, 4);
      }
    }
    return 2;
  }
  // One bfrange entry: <lo> <hi> then either <dst> or [ <d0> <d1> ... ].
  static final _rangeEntry = RegExp(
    r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(?:<([0-9A-Fa-f]+)>|\[([^\]]*)\])',
  );

  static void _parseBfChar(String source, Map<int, String> map) {
    for (final block in _bfCharBlock.allMatches(source)) {
      final body = block.group(1)!;
      final tokens = _hex.allMatches(body).toList();
      // Entries are pairs: <code> <destination>.
      for (var i = 0; i + 1 < tokens.length; i += 2) {
        final code = int.parse(tokens[i].group(1)!, radix: 16);
        map[code] = _decodeUtf16Be(tokens[i + 1].group(1)!);
      }
    }
  }

  static void _parseBfRange(String source, Map<int, String> map) {
    for (final block in _bfRangeBlock.allMatches(source)) {
      for (final entry in _rangeEntry.allMatches(block.group(1)!)) {
        final lo = int.parse(entry.group(1)!, radix: 16);
        final hi = int.parse(entry.group(2)!, radix: 16);

        final singleDst = entry.group(3);
        if (singleDst != null) {
          // Incrementing form: dst applies to lo, +1 for each code up to hi.
          final base = _decodeUtf16Be(singleDst);
          final baseRune = base.runes.isEmpty ? 0 : base.runes.last;
          final prefix = String.fromCharCodes(
            base.runes.take(base.runes.length - 1),
          );
          for (var code = lo; code <= hi; code++) {
            map[code] = prefix + String.fromCharCode(baseRune + (code - lo));
          }
          continue;
        }

        // Array form: one explicit destination per code in the range.
        final dsts = _hex.allMatches(entry.group(4)!).toList();
        for (var i = 0; i < dsts.length && lo + i <= hi; i++) {
          map[lo + i] = _decodeUtf16Be(dsts[i].group(1)!);
        }
      }
    }
  }

  /// A ToUnicode destination is a big-endian UTF-16 string (one or more code
  /// units), e.g. `00660069` -> "fi".
  static String _decodeUtf16Be(String hex) {
    final units = <int>[];
    for (var i = 0; i + 4 <= hex.length; i += 4) {
      units.add(int.parse(hex.substring(i, i + 4), radix: 16));
    }
    if (units.isEmpty && hex.isNotEmpty) {
      // Odd single-byte destination; treat as one code point.
      units.add(int.parse(hex, radix: 16));
    }
    return String.fromCharCodes(units);
  }
}
