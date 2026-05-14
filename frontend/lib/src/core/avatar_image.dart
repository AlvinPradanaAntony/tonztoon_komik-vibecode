import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class OptimizedAvatar {
  const OptimizedAvatar({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

class AvatarImagePicker {
  AvatarImagePicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  static const int _avatarSize = 512;
  static const int _targetBytes = 260 * 1024;

  final ImagePicker _picker;

  Future<OptimizedAvatar?> pick(
    BuildContext context,
    ImageSource source, {
    VoidCallback? onSelected,
  }) async {
    final uiSettings = _cropUiSettings(context);
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 88,
    );
    if (file == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      maxWidth: 1080,
      maxHeight: 1080,
      uiSettings: uiSettings,
    );
    if (cropped == null) return null;

    onSelected?.call();
    final bytes = await cropped.readAsBytes();
    final optimized = await compute(_optimizeAvatarBytes, bytes);
    return OptimizedAvatar(
      bytes: optimized,
      fileName: 'avatar.jpg',
      contentType: 'image/jpeg',
    );
  }

  List<PlatformUiSettings> _cropUiSettings(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      AndroidUiSettings(
        toolbarTitle: 'Sesuaikan foto',
        toolbarColor: colorScheme.surface,
        toolbarWidgetColor: colorScheme.onSurface,
        activeControlsWidgetColor: colorScheme.primary,
        backgroundColor: colorScheme.surface,
        dimmedLayerColor: Colors.black54,
        cropFrameColor: colorScheme.primary,
        initAspectRatio: CropAspectRatioPreset.square,
        lockAspectRatio: true,
        cropStyle: CropStyle.circle,
        hideBottomControls: false,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
      ),
      IOSUiSettings(
        title: 'Sesuaikan foto',
        doneButtonTitle: 'Pilih',
        cancelButtonTitle: 'Batal',
        cropStyle: CropStyle.circle,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
      ),
      WebUiSettings(
        context: context,
        presentStyle: WebPresentStyle.dialog,
        size: const CropperSize(width: 420, height: 420),
      ),
    ];
  }
}

Uint8List _optimizeAvatarBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Format gambar tidak didukung.');
  }

  final oriented = img.bakeOrientation(decoded);
  final square = img.copyResizeCropSquare(
    oriented,
    size: AvatarImagePicker._avatarSize,
    interpolation: img.Interpolation.average,
  );

  var working = square;
  var quality = 82;
  List<int> encoded = const [];
  while (true) {
    for (
      var currentQuality = quality;
      currentQuality >= 46;
      currentQuality -= 8
    ) {
      encoded = img.encodeJpg(working, quality: currentQuality);
      if (encoded.length <= AvatarImagePicker._targetBytes) {
        return Uint8List.fromList(encoded);
      }
    }

    if (working.width <= 320) return Uint8List.fromList(encoded);
    final nextSize = (working.width * 0.85)
        .round()
        .clamp(320, working.width)
        .toInt();
    working = img.copyResize(
      working,
      width: nextSize,
      height: nextSize,
      interpolation: img.Interpolation.average,
    );
    quality = 74;
  }
}
