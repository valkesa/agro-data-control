import 'package:agro_data_control/utils/latest_only_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LatestOnlyGuard', () {
    test('a single operation is current until superseded', () {
      final LatestOnlyGuard guard = LatestOnlyGuard();
      final int token = guard.start();
      expect(guard.isCurrent(token), isTrue);
    });

    test('starting a newer operation makes the previous token stale', () {
      final LatestOnlyGuard guard = LatestOnlyGuard();
      final int tokenA = guard.start();
      final int tokenB = guard.start();

      expect(guard.isCurrent(tokenA), isFalse);
      expect(guard.isCurrent(tokenB), isTrue);
    });

    test('the exact bug scenario: slower earlier call resolves AFTER a '
        'faster later one, and must be rejected', () async {
      // Las Heras (A) is slower — needs devices+rooms reads.
      // Genetica-1 (B) is faster — legacy Site, skips those reads.
      // User: Las Heras -> Genetica-1, and Genetica-1's fetch resolves
      // first because it's structurally faster, even though it started
      // second. A's late arrival must not be allowed to apply.
      final LatestOnlyGuard guard = LatestOnlyGuard();
      final List<String> applied = <String>[];

      Future<void> switchTo(String site, {required int delayMs}) async {
        final int token = guard.start();
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (!guard.isCurrent(token)) {
          return; // stale — correctly discarded
        }
        applied.add(site);
      }

      final Future<void> lasHeras = switchTo('las-heras', delayMs: 30);
      final Future<void> genetica1 = switchTo('genetica-1', delayMs: 5);
      await Future.wait(<Future<void>>[lasHeras, genetica1]);

      // Genetica-1 resolved first and applied; Las Heras resolved later
      // but is stale by then (Genetica-1's `start()` already bumped the
      // generation) and must have been discarded.
      expect(applied, <String>['genetica-1']);
    });

    test('three-way alternation: only the very last call ever applies, '
        'regardless of resolution order', () async {
      final LatestOnlyGuard guard = LatestOnlyGuard();
      final List<String> applied = <String>[];

      Future<void> switchTo(String site, {required int delayMs}) async {
        final int token = guard.start();
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (!guard.isCurrent(token)) {
          return;
        }
        applied.add(site);
      }

      // Started in order A, B, C but resolve out of order: B, A, C.
      final Future<void> a = switchTo('A', delayMs: 20);
      final Future<void> b = switchTo('B', delayMs: 5);
      final Future<void> c = switchTo('C', delayMs: 15);
      await Future.wait(<Future<void>>[a, b, c]);

      expect(applied, <String>['C']);
    });

    test('repeated alternation never leaves a stale token marked current', () {
      final LatestOnlyGuard guard = LatestOnlyGuard();
      final List<int> tokens = <int>[for (int i = 0; i < 5; i++) guard.start()];

      for (int i = 0; i < tokens.length - 1; i++) {
        expect(guard.isCurrent(tokens[i]), isFalse);
      }
      expect(guard.isCurrent(tokens.last), isTrue);
    });
  });
}
