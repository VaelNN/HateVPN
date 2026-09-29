















import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../models/ui_msg.dart';
import 'app_log.dart';
import 'error_format.dart';
import 'l10n/locale_controller.dart';
import 'url_launcher.dart';





const _noPickerCode = 'explorer_not_found';







class PickedFile {
  const PickedFile({required this.name, required this.bytes});


  final String name;

  final Uint8List bytes;



  String get text => utf8.decode(bytes, allowMalformed: true);
}


sealed class PickOutcome {
  const PickOutcome();
}


class PickedFiles extends PickOutcome {
  const PickedFiles(this.files);

  final List<PickedFile> files;

  PickedFile get single => files.single;
}


class PickCancelled extends PickOutcome {
  const PickCancelled();
}



class PickNoPicker extends PickOutcome {
  const PickNoPicker();
}



class PickFailed extends PickOutcome {
  const PickFailed(this.error);

  final Object error;
}






Future<PickOutcome> pickFileSafely({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
}) async {











  final action = await UrlLauncher.filePickerAction();
  if (action == null) {
    AppLog.I.warning('[pick] no real file manager (TV stub only)');
    return const PickNoPicker();
  }
  if (action == UrlLauncher.actionGetContent) {


    return _pickViaGetContent(
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
  }
  try {


    final picked = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,

      allowMultiple: allowMultiple,
    );
    if (picked.isEmpty) return const PickCancelled();
    final files = <PickedFile>[];
    for (final f in picked) {
      files.add(PickedFile(name: f.name, bytes: await f.readAsBytes()));
    }
    return PickedFiles(files);
  } on PlatformException catch (e) {
    if (e.code == _noPickerCode) {
      AppLog.I.warning('[pick] no file manager on device (${e.code})');
      return const PickNoPicker();
    }
    AppLog.I.warning('[pick] platform error: $e');
    return PickFailed(e);
  } catch (e) {
    AppLog.I.warning('[pick] failed: $e');
    return PickFailed(e);
  }
}












Future<PickOutcome> _pickViaGetContent({
  List<String>? allowedExtensions,
  bool allowMultiple = false,
}) async {
  try {
    final picked =
        await UrlLauncher.pickFilesViaGetContent(allowMultiple: allowMultiple);
    if (picked == null || picked.isEmpty) return const PickCancelled();
    final files = <PickedFile>[];
    for (final item in picked) {
      final name = item['name'] as String? ?? 'config';
      final bytes = item['bytes'] as Uint8List?;
      if (bytes == null) {
        AppLog.I.warning('[pick] GET_CONTENT returned no bytes for $name');
        continue;
      }
      if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final allowed =
            allowedExtensions.map((e) => e.toLowerCase().replaceAll('.', ''));
        if (!allowed.contains(ext)) {
          AppLog.I.warning('[pick] GET_CONTENT: extension "$ext" not allowed');
          continue;
        }
      }
      files.add(PickedFile(name: name, bytes: bytes));
    }
    if (files.isEmpty) {


      final hint = allowedExtensions != null && allowedExtensions.isNotEmpty
          ? getLocalText.s('Select a %s file', allowedExtensions.join(', '))
          : getLocalText.s('Cannot read the selected file');
      return PickFailed(Exception(hint));
    }
    AppLog.I.info('[pick] GET_CONTENT ok: ${files.length} file(s)');
    return PickedFiles(files);
  } on PlatformException catch (e) {
    AppLog.I.warning('[pick] GET_CONTENT platform error: $e');
    return PickFailed(e);
  } catch (e) {
    AppLog.I.warning('[pick] GET_CONTENT failed: $e');
    return PickFailed(e);
  }
}





String get noFileManagerHint => const ErrMsg(ErrKey.noFileManager).render();






String? pickProblemText(PickOutcome outcome) => switch (outcome) {
      PickedFiles() || PickCancelled() => null,
      PickNoPicker() => noFileManagerHint,
      PickFailed(:final error) =>
        getLocalText.s("Error: %s", formatUserError(error).render()),
    };
