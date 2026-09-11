import 'dart:typed_data';

/// Reads the EXIF orientation tag (0x0112) straight from the encoded bytes.
///
/// Why not `img.bakeOrientation`/`image.exif`: as of `image` 4.9.2 the decoders do **not**
/// populate EXIF metadata at all — `decodeJpg(...).exif.imageIfd.orientation` is null even for a
/// JPEG that carries the tag, and `bakeOrientation` therefore never rotates anything. On top of
/// that, the package's orientation-6 branch rotates the stored pixels the wrong way relative to
/// the EXIF specification (Pillow's `ImageOps.exif_transpose` is the reference used here).
///
/// This reader handles the two containers the app can receive from a picker or camera:
/// JPEG (an APP1 segment starting with `Exif\0\0`) and PNG (an `eXIf` chunk). Both wrap a TIFF
/// header, which is what this parses. Returns null when there is no orientation tag.
int? readExifOrientation(Uint8List bytes) {
  final Uint8List? tiff = _extractTiff(bytes);
  if (tiff == null) {
    return null;
  }
  return _orientationFromTiff(tiff);
}

Uint8List? _extractTiff(Uint8List bytes) {
  // PNG: 8-byte signature, then length/type/data/crc chunks.
  const List<int> pngSignature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length > 8 && _matches(bytes, 0, pngSignature)) {
    int offset = 8;
    while (offset + 8 <= bytes.length) {
      final int length = _u32(bytes, offset);
      final String type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final int dataStart = offset + 8;
      if (dataStart + length > bytes.length) {
        return null;
      }
      if (type == 'eXIf') {
        return Uint8List.sublistView(bytes, dataStart, dataStart + length);
      }
      offset = dataStart + length + 4; // skip CRC
      if (type == 'IEND') {
        return null;
      }
    }
    return null;
  }

  // JPEG: 0xFFD8, then marker segments. APP1 (0xFFE1) may hold "Exif\0\0" + TIFF header.
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  int offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final int marker = bytes[offset + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) {
      return null; // start of scan / end of image: no EXIF found
    }
    final int segmentLength = _u16(bytes, offset + 2);
    final int dataStart = offset + 4;
    if (segmentLength < 2 || dataStart + segmentLength - 2 > bytes.length) {
      return null;
    }
    if (marker == 0xE1 &&
        segmentLength >= 8 &&
        _matches(bytes, dataStart, <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00])) {
      return Uint8List.sublistView(
          bytes, dataStart + 6, dataStart + segmentLength - 2);
    }
    offset = dataStart + segmentLength - 2;
  }
  return null;
}

int? _orientationFromTiff(Uint8List tiff) {
  if (tiff.length < 8) {
    return null;
  }
  final bool littleEndian = tiff[0] == 0x49 && tiff[1] == 0x49;
  final bool bigEndian = tiff[0] == 0x4D && tiff[1] == 0x4D;
  if (!littleEndian && !bigEndian) {
    return null;
  }
  if (_u16(tiff, 2, littleEndian) != 0x2A) {
    return null;
  }
  final int ifdOffset = _u32(tiff, 4, littleEndian);
  if (ifdOffset + 2 > tiff.length) {
    return null;
  }
  final int entryCount = _u16(tiff, ifdOffset, littleEndian);
  for (int i = 0; i < entryCount; i++) {
    final int entry = ifdOffset + 2 + i * 12;
    if (entry + 12 > tiff.length) {
      return null;
    }
    if (_u16(tiff, entry, littleEndian) == 0x0112) {
      return _u16(tiff, entry + 8, littleEndian);
    }
  }
  return null;
}

bool _matches(Uint8List bytes, int offset, List<int> pattern) {
  if (offset + pattern.length > bytes.length) {
    return false;
  }
  for (int i = 0; i < pattern.length; i++) {
    if (bytes[offset + i] != pattern[i]) {
      return false;
    }
  }
  return true;
}

int _u16(Uint8List bytes, int offset, [bool littleEndian = false]) {
  if (offset + 2 > bytes.length) {
    return 0;
  }
  return littleEndian
      ? bytes[offset] | (bytes[offset + 1] << 8)
      : (bytes[offset] << 8) | bytes[offset + 1];
}

int _u32(Uint8List bytes, int offset, [bool littleEndian = false]) {
  if (offset + 4 > bytes.length) {
    return 0;
  }
  return littleEndian
      ? bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24)
      : (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
}

/// Reads the stored frame dimensions from a JPEG's SOF marker.
///
/// Used to tell whether a decoder transposed the pixels while applying EXIF orientation: the frame
/// header keeps the dimensions as stored, so a decoded image whose width/height are swapped relative
/// to it has already been oriented by the decoder.
(int, int)? readJpegStoredDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  int offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final int marker = bytes[offset + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    if (marker == 0xDA || marker == 0xD9) {
      return null;
    }
    final int segmentLength = _u16(bytes, offset + 2);
    final int dataStart = offset + 4;
    if (segmentLength < 2 || dataStart + segmentLength - 2 > bytes.length) {
      return null;
    }
    // SOF0..SOF15 except DHT (0xC4), JPG (0xC8) and DAC (0xCC) carry the frame dimensions.
    final bool isSof = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof && dataStart + 5 <= bytes.length) {
      final int height = _u16(bytes, dataStart + 1);
      final int width = _u16(bytes, dataStart + 3);
      return (width, height);
    }
    offset = dataStart + segmentLength - 2;
  }
  return null;
}
