// TARGET: Flutter 3.22+ | tflite_flutter ^0.10.4
// JARVIS MODULE: On-Device ML File Classification (MobileNetV2)

import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'drag_overlay.dart';

class ClassificationResult {
  final DragPayloadType type;
  final String label;
  final double confidence;

  const ClassificationResult({
    required this.type,
    required this.label,
    required this.confidence,
  });
}

class AIClassifier {
  Interpreter? _interpreter;
  static const String _modelPath = 'assets/models/mobilenet_v2.tflite';

  static const Map<String, DragPayloadType> _extensionMap = {
    '.jpg': DragPayloadType.image,
    '.jpeg': DragPayloadType.image,
    '.png': DragPayloadType.image,
    '.heic': DragPayloadType.image,
    '.mp4': DragPayloadType.video,
    '.mov': DragPayloadType.video,
    '.mkv': DragPayloadType.video,
    '.dart': DragPayloadType.code,
    '.js': DragPayloadType.code,
    '.py': DragPayloadType.code,
    '.ts': DragPayloadType.code,
    '.java': DragPayloadType.code,
  };

  Future<void> _loadModel() async {
    _interpreter ??= await Interpreter.fromAsset(_modelPath);
  }

  // ── CLASSIFY FILE ──────────────────────────────────────────────────────────
  Future<ClassificationResult> classify(String filePath) async {
    final extension = filePath
        .substring(filePath.lastIndexOf('.'))
        .toLowerCase();

    // Fast path: extension-based
    if (_extensionMap.containsKey(extension)) {
      final type = _extensionMap[extension]!;

      // Deep classify images using TFLite
      if (type == DragPayloadType.image) {
        return await _classifyImage(filePath);
      }

      return ClassificationResult(
        type: type,
        label: type.name,
        confidence: 1.0,
      );
    }

    return const ClassificationResult(
      type: DragPayloadType.file,
      label: 'generic_file',
      confidence: 1.0,
    );
  }

  // ── IMAGE CLASSIFICATION (MobileNetV2 224x224) ────────────────────────────
  Future<ClassificationResult> _classifyImage(String imagePath) async {
    try {
      await _loadModel();

      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      var image = img.decodeImage(imageBytes);
      if (image == null) return _defaultImageResult();

      image = img.copyResize(image, width: 224, height: 224);

      // Normalize to [0, 1]
      final input = List.generate(
        1,
        (_) => List.generate(
          224,
          (y) => List.generate(
            224,
            (x) {
              final pixel = image!.getPixel(x, y);
              return [
                img.getRed(pixel) / 255.0,
                img.getGreen(pixel) / 255.0,
                img.getBlue(pixel) / 255.0,
              ];
            },
          ),
        ),
      );

      final output = List.filled(1001, 0.0).reshape([1, 1001]);
      _interpreter!.run(input, output);

      final scores = output[0] as List<double>;
      final maxScore = scores.reduce((a, b) => a > b ? a : b);
      final maxIdx = scores.indexOf(maxScore);

      // Agrotech hook: indices 949-999 → plant/crop domain
      final label = maxIdx >= 949
          ? 'plant_disease_candidate'
          : 'classified_image_$maxIdx';

      debugPrint('[JARVIS-AI] Image classified: $label (${(maxScore * 100).toStringAsFixed(1)}%)');

      return ClassificationResult(
        type: DragPayloadType.image,
        label: label,
        confidence: maxScore,
      );
    } catch (e) {
      debugPrint('[JARVIS-AI] Classification error: $e');
      return _defaultImageResult();
    }
  }

  ClassificationResult _defaultImageResult() => const ClassificationResult(
        type: DragPayloadType.image,
        label: 'image',
        confidence: 0.9,
      );

  void dispose() => _interpreter?.close();
}