import 'dart:math';

/// Names bots are drawn from, in English and Nepali (same order).
const _en = [
  'Aarav',
  'Sita',
  'Pemba',
  'Hari',
  'Gita',
  'Bikash',
  'Sarita',
  'Dawa',
  'Kiran',
  'Laxmi',
  'Nabin',
  'Puja',
  'Ramesh',
  'Anita',
  'Tenzing',
  'Sunita',
  'Bishal',
  'Asmita',
  'Prakash',
  'Kamala',
  'Suman',
  'Nima',
  'Rojina',
  'Dipesh',
];

const _ne = [
  'आरव',
  'सीता',
  'पेम्बा',
  'हरि',
  'गीता',
  'विकास',
  'सरिता',
  'दावा',
  'किरण',
  'लक्ष्मी',
  'नविन',
  'पूजा',
  'रमेश',
  'अनिता',
  'तेन्जिङ',
  'सुनिता',
  'विशाल',
  'अस्मिता',
  'प्रकाश',
  'कमला',
  'सुमन',
  'निमा',
  'रोजिना',
  'दिपेश',
];

/// [count] different bot names picked at random, in Nepali when
/// [languageCode] is 'ne'.
List<String> randomBotNames(int count, {String? languageCode, Random? random}) {
  final pool = languageCode == 'ne' ? _ne : _en;
  return (List.of(pool)..shuffle(random ?? Random())).take(count).toList();
}
