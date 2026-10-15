import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/parity.dart';

/// ADR 0003: docx and pdf need not look alike, but they must say the same
/// thing. Each render feature adds the facts it guarantees to this list.
const List<String> _facts = [
  // Section numbering (front matter number-sections: true).
  '1 Introducción',
  '1.1 Fórmulas de bloque',
  '1.2 Tablas',
  '1.4 Listas',
  // Text and structure.
  'Introducción',
  'Contar bien exige método.',
  'Fórmulas de bloque',
  'Tablas',
  'Permutación',
  'Subconjuntos de r entre n.',
  'Triángulo de Pascal en SVG.',
  'Resolver cuatro problemas de conteo.',
  'Verificar cada resultado enumerando los casos.',
];

final bool _hasTools = toolExists('pandoc') && toolExists('typst');

void main() {
  group('docx and pdf say the same thing', () {
    late Directory work;
    late ParityRender render;

    setUpAll(() async {
      work = Directory.systemTemp.createTempSync('docmd_parity_');
      render = await ParityRender.of(
        Directory(p.join('test', 'fixtures', 'parity')),
        work,
      );
    });

    tearDownAll(() => work.deleteSync(recursive: true));

    for (final fact in _facts) {
      test('both carry "$fact"', () {
        expect(render.missing(fact), isEmpty);
      });
    }
  }, skip: _hasTools ? false : 'needs pandoc and typst on PATH');
}
