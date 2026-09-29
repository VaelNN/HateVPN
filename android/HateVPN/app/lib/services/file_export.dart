


















import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/ui_msg.dart';
import 'app_log.dart';
import 'error_format.dart';
import 'l10n/locale_controller.dart';
import 'url_launcher.dart';




const _noPickerCode = 'explorer_not_found';


sealed class SaveOutcome {
  const SaveOutcome();
}




class SavedToFile extends SaveOutcome {
  const SavedToFile(this.name);

  final String name;
}



class SavedToDownloads extends SaveOutcome {
  const SavedToDownloads(this.name);

  final String name;
}


class SaveCancelled extends SaveOutcome {
  const SaveCancelled();
}


class SaveNoTarget extends SaveOutcome {
  const SaveNoTarget();
}


class SaveFailed extends SaveOutcome {
  const SaveFailed(this.error);

  final Object error;
}






Future<SaveOutcome> saveFileSafely({
  required String fileName,
  required String content,
}) async {
  if (!await UrlLauncher.hasRealFilePicker()) {
    AppLog.I.warning('[save] no real file manager (TV stub only)');
    return const SaveNoTarget();
  }
  try {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: utf8.encode(content),
    );
    if (uri == null) return const SaveCancelled();
    return SavedToFile(fileName);
  } on PlatformException catch (e) {
    if (e.code == _noPickerCode) {
      AppLog.I.warning('[save] no file manager on device (${e.code})');
      return const SaveNoTarget();
    }
    AppLog.I.warning('[save] platform error: $e');
    return SaveFailed(e);
  } catch (e) {
    AppLog.I.warning('[save] failed: $e');
    return SaveFailed(e);
  }
}


Future<SaveOutcome> saveToDownloadsSafely({
  required String fileName,
  required String content,
}) async {
  try {
    final saved = await UrlLauncher.saveToDownloads(
      fileName: fileName,
      content: content,
    );
    if (saved == null) {
      AppLog.I.warning('[save] MediaStore write returned null');
      return const SaveNoTarget();
    }
    return SavedToDownloads(saved);
  } catch (e) {
    AppLog.I.warning('[save] downloads failed: $e');
    return SaveFailed(e);
  }
}






String? saveProblemText(SaveOutcome outcome) => switch (outcome) {
      SavedToFile() || SavedToDownloads() || SaveCancelled() => null,
      SaveNoTarget() => const ErrMsg(ErrKey.noFileManager).render(),
      SaveFailed(:final error) =>
        getLocalText.s("Export failed: %s", formatUserError(error).render()),
    };
