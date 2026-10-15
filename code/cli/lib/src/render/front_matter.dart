library;

/// The top-level scalars of a Markdown source's leading YAML block.
///
/// Some writer options pandoc does not read from metadata (`number-sections`,
/// citation processing); docmd derives them from the front matter so the
/// Markdown stays the one place a document is configured (ADR 0003). Only flat
/// `key: value` lines at column 0 are read — the same line-wise approach as the
/// manifest's `kind`, so the CLI needs no YAML parser. Nested maps, lists and
/// block scalars are skipped, which is all these options need.
class FrontMatter {
  /// Top-level keys; a key whose value is a nested block maps to ''.
  final Map<String, String> _raw;

  FrontMatter._(this._raw);

  factory FrontMatter.parse(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    final raw = <String, String>{};
    if (lines.isEmpty || lines.first.trimRight() != '---') {
      return FrontMatter._(raw);
    }
    for (final line in lines.skip(1)) {
      final trimmed = line.trimRight();
      if (trimmed == '---' || trimmed == '...') {
        return FrontMatter._(raw);
      }
      final match = _key.firstMatch(trimmed);
      if (match != null) {
        raw[match.group(1)!] = (match.group(2) ?? '').trim();
      }
    }
    // No closing fence: not a metadata block.
    return FrontMatter._({});
  }

  /// Whether [key] is set at the top level, as a scalar or a nested block.
  bool has(String key) => _raw.containsKey(key);

  /// The value of [key] with surrounding quotes removed, or null.
  String? operator [](String key) {
    final value = _raw[key];
    if (value == null || value.isEmpty) return null;
    return _unquote(value);
  }

  /// Whether [key] is a YAML true. A quoted "true" is a string, as for pandoc.
  bool flag(String key) => _true.contains(_raw[key]);

  static String _unquote(String value) {
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  // `key: value` or a bare `key:` (a block follows) at column 0.
  static final RegExp _key = RegExp(r'^([A-Za-z0-9_-]+):(?:\s+(\S.*))?$');

  static const Set<String> _true = {
    'true',
    'True',
    'TRUE',
    'yes',
    'Yes',
    'YES',
    'on',
    'On',
    'ON',
  };
}
