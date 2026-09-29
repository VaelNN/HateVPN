import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/screens/about_screen.dart';






void main() {
  group('About → user guide link', () {
    test('ru → русский гайд, en → английский', () {
      expect(AboutScreen.guideUrlFor('ru'), AboutScreen.guideUrlRu);
      expect(AboutScreen.guideUrlFor('en'), AboutScreen.guideUrlEn);
      expect(AboutScreen.guideUrlRu, isNot(AboutScreen.guideUrlEn));
    });

    test('незнакомый язык → английский (fallback, не 404)', () {



      for (final tag in ['de', 'fa', 'zh', '']) {
        expect(AboutScreen.guideUrlFor(tag), AboutScreen.guideUrlEn,
            reason: 'тег "$tag" должен падать в английскую версию');
      }
    });

    test('оба URL смотрят на main и на разные файлы репозитория', () {
      for (final url in [AboutScreen.guideUrlEn, AboutScreen.guideUrlRu]) {


        expect(url, startsWith('https://github.com/Leadaxe/LxBox/blob/main/'),
            reason: 'ссылка должна вести в main: $url');
        expect(url, endsWith('.md'));
      }
      expect(AboutScreen.guideUrlEn, contains('docs/USER_GUIDE.md'));
      expect(AboutScreen.guideUrlRu, contains('docs/USER_GUIDE.ru.md'));
    });
  });
}
