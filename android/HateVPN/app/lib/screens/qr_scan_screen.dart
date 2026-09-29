













import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../services/app_log.dart';
import '../services/error_format.dart';
import '../services/l10n/locale_controller.dart';


sealed class ScanOutcome {
  const ScanOutcome();
}



class ScannedCode extends ScanOutcome {
  const ScannedCode(this.value);

  final String value;
}


class ScanCancelled extends ScanOutcome {
  const ScanCancelled();
}


class ScanDenied extends ScanOutcome {
  const ScanDenied();
}


class ScanFailed extends ScanOutcome {
  const ScanFailed(this.error);

  final Object error;
}





String? scanProblemText(ScanOutcome outcome) => switch (outcome) {
  ScannedCode() || ScanCancelled() => null,
  ScanDenied() => getLocalText.s("Camera access denied"),
  ScanFailed(:final error) => getLocalText.s(
    "Camera error: %s",
    formatUserError(error).render(),
  ),
};






class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}






bool _isPermissionDenied(String code) =>
    code == 'CameraAccessDenied' ||
    code == 'CameraAccessDeniedWithoutPrompt' ||
    code == 'CameraAccessRestricted';

class _QrScanScreenState extends State<QrScanScreen> {


  bool _handled = false;

  void _finish(ScanOutcome outcome) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(outcome);
  }




  int _attempts = 0;

  void _onScan(Code code) {
    if (_handled) return;
    final value = code.text?.trim();
    if (value == null || value.isEmpty) return;
    AppLog.I.info('[qr] scanned ${value.length} chars');
    _finish(ScannedCode(value));
  }

  void _onScanFailure(Code code) {
    if (_handled || !mounted) return;
    setState(() => _attempts++);
  }



  void _onControllerCreated(CameraController? controller, Exception? error) {
    if (error == null || _handled) return;
    final code = error is CameraException ? error.code : null;
    AppLog.I.warning('[qr] scanner error: ${code ?? error}');
    _finish(
      code != null && _isPermissionDenied(code)
          ? const ScanDenied()
          : ScanFailed(error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(getLocalText.s("Scan QR code"))),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ReaderWidget(
            onScan: _onScan,
            onScanFailure: _onScanFailure,
            onControllerCreated: _onControllerCreated,


            codeFormat: Format.qrCode,



            showGallery: false,
            showToggleCamera: false,




            cropPercent: 0.9,




            tryHarder: true,


            tryDownscale: true,


            tryInverted: false,





            scanDelay: const Duration(milliseconds: 300),


            scanDelaySuccess: const Duration(milliseconds: 300),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [


                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _attempts.isEven ? Colors.white : Colors.white24,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        getLocalText.s("Point the camera at a QR code"),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
