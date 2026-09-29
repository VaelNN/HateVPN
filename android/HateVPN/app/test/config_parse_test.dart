import 'dart:convert';

import 'package:lxbox/config/config_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonicalJsonForSingbox accepts JSON5 comments', () {
    const input = '''
{
  // line comment
  "a": 1,
  "b": [2, 3,], /* block */
}
''';
    final out = canonicalJsonForSingbox(input);
    final map = jsonDecode(out) as Map<String, dynamic>;
    expect(map['a'], 1);
    expect(map['b'], [2, 3]);
  });



  test('canonicalJsonForSingbox normalizes json5 SyntaxException', () {
    expect(
      () => canonicalJsonForSingbox('{broken'),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('at 1:'))),
    );
  });


  test('canonicalJsonForSingboxAsync matches sync on valid input', () async {
    const input = '{"a": 1, /* c */ "b": [2,],}';
    expect(await canonicalJsonForSingboxAsync(input),
        canonicalJsonForSingbox(input));
  });

  test('canonicalJsonForSingboxAsync throws FormatException with message',
      () async {
    await expectLater(
      canonicalJsonForSingboxAsync('{broken'),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', isNotEmpty)),
    );
  });

  test('prettyJsonForDisplayAsync matches sync', () async {
    const input = '{"a":1}';
    expect(await prettyJsonForDisplayAsync(input),
        prettyJsonForDisplay(input));

    expect(await prettyJsonForDisplayAsync('{oops'), '{oops');
  });
}
