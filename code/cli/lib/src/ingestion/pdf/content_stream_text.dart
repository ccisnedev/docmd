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

  void breakLine() {
    if (out.isNotEmpty && !out.toString().endsWith('\n')) {
      out.write('\n');
    }
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
          out.write(_decodeString(string, cmapFor(currentFont ?? '')));
        }
      case 'TJ':
        final array = operands.lastWhere(
          (o) => o.type == _TokenType.array,
          orElse: () => _Token(_TokenType.array, ''),
        );
        out.write(_decodeArray(array.text, cmapFor(currentFont ?? '')));
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

/// Literal strings are byte codes. Map each through the CMap when present;
/// otherwise fall back to the raw byte as a character (best effort).
String _decodeLiteral(String literal, ToUnicodeCMap? cmap) {
  final buffer = StringBuffer();
  for (final code in literal.codeUnits) {
    final mapped = cmap?[code];
    buffer.write(mapped ?? String.fromCharCode(code));
  }
  return buffer.toString();
}

enum _TokenType { name, number, hexString, literalString, array, op }

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
      i++;
      final buffer = StringBuffer();
      var depth = 1;
      while (i < n && depth > 0) {
        final ch = s.codeUnitAt(i);
        if (ch == _backslash && i + 1 < n) {
          buffer.writeCharCode(s.codeUnitAt(i + 1));
          i += 2;
          continue;
        }
        if (ch == _lparen) depth++;
        if (ch == _rparen) {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
        buffer.writeCharCode(ch);
        i++;
      }
      yield _Token(_TokenType.literalString, buffer.toString());
      continue;
    }

    if (c == _lbracket) {
      final start = ++i;
      var depth = 1;
      while (i < n && depth > 0) {
        final ch = s.codeUnitAt(i);
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
