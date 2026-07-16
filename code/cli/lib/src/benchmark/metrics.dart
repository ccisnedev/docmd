library;

/// Structural metrics extracted from a Markdown ingestion, used to compare
/// engines on a shared corpus. These are content-coverage signals — text volume,
/// structure, tables, images — not style fidelity, matching DocMD's
/// content-over-style ingestion objective.
class IngestionMetrics {
  final int words;
  final int headings;
  final int tables;
  final int images;

  const IngestionMetrics({
    required this.words,
    required this.headings,
    required this.tables,
    required this.images,
  });

  factory IngestionMetrics.fromMarkdown(String markdown) {
    return IngestionMetrics(
      words: tokenize(markdown).length,
      headings: countHeadings(markdown),
      tables: countTables(markdown),
      images: countImages(markdown),
    );
  }

  Map<String, dynamic> toJson() => {
    'words': words,
    'headings': headings,
    'tables': tables,
    'images': images,
  };
}

final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _headingPattern = RegExp(r'^\s{0,3}#{1,6}\s', multiLine: true);
final RegExp _imagePattern = RegExp(r'!\[[^\]]*\]\([^)]*\)');

/// Lowercased alphanumeric tokens (words), Unicode-aware.
List<String> tokenize(String text) {
  return _wordPattern
      .allMatches(text.toLowerCase())
      .map((m) => m[0]!)
      .toList(growable: false);
}

/// Count of GFM heading lines (`#`..`######`).
int countHeadings(String markdown) => _headingPattern.allMatches(markdown).length;

/// Count of Markdown image references `![alt](src)`.
int countImages(String markdown) => _imagePattern.allMatches(markdown).length;

/// Count of GFM pipe tables, detected by their delimiter row
/// (e.g. `| --- | :--: |`). One delimiter row ≈ one table.
int countTables(String markdown) {
  var count = 0;
  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.contains('|') || !line.contains('-')) {
      continue;
    }
    // A delimiter row is composed only of pipes, dashes, colons and spaces.
    if (RegExp(r'^\|?[\s:\-|]+\|?$').hasMatch(line) &&
        RegExp(r'-').hasMatch(line) &&
        line.contains('|')) {
      count += 1;
    }
  }
  return count;
}

/// Fraction of the reference's unique vocabulary that appears in the candidate.
/// A recall of 1.0 means the candidate captured every distinct word the
/// reference did; 0.0 means none. Empty reference yields 1.0 (nothing to miss).
double textRecall(String reference, String candidate) {
  final referenceTokens = tokenize(reference).toSet();
  if (referenceTokens.isEmpty) return 1.0;
  final candidateTokens = tokenize(candidate).toSet();
  final captured =
      referenceTokens.where(candidateTokens.contains).length;
  return captured / referenceTokens.length;
}
