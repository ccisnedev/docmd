/// A `skip` value for `test(...)`/`group(...)` that names the missing tool
/// instead of skipping silently.
///
/// `package:test`'s `skip` parameter accepts a `bool` or a `String`: `false`
/// runs the test, and any other value (including `true`) skips it, printing
/// the value's `toString()` as the reason when it is not a plain boolean.
/// Passing a bare `!hasPandoc` skips with no stated reason at all when the
/// tool is missing, which reads as a silently vanishing test rather than an
/// environment limitation. This returns `false` (run it) when [available],
/// or a message naming [tool] otherwise, so a skipped run's output says why.
Object toolSkipReason({required bool available, required String tool}) {
  if (available) return false;
  return '$tool is not installed (or not on PATH) on this machine; '
      'install it to run this test.';
}
