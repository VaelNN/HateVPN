import '../services/l10n/locale_controller.dart';
import 'platform_channels.dart';
import 'version_info.dart';








class ProjectLinks {
  ProjectLinks._();

  static const repo = 'https://github.com/Leadaxe/LxBox';
  static const latestRelease =
      'https://github.com/Leadaxe/LxBox/releases/latest';
  static const core = 'https://github.com/Leadaxe/sing-box-lx';
  static const launcher = 'https://github.com/Leadaxe/singbox-launcher';
  static const singboxUpstream = 'https://github.com/SagerNet/sing-box';
  static const telegram = 'https://t.me/singbox_launcher/4317';
  static const donate = 'https://t.me/singbox_launcher/340/3621';
  static const issues = 'https://github.com/Leadaxe/LxBox/issues';
  static const donatePage =
      'https://github.com/Leadaxe/LxBox/blob/main/docs/DONATE.md';
  static const donatePageRu =
      'https://github.com/Leadaxe/LxBox/blob/main/docs/DONATE.ru.md';


  static String donatePageFor(String tag) =>
      tag == 'ru' ? donatePageRu : donatePage;
  static const automationDoc =
      'https://github.com/Leadaxe/LxBox/blob/main/docs/AUTOMATION.md';





  static const guideEn =
      'https://github.com/Leadaxe/LxBox/blob/main/docs/USER_GUIDE.md';
  static const guideRu =
      'https://github.com/Leadaxe/LxBox/blob/main/docs/USER_GUIDE.ru.md';

  static String guideFor(String tag) => tag == 'ru' ? guideRu : guideEn;

  static String releaseTag(String tag) =>
      'https://github.com/Leadaxe/LxBox/releases/tag/$tag';







  static const playPage =
      'market://details?id=${PlatformChannels.packageName}';
  static const playPageWeb =
      'https://play.google.com/store/apps/details?id=${PlatformChannels.packageName}';
  static const fdroidPage =
      'https://f-droid.org/packages/${PlatformChannels.packageName}/';



  static Map<String, String> placeholders() => {
        '@selfLink': latestRelease,
        '@repoLink': repo,
        '@coreLink': core,
        '@launcherLink': launcher,
        '@tgLink': telegram,
        '@donateLink': donate,
        '@issuesLink': issues,
        '@donatePage': donatePageFor(LocaleController.I.effectiveTag),
        '@guideLink': guideFor(LocaleController.I.effectiveTag),
        '@appVersion': VersionInfo.I.version,
      };





  static String expand(String raw) {
    if (!raw.contains('@')) return raw;
    final map = placeholders();
    final keys = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var out = raw;
    for (final k in keys) {
      if (out.contains(k)) out = out.replaceAll(k, map[k]!);
    }
    return out;
  }
}
