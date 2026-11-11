import 'package:flutter/widgets.dart';

import '../../bots/bot_strategy.dart';
import '../../game/models/bot_names.dart';
import '../../game/models/moves.dart';
import '../../game/rules/bonuses.dart';
import '../../game/rules/hand_evaluator.dart';
import '../../persistence/settings_repository.dart';
import '../theme/table_themes.dart';
import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension L10nNames on AppLocalizations {
  String category(HandCategory c) => switch (c) {
    HandCategory.highCard => catHighCard,
    HandCategory.pair => catPair,
    HandCategory.twoPair => catTwoPair,
    HandCategory.color => catColor,
    HandCategory.sequence => catSequence,
    HandCategory.trail => catTrail,
    HandCategory.pureSequence => catPureSequence,
    HandCategory.fourOfAKind => catFourOfAKind,
  };

  /// Name of an evaluated group, e.g. "Color" or "4-card Color".
  String handName(HandValue v) =>
      v.fourCard &&
          v.category != HandCategory.twoPair &&
          v.category != HandCategory.fourOfAKind
      ? catFourCard(category(v.category))
      : category(v.category);

  String bonus(BonusType b) => switch (b) {
    BonusType.fourOfAKind => bonusFourOfAKind,
    BonusType.sixPairs => bonusSixPairs,
    BonusType.threeTrails => bonusThreeTrails,
    BonusType.allRanks => bonusAllRanks,
  };

  String ruleError(RuleError e) => switch (e) {
    RuleError.notYourTurn => errNotYourTurn,
    RuleError.wrongGroupCount ||
    RuleError.wrongGroupSize ||
    RuleError.duplicateCard ||
    RuleError.cardNotOwned ||
    RuleError.missingCards => errInvalidArrangement,
    RuleError.fourCardTooStrong => errFourCardTooStrong,
    RuleError.alreadyAnswered => errAlreadyAnswered,
    _ => errGeneric,
  };

  String difficultyName(BotDifficulty d) => switch (d) {
    BotDifficulty.easy => easy,
    BotDifficulty.medium => medium,
    BotDifficulty.hard => hard,
  };

  String difficultyDesc(BotDifficulty d) => switch (d) {
    BotDifficulty.easy => easyDesc,
    BotDifficulty.medium => mediumDesc,
    BotDifficulty.hard => hardDesc,
  };

  String trackName(MusicTrack t) => switch (t) {
    MusicTrack.himalaya => trackHimalaya,
    MusicTrack.festival => trackFestival,
    MusicTrack.calm => trackCalm,
  };

  String soundSetName(SoundSet s) => switch (s) {
    SoundSet.classic => soundClassic,
    SoundSet.soft => soundSoft,
    SoundSet.arcade => soundArcade,
  };

  String themeName(TableThemeId t) => switch (t) {
    TableThemeId.emerald => themeEmerald,
    TableThemeId.dashain => themeDashain,
    TableThemeId.tihar => themeTihar,
    TableThemeId.himalaya => themeHimalaya,
  };

  String cardBackName(CardBackId b) => switch (b) {
    CardBackId.dhaka => backDhaka,
    CardBackId.mandala => backMandala,
    CardBackId.lotus => backLotus,
    CardBackId.classic => backClassic,
  };

  /// Three different bot names, picked at random each time.
  List<String> get botNames =>
      randomBotNames(3, languageCode: localeName.split('_').first);
}
