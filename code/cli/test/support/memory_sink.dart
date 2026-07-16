import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Captures everything written to an [IOSink] so tests can assert on the exact
/// bytes a command emitted to stdout / stderr.
class MemorySink {
  final _consumer = _MemoryStreamConsumer();
  late final IOSink sink = IOSink(_consumer);

  Future<String> text() async {
    await sink.flush();
    return utf8.decode(_consumer.bytes);
  }
}

class _MemoryStreamConsumer implements StreamConsumer<List<int>> {
  final List<int> bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}

  Future<void> get done async {}
}
