import 'package:chuchula/ads/rewarded_ads.dart';
import 'package:chuchula/app/providers.dart';
import 'package:chuchula/game/models/game_state.dart';
import 'package:chuchula/game/scoring/cash_points.dart';
import 'package:chuchula/persistence/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchResult _result(int winner, List<int> scores) => MatchResult(
  winnerSeat: winner,
  reason: MatchEndReason.targetReached,
  finalScores: scores,
);

class _Ads implements RewardedAds {
  _Ads(this.earn);
  final bool earn;
  @override
  bool get supported => true;
  @override
  Future<bool> show() async => earn;
}

Future<ProviderContainer> _container({
  Map<String, Object> prefs = const {},
  bool earn = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = await LocalStore.open();
  final c = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      rewardedAdsProvider.overrideWithValue(_Ads(earn)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('settlement', () {
    test('2nd pays 20, 3rd pays 30, last pays 50 to the winner', () {
      final r = _result(2, [12, 5, 21, 9]);
      expect(CashPoints.places(r), [2, 4, 1, 3]);
      expect(CashPoints.settle(r), [-20, -50, 100, -30]);
    });

    test('an instant win comes first even with fewer points', () {
      final r = _result(3, [15, 10, 5, 2]);
      expect(CashPoints.settle(r), [-20, -30, -50, 100]);
    });

    test('tied players split the places they span', () {
      // Tied for 2nd and 3rd: (20 + 30) / 2 each.
      expect(CashPoints.settle(_result(0, [20, 8, 8, 3])), [
        100,
        -25,
        -25,
        -50,
      ]);
      // Tied for 3rd and last: (30 + 50) / 2 each.
      expect(CashPoints.settle(_result(0, [20, 9, 4, 4])), [
        100,
        -20,
        -40,
        -40,
      ]);
      // All three tied: 100 / 3 rounded down; the winner gets what is paid.
      expect(CashPoints.settle(_result(1, [6, 20, 6, 6])), [-33, 99, -33, -33]);
    });

    test('payments always add up to what the winner gains', () {
      for (final scores in [
        [20, 0, 0, 0],
        [3, 20, 19, 18],
        [21, 21, 5, 5],
      ]) {
        final d = CashPoints.settle(_result(0, scores));
        expect(d.reduce((a, b) => a + b), 0);
        expect(d[0], greaterThan(0));
      }
    });
  });

  group('wallet', () {
    test('starts at 100 and is saved', () async {
      final c = await _container();
      expect(c.read(walletProvider).balance, CashPoints.startingBalance);
      expect(c.read(walletProvider.notifier).canPlay, isTrue);
      c.read(walletProvider.notifier).settle('m1', -30);
      expect(c.read(walletProvider).balance, 70);
      expect(c.read(localStoreProvider).loadWallet().balance, 70);
    });

    test('a match is settled only once', () async {
      final c = await _container();
      final w = c.read(walletProvider.notifier);
      w.settle('m1', 100);
      w.settle('m1', 100);
      expect(c.read(walletProvider).balance, 200);
    });

    test('a watched ad adds 50; an unfinished one adds nothing', () async {
      final c = await _container(prefs: {'wallet.v1': '{"balance":20}'});
      expect(c.read(walletProvider.notifier).canPlay, isFalse);
      expect(await c.read(walletProvider.notifier).watchAd(), isTrue);
      expect(c.read(walletProvider).balance, 70);
      expect(c.read(walletProvider.notifier).canPlay, isTrue);

      final none = await _container(
        prefs: {'wallet.v1': '{"balance":20}'},
        earn: false,
      );
      expect(await none.read(walletProvider.notifier).watchAd(), isFalse);
      expect(none.read(walletProvider).balance, 20);
    });

    test('a corrupt save falls back to a fresh wallet', () async {
      final c = await _container(prefs: {'wallet.v1': 'not json'});
      expect(c.read(walletProvider).balance, 100);
    });
  });
}
