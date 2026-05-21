library;

import 'dart:io';

import 'package:docmd_cli/docmd_cli.dart';

Future<void> main(List<String> args) async {
  final code = await runDocmd(args);
  exit(code);
}
