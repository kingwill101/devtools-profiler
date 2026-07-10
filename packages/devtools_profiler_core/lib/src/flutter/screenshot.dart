import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:vm_service/vm_service.dart';

/// Captures screenshots of running Flutter applications via VM service
/// extension.
class ScreenshotCaptureService {
  /// Creates a screenshot capture service.
  ScreenshotCaptureService({required VmService vmService})
    : _vmService = vmService;

  final VmService _vmService;

  /// Captures a screenshot of the entire Flutter app from [isolateId].
  ///
  /// [width] and [height] control the output dimensions. [maxPixelRatio]
  /// caps the pixel ratio (default 3.0). Returns raw PNG bytes.
  Future<Uint8List> captureScreenshot({
    required String isolateId,
    double width = 800,
    double height = 600,
    double maxPixelRatio = 3.0,
    double margin = 0.0,
  }) async {
    // First inspect the root widget to get the render object ID
    final rootResponse = await _vmService.callServiceExtension(
      'ext.flutter.inspector.getRootWidgetSummaryTree',
      isolateId: isolateId,
      args: {'objectGroup': 'screenshot'},
    );

    final rootJson = rootResponse.json?['result'] as Map<String, Object?>?;
    final rootId = rootJson?['objectId'] as String?;

    if (rootId == null) {
      throw StateError(
        'Could not resolve root widget ID for screenshot.',
      );
    }

    final response = await _vmService.callServiceExtension(
      'ext.flutter.inspector.screenshot',
      isolateId: isolateId,
      args: {
        'id': rootId,
        'width': width.toStringAsFixed(0),
        'height': height.toStringAsFixed(0),
        'maxPixelRatio': maxPixelRatio.toStringAsFixed(1),
        'margin': margin.toStringAsFixed(0),
      },
    );

    final imageData = response.json?['result'] as String? ??
        response.json?['screenshot'] as String?;

    if (imageData == null || imageData.isEmpty) {
      throw StateError('Screenshot returned empty image data.');
    }

    return base64.decode(imageData);
  }

  /// Captures a screenshot and writes it to [outputPath].
  Future<File> captureScreenshotToFile({
    required String isolateId,
    required String outputPath,
    double width = 800,
    double height = 600,
    double maxPixelRatio = 3.0,
  }) async {
    final bytes = await captureScreenshot(
      isolateId: isolateId,
      width: width,
      height: height,
      maxPixelRatio: maxPixelRatio,
    );
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
    return file;
  }
}
