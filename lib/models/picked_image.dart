/// Immutable value object describing an image the user selected on the device.
///
/// Iteration 0 deliberately keeps only what the preview needs. Decoded pixel
/// bytes are NOT held here, so the widget tree never owns a large buffer.
class PickedImage {
  const PickedImage({
    required this.path,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  /// Absolute path of the file inside the app's own cache/storage.
  final String path;

  /// File size in bytes, read from disk at pick time.
  final int sizeBytes;

  /// Decoded pixel width, or null when the file could not be decoded.
  final int? width;

  /// Decoded pixel height, or null when the file could not be decoded.
  final int? height;

  bool get hasDimensions => width != null && height != null;

  /// Human readable file size, e.g. `128.4 KB`.
  String get readableSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    final double kb = sizeBytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  /// Human readable pixel size, or a clear hint that decoding failed.
  String get readableDimensions =>
      hasDimensions ? '$width x $height px' : 'dimensions unavailable';

  @override
  String toString() =>
      'PickedImage(path: $path, sizeBytes: $sizeBytes, '
      'width: $width, height: $height)';
}
