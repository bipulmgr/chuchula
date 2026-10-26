import 'package:flutter/widgets.dart';

import '../../bots/bot_strategy.dart';
import '../../game/models/moves.dart';
import '../../game/rules/bonuses.dart';
import '../../game/rules/hand_evaluator.dart';
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

  String bonus(BonusType b) => switch (b) {
    BonusType.fourOfAKind => bonusFourOfAKind,
    BonusType.sixPairs => bonusSixPairs,
    BonusType.threeTrails => bonusThreeTrails,
    BonusType.allRanks => bonusAllRanks,
  };

  String ruleError(RuleError e) => switch (e) {
    RuleError.notYourTurn => errNotYourTurn,
    RuleError.notAscending => errNotAscending,
    RuleError.wrongGroupCount ||
    RuleError.wrongGroupSize ||
    RuleError.duplicateCard ||
    RuleError.cardNotOwned ||
    RuleError.missingCards => errInvalidArrangement,
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

  List<String> get botNames => [botName1, botName2, botName3];
}
