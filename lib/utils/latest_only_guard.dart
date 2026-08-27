/// Guards a sequence of independently-started async operations so that
/// only the most-recently-started one is ever allowed to apply its
/// result — a slower, earlier operation that finishes after a newer one
/// has already started is detected as stale and should be discarded by
/// the caller.
///
/// This is the exact mechanism behind the Etapa 5C.1/5C.2 fix for TABLA
/// reverting to the wrong Site's layout: `_switchSite`, `_switchTenant`
/// and the initial dashboard bootstrap in `main.dart` each do several
/// `await`ed Firestore reads before applying their result via `setState`.
/// Without this guard, whichever call happens to finish LAST wins,
/// regardless of which one the user actually asked for last — a real,
/// reproducible race when a fast (legacy) Site switch is issued shortly
/// after a slow (dynamic) one is still in flight.
///
/// Usage:
/// ```dart
/// final LatestOnlyGuard _siteSwitchGuard = LatestOnlyGuard();
///
/// Future<void> switchSite(String siteId) async {
///   final int token = _siteSwitchGuard.start();
///   final data = await someAsyncFetch(siteId);
///   if (!_siteSwitchGuard.isCurrent(token)) return; // stale, discard
///   setState(() { ...apply data... });
/// }
/// ```
class LatestOnlyGuard {
  int _generation = 0;

  /// Call at the start of a new async operation. Returns a token to pass
  /// to [isCurrent] right before applying that operation's result.
  int start() => ++_generation;

  /// True if [token] (from a matching [start] call) is still the most
  /// recent one issued — i.e. no newer operation has started since. Once
  /// this returns `false` for a token, it can never become `true` again.
  bool isCurrent(int token) => token == _generation;

  /// Diagnostic-only: the current generation number. Not meant to be
  /// compared against directly by callers — use [isCurrent] with the
  /// token from [start] instead.
  int get debugGeneration => _generation;
}
