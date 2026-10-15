library;

import 'to_unicode_cmap.dart';

/// Extracts readable text from a decoded page content stream.
///
/// Content streams are PostScript-like: operands precede their operator. This
/// walks the token stream, tracks the active font (set by `Tf`), and turns the
/// glyph codes shown by `Tj`/`TJ` back into text through that font's
/// [ToUnicodeCMap]. [cmapFor] maps a font resource name (e.g. `F1`) to its CMap,
/// or null when the font has none — in which case its glyphs are dropped rather
/// than emitted as noise.
///
/// Layout is approximated, not reconstructed: a text-positioning move starts a
/// new line, and a large negative `TJ` kerning adjustment inserts a space (word
/// gaps that carry no space glyph). That is enough for LLM-facing plain text,
/// which needs the words in order rather than pixel positions.
String extractTextFromContentStream(
  String content,
  ToUnicodeCMap? Function(String fontResourceName) cmapFor,
) {
  final out = StringBuffer();
  final operands = <_Token>[];
  String? currentFont;
  // y of the current text line, tracked so a drop to a new line becomes a
  // newline even in PDFs that position every line with an absolute Tm.
  double? lineY;
  // Translation of the last `cm`. Typst places every run through the CTM and
  // leaves Tm alone, so this is where its lines and word runs show up.
  double? ctmX;
  double? ctmY;
  // A run placed apart on the same line: separate it from the previous one
  // unless either side already carries the space.
  var pendingSpace = false;
  // Open marked-content sequences (BMC/BDC … EMC). While one carries an
  // /ActualText, that text replaces whatever glyphs it encloses.
  var markedDepth = 0;
  int? actualTextDepth;

  void breakLine() {
    pendingSpace = false;
    if (out.isNotEmpty && !out.toString().endsWith('\n')) {
      out.write('\n');
    }
  }

  void show(String text, {bool actual = false}) {
    if (text.isEmpty || (actualTextDepth != null && !actual)) return;
    if (pendingSpace && out.isNotEmpty) {
      final before = out.toString();
      final last = before.codeUnitAt(before.length - 1);
      final first = text.codeUnitAt(0);
      // Runs set flush against punctuation (an italic title and its period,
      // a styled word in parentheses) are not separate words.
      if (!_isSpace(last) &&
          !_isSpace(first) &&
          !_opensFlush(last) &&
          !_closesFlush(first)) {
        out.write(' ');
      }
    }
    pendingSpace = false;
    out.write(text);
  }

  for (final token in _tokenize(content)) {
    if (token.type != _TokenType.op) {
      operands.add(token);
      continue;
    }

    switch (token.text) {
      case 'Tf':
        final name = operands.lastWhere(
          (o) => o.type == _TokenType.name,
          orElse: () => _Token(_TokenType.name, currentFont ?? ''),
        );
        currentFont = name.text;
      case 'Tj':
        final string = _lastString(operands);
        if (string != null) {
          show(_decodeString(string, cmapFor(currentFont ?? '')));
        }
      case 'TJ':
        final array = operands.lastWhere(
          (o) => o.type == _TokenType.array,
          orElse: () => _Token(_TokenType.array, ''),
        );
        show(_decodeArray(array.text, cmapFor(currentFont ?? '')));
      case 'BMC':
        markedDepth++;
      case 'BDC':
        markedDepth++;
        final properties = operands.lastWhere(
          (o) => o.type == _TokenType.dict,
          orElse: () => const _Token(_TokenType.dict, ''),
        );
        final actual = _actualText(properties.text);
        if (actual != null && actualTextDepth == null) {
          show(actual, actual: true);
          actualTextDepth = markedDepth;
        }
      case 'EMC':
        if (markedDepth == actualTextDepth) actualTextDepth = null;
        if (markedDepth > 0) markedDepth--;
      case 'cm':
        final nums = _numbers(operands);
        if (nums.length >= 6) {
          final (x, y) = (nums[4], nums[5]);
          final (previousX, previousY) = (ctmX, ctmY);
          if (previousY != null && (previousY - y).abs() > _lineMoveThreshold) {
            breakLine();
          } else if (previousX != null &&
              (previousX - x).abs() > _lineMoveThreshold) {
            pendingSpace = true;
          }
          (ctmX, ctmY) = (x, y);
        }
      case 'Tm':
        // a b c d e f — f is the y translation of the text line.
        final nums = _numbers(operands);
        if (nums.length >= 6) {
          final y = nums[5];
          final previousY = lineY;
          if (previousY != null && (previousY - y).abs() > _lineMoveThreshold) {
            breakLine();
          }
          lineY = y;
        }
      case 'Td':
      case 'TD':
        // tx ty — a non-trivial vertical offset moves to a new line.
        final nums = _numbers(operands);
        final ty = nums.length >= 2 ? nums[1] : 0;
        if (ty.abs() > _lineMoveThreshold) {
          breakLine();
          final previousY = lineY;
          if (previousY != null) lineY = previousY + ty;
        }
      case 'T*':
      case "'":
      case '"':
        breakLine();
    }
    operands.clear();
  }

  return out.toString();
}

/// Trailing numeric operands, in order, for operators like Tm/Td.
List<double> _numbers(List<_Token> operands) => operands
    .where((o) => o.type == _TokenType.number)
    .map((o) => double.tryParse(o.text) ?? 0)
    .toList();

/// A text-matrix / line move larger than this (text-space units) is a new line.
const double _lineMoveThreshold = 1.0;

/// Kerning more negative than this (thousandths of an em) is treated as a word
/// gap and rendered as a space.
const int _wordGapThreshold = 200;

_Token? _lastString(List<_Token> operands) {
  for (final o in operands.reversed) {
    if (o.type == _TokenType.hexString || o.type == _TokenType.literalString) {
      return o;
    }
  }
  return null;
}

String _decodeString(_Token string, ToUnicodeCMap? cmap) {
  if (string.type == _TokenType.hexString) {
    return _decodeGlyphHex(string.text, cmap);
  }
  return _decodeLiteral(string.text, cmap);
}

String _decodeArray(String inner, ToUnicodeCMap? cmap) {
  final buffer = StringBuffer();
  for (final token in _tokenize(inner)) {
    switch (token.type) {
      case _TokenType.hexString:
        buffer.write(_decodeGlyphHex(token.text, cmap));
      case _TokenType.literalString:
        buffer.write(_decodeLiteral(token.text, cmap));
      case _TokenType.number:
        final adjustment = double.tryParse(token.text) ?? 0;
        if (adjustment < -_wordGapThreshold) {
          buffer.write(' ');
        }
      default:
        break;
    }
  }
  return buffer.toString();
}

/// Splits a hex glyph string into codes of the font's width (1 byte for simple
/// fonts, 2 for Identity-H) and maps each through the CMap. Unmapped codes are
/// dropped rather than emitted as noise.
String _decodeGlyphHex(String hex, ToUnicodeCMap? cmap) {
  if (cmap == null) return '';
  final width = cmap.codeByteLength * 2; // hex chars per code
  final buffer = StringBuffer();
  for (var i = 0; i + width <= hex.length; i += width) {
    final code = int.parse(hex.substring(i, i + width), radix: 16);
    final mapped = cmap[code];
    if (mapped != null) buffer.write(mapped);
  }
  return buffer.toString();
}

/// Literal strings are byte codes, grouped by the font's code width like hex
/// strings (Typst writes 2-byte Identity-H codes as `(\000\001)`). A 1-byte
/// code the CMap does not map falls back to the raw byte as a character (best
/// effort); a wider one is dropped, as in [_decodeGlyphHex].
String _decodeLiteral(String literal, ToUnicodeCMap? cmap) {
  final width = cmap?.codeByteLength ?? 1;
  if (width > 1) {
    final bytes = literal.codeUnits;
    final buffer = StringBuffer();
    for (var i = 0; i + width <= bytes.length; i += width) {
      var code = 0;
      for (var j = 0; j < width; j++) {
        code = (code << 8) | (bytes[i + j] & 0xFF);
      }
      final mapped = cmap![code];
      if (mapped != null) buffer.write(mapped);
    }
    return buffer.toString();
  }
  final buffer = StringBuffer();
  for (final code in literal.codeUnits) {
    final mapped = cmap?[code];
    buffer.write(mapped ?? String.fromCharCode(code));
  }
  return buffer.toString();
}

enum _TokenType { name, number, hexString, literalString, array, dict, op }

class _Token {
  final _TokenType type;
  final String text;
  const _Token(this.type, this.text);
}

const int _slash = 0x2F; // /
const int _lt = 0x3C; // <
const int _gt = 0x3E; // >
const int _lparen = 0x28; // (
const int _rparen = 0x29; // )
const int _lbracket = 0x5B; // [
const int _rbracket = 0x5D; // ]
const int _backslash = 0x5C; // \

Iterable<_Token> _tokenize(String s) sync* {
  var i = 0;
  final n = s.length;

  while (i < n) {
    final c = s.codeUnitAt(i);

    if (_isWhitespace(c)) {
      i++;
      continue;
    }

    if (c == _slash) {
      final start = ++i;
      while (i < n && !_isDelimiterOrSpace(s.codeUnitAt(i))) {
        i++;
      }
      yield _Token(_TokenType.name, s.substring(start, i));
      continue;
    }

    // An inline dictionary (`<< … >>`), such as a BDC property list. Strings
    // inside it may hold `>`, so they are skipped whole.
    if (c == _lt && i + 1 < n && s.codeUnitAt(i + 1) == _lt) {
      final start = i += 2;
      var depth = 1;
      while (i < n) {
        final ch = s.codeUnitAt(i);
        if (ch == _lparen) {
          i = _readLiteral(s, i).$2;
          continue;
        }
        if (ch == _lt && i + 1 < n && s.codeUnitAt(i + 1) == _lt) {
          depth++;
          i += 2;
          continue;
        }
        if (ch == _gt && i + 1 < n && s.codeUnitAt(i + 1) == _gt) {
          if (--depth == 0) break;
          i += 2;
          continue;
        }
        i++;
      }
      yield _Token(_TokenType.dict, s.substring(start, i.clamp(start, n)));
      i += 2; // consume '>>'
      continue;
    }

    if (c == _lt) {
      final start = ++i;
      while (i < n && s.codeUnitAt(i) != _gt) {
        i++;
      }
      final hex = s.substring(start, i).replaceAll(RegExp(r'\s'), '');
      i++; // consume '>'
      yield _Token(_TokenType.hexString, hex);
      continue;
    }

    if (c == _lparen) {
      final (literal, end) = _readLiteral(s, i);
      i = end;
      yield _Token(_TokenType.literalString, literal);
      continue;
    }

    if (c == _lbracket) {
      final start = ++i;
      var depth = 1;
      while (i < n && depth > 0) {
        final ch = s.codeUnitAt(i);
        // A string may hold any byte, brackets included: skip it whole.
        if (ch == _lparen) {
          i = _readLiteral(s, i).$2;
          continue;
        }
        if (ch == _lt) {
          final close = s.indexOf('>', i);
          i = close < 0 ? n : close + 1;
          continue;
        }
        if (ch == _lbracket) depth++;
        if (ch == _rbracket) depth--;
        if (depth == 0) break;
        i++;
      }
      yield _Token(_TokenType.array, s.substring(start, i));
      i++; // consume ']'
      continue;
    }

    if (_isNumberStart(c)) {
      final start = i++;
      while (i < n && _isNumberChar(s.codeUnitAt(i))) {
        i++;
      }
      yield _Token(_TokenType.number, s.substring(start, i));
      continue;
    }

    // Anything else is an operator token (letters, ', ", T*, etc.).
    final start = i++;
    while (i < n && !_isDelimiterOrSpace(s.codeUnitAt(i))) {
      i++;
    }
    yield _Token(_TokenType.op, s.substring(start, i));
  }
}

bool _isWhitespace(int c) =>
    c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00;

bool _isNumberStart(int c) =>
    (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;

bool _isNumberChar(int c) => (c >= 0x30 && c <= 0x39) || c == 0x2E;

bool _isDelimiterOrSpace(int c) =>
    _isWhitespace(c) ||
    c == _slash ||
    c == _lt ||
    c == _gt ||
    c == _lparen ||
    c == _rparen ||
    c == _lbracket ||
    c == _rbracket;

/// Reads the literal string opening at `s[start]` (a `(`) and returns its
/// bytes with escapes resolved, plus the index just past its closing `)`.
/// Balanced parentheses nest; `\n \r \t \b \f \( \) \` and up to three octal
/// digits are escapes; a backslash before a line break continues the line.
(String, int) _readLiteral(String s, int start) {
  final n = s.length;
  final buffer = StringBuffer();
  var i = start + 1;
  var depth = 1;
  while (i < n) {
    final ch = s.codeUnitAt(i);
    if (ch == _backslash && i + 1 < n) {
      final next = s.codeUnitAt(i + 1);
      i += 2;
      if (next >= 0x30 && next <= 0x37) {
        var value = next - 0x30;
        for (var k = 0; k < 2 && i < n; k++) {
          final d = s.codeUnitAt(i);
          if (d < 0x30 || d > 0x37) break;
          value = value * 8 + (d - 0x30);
          i++;
        }
        buffer.writeCharCode(value & 0xFF);
        continue;
      }
      if (next == 0x0D) {
        if (i < n && s.codeUnitAt(i) == 0x0A) i++;
        continue;
      }
      if (next == 0x0A) continue;
      buffer.writeCharCode(_literalEscapes[next] ?? next);
      continue;
    }
    if (ch == _lparen) depth++;
    if (ch == _rparen && --depth == 0) {
      return (buffer.toString(), i + 1);
    }
    buffer.writeCharCode(ch);
    i++;
  }
  return (buffer.toString(), n);
}

const Map<int, int> _literalEscapes = {
  0x6E: 0x0A, // \n
  0x72: 0x0D, // \r
  0x74: 0x09, // \t
  0x62: 0x08, // \b
  0x66: 0x0C, // \f
};

bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x09 || c == 0xA0;

/// The /ActualText of a marked-content property list, or null when it has
/// none. It is a PDF text string: UTF-16BE behind a FE FF mark, otherwise
/// PDFDocEncoding, read here as Latin-1 (identical for the printable range).
String? _actualText(String properties) {
  final tokens = _tokenize(properties).toList();
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (tokens[i].type != _TokenType.name || tokens[i].text != 'ActualText') {
      continue;
    }
    final value = tokens[i + 1];
    final List<int> bytes;
    if (value.type == _TokenType.literalString) {
      bytes = value.text.codeUnits;
    } else if (value.type == _TokenType.hexString) {
      final hex = value.text.length.isOdd ? '${value.text}0' : value.text;
      bytes = [
        for (var k = 0; k + 2 <= hex.length; k += 2)
          int.parse(hex.substring(k, k + 2), radix: 16),
      ];
    } else {
      return null;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[
        for (var k = 2; k + 1 < bytes.length; k += 2)
          (bytes[k] << 8) | bytes[k + 1],
      ];
      return String.fromCharCodes(units);
    }
    return String.fromCharCodes(bytes);
  }
  return null;
}

/// Punctuation a following run attaches to without a space: `(`, `[`, `{`,
/// opening quotes, and Spanish `¿` `¡`.
bool _opensFlush(int c) => '([{¿¡«“‘'.codeUnits.contains(c);

/// Punctuation that attaches to the preceding run without a space.
bool _closesFlush(int c) => '.,;:!?)]}%»”’'.codeUnits.contains(c);
