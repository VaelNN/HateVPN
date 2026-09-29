import 'package:flutter/material.dart';

import '../models/ui_msg.dart';
import '../services/l10n/locale_controller.dart';
import 'app_bottom_sheet.dart';


enum ExportAction {

  saveToFile,


  saveToDownloads,


  share,
}












Future<ExportAction?> showExportActionSheet(
  BuildContext context, {
  required bool canSaveToFile,
  required bool canSaveToDownloads,
}) {
  return showAppBottomSheet<ExportAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSaveToFile)
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text(getLocalText.s("Save to file")),
              subtitle: Text(getLocalText.s("Pick a folder on this device")),
              onTap: () => Navigator.pop(ctx, ExportAction.saveToFile),
            ),
          if (canSaveToDownloads)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(getLocalText.s("Save to Downloads")),
              subtitle: Text(getLocalText.s("Straight to the Downloads folder")),
              onTap: () => Navigator.pop(ctx, ExportAction.saveToDownloads),
            ),


          if (!canSaveToFile && !canSaveToDownloads)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                const ErrMsg(ErrKey.noFileManager).render(),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(getLocalText.s("Share")),
            subtitle: Text(getLocalText.s("Send to another app")),
            onTap: () => Navigator.pop(ctx, ExportAction.share),
          ),
        ],
      ),
    ),
  );
}
