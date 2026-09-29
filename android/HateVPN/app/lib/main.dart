import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart' show initializeDateFormatting;
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/app_log.dart';
import 'services/l10n/locale_controller.dart';
import 'services/automation/automation_dispatcher.dart';
import 'services/automation/event_emitter.dart';
import 'services/clash_log_pump.dart';
import 'services/contract/registry.dart';
import 'services/parser/engine/section_loader.dart';
import 'services/parser/mappers/draft_sections.dart';
import 'services/crash_banner_state.dart';
import 'services/install_source.dart';
import 'services/oom_reports.dart';
import 'services/stderr_reader.dart';
import 'services/subscription/subscription_identity.dart';
import 'services/debug/bootstrap.dart' as debug_bootstrap;
import 'services/nav/home_return_observer.dart';
import 'services/settings_storage.dart';
import 'services/template_loader.dart';
import 'services/version_info.dart';
import 'services/workspaces/workspace_controller.dart';
import 'services/workspaces/workspace_store.dart';
import 'services/wifi_history_listener.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();












  final prevOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.I.error(
      'Flutter error: ${details.exceptionAsString()}'
      '${details.context != null ? " @ ${details.context}" : ""}',
    );
    if (kDebugMode) prevOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.I.error('Uncaught async: $error');
    return true;
  };
  ErrorWidget.builder = (details) => _FallbackErrorWidget(details: details);





  try {



    await VersionInfo.I.init();




    try {
      await ContractRegistry.I.load();
    } catch (e) {
      AppLog.I.warning('Contract registry not loaded: $e');
    }




    try {
      await MapperSections.I.loadDrafts(files: kDraftFiles);
    } catch (e) {
      AppLog.I.warning('Draft mapper sections not loaded: $e');
    }



    await InstallSourceResolver.init();





    await AppLog.I.initPersistent();







    final workspaceRecovered = await WorkspaceStore.I.recover();


    if (workspaceRecovered) SettingsStorage.markConfigDirty();



    await SubscriptionIdentity.init();




    await SettingsStorage.bootstrapAndSyncNativePrefs();





    await LocaleController.I.bootstrap(await SettingsStorage.getAppLanguage());
    WidgetsBinding.instance.addObserver(LocaleController.I);




    await initializeDateFormatting('ru');




    final directionsTemplate = await TemplateLoader.load();
    await SettingsStorage.migrateDirectionsIfNeeded(
      directionsTemplate.groupTemplates,

      varDefaults: {
        for (final v in directionsTemplate.vars) v.name: v.defaultValue,
      },
    );




    ClashLogPump.I.attach();



    unawaited(WifiHistoryListener.I.init());



    registerAutomationBridge();
    unawaited(AutomationEventEmitter.I.reload());




    unawaited(
      CrashReports.prune().then((removed) {
        if (removed > 0) AppLog.I.info('Pruned $removed old crash report(s)');
        return CrashBannerState.I.refresh();
      }),
    );





    unawaited(
      OomReports.prune().then((removed) {
        if (removed > 0) AppLog.I.info('Pruned $removed old OOM report(s)');
      }),
    );


    final _ = debug_bootstrap.appStartedAt;
  } catch (e, st) {
    AppLog.I.error('Startup init failed (continuing best-effort): $e\n$st');
  }



  await applyAllowRotationSetting();


  try {
    await SettingsStorage.getNodeListTwoColumns();
  } catch (_) {

  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF080A0C),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LxBoxApp());
}







Future<void> applyAllowRotationSetting() async {
  var allow = false;
  try {
    allow = await SettingsStorage.getAllowRotation();
  } catch (_) {

  }
  await SystemChrome.setPreferredOrientations(
    allow ? const <DeviceOrientation>[] : const [DeviceOrientation.portraitUp],
  );
}



class _FallbackErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _FallbackErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {


    return Container(
      color: const Color(0xFF2A1515),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 40),
          const SizedBox(height: 12),


          Text(
            getLocalText.s(
              "Something went wrong in this section.\nCheck Debug → Logs.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}


class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier() {
    _load();
  }

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  static const _key = 'app_theme_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}

final themeNotifier = ThemeNotifier();

class LxBoxApp extends StatelessWidget {
  const LxBoxApp({super.key});

  static const _seed = Color(0xFFCED5D9);

  @override
  Widget build(BuildContext context) {


    return AnimatedBuilder(
      animation: Listenable.merge([
        themeNotifier,
        LocaleController.I,
        WorkspaceController.I,
      ]),
      builder: (context, _) {



        return MaterialApp(
          title: 'HateVPN',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: _seed),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: _seed,
                  brightness: Brightness.dark,
                ).copyWith(
                  primary: const Color(0xFFEFF2F4),
                  onPrimary: const Color(0xFF161A1E),
                  surface: const Color(0xFF0B0D0F),
                  onSurface: const Color(0xFFF3F5F6),
                ),
            scaffoldBackgroundColor: const Color(0xFF080A0C),
            useMaterial3: true,
          ),
          themeMode: ThemeMode.dark,







          locale: LocaleController.I.effective,
          supportedLocales: LocaleController.supportedLocales,



          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],


          navigatorObservers: [homeReturnObserver],



          home: HomeScreen(key: ValueKey(WorkspaceController.I.generation)),
        );
      },
    );
  }
}
