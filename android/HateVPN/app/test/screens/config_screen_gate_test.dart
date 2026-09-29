import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/screens/config_screen.dart';

void main() {

  test('configTooLargeToEdit boundary', () {
    expect(configTooLargeToEdit(''), isFalse);
    expect(configTooLargeToEdit('x' * kConfigEditMaxChars), isFalse);
    expect(configTooLargeToEdit('x' * (kConfigEditMaxChars + 1)), isTrue);
  });
}
