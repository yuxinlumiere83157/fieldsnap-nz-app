@Tags(<String>['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fieldsnap/services/image_preprocessor.dart';
import 'package:fieldsnap/services/tflite_species_classifier.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';

/// Check 1 of 3: **preprocessing conformance** (image -> tensor).
///
/// Two kinds of evidence, because they catch different bugs:
///
///  * **Synthetic asymmetric fixtures** (`synthetic_orientation_*.jpg`) prove *pixel position
///    and channel order*. Overall statistics cannot: swapping R and B, or mirroring the image,
///    leaves min/max/mean/percentiles nearly unchanged, which is exactly how the earlier version
///    of this test could pass while being wrong. These assertions read named regions per channel.
///  * **A real photo** compared against the Python reference *per element*, with the residual
///    reported rather than assumed.
///
/// The EXIF case pins spec step 2: the orientation-6 file stores rotated pixels, so a
/// preprocessor that ignores EXIF, or flips, or swaps channels, fails.
void main() {
  const ImagePreprocessor preprocessor = ImagePreprocessor(size: 224);

  ModelInput fromFile(String path) =>
      preprocessor.fromImageBytes(File(path).readAsBytesSync());

  /// Mean per channel inside a region given in logical 224x224 coordinates.
  ({double r, double g, double b}) regionMean(
    Float32List tensor,
    List<int> xs,
    List<int> ys,
  ) {
    double r = 0, g = 0, b = 0;
    int n = 0;
    for (int y = ys[0]; y <= ys[1]; y++) {
      for (int x = xs[0]; x <= xs[1]; x++) {
        final int i = (y * 224 + x) * 3;
        r += tensor[i];
        g += tensor[i + 1];
        b += tensor[i + 2];
        n++;
      }
    }
    return (r: r / n, g: g / n, b: b / n);
  }

  group('synthetic fixtures prove channel order and pixel position', () {
    test('red, blue and green blocks land where the logical layout says', () {
      // Tensor values are in [-1, 1] (spec step 5), so a pure red pixel is about +0.80 in
      // channel 0 and -0.84 in the others. The thresholds below are those measured values.
      final ModelInput input = fromFile('test/fixtures/synthetic_orientation_1.png');
      final Float32List t = input.tensor;

      final ({double r, double g, double b}) red =
          regionMean(t, <int>[20, 60], <int>[20, 90]);
      final ({double r, double g, double b}) blue =
          regionMean(t, <int>[160, 210], <int>[130, 200]);
      final ({double r, double g, double b}) green =
          regionMean(t, <int>[10, 60], <int>[180, 215]);
      final ({double r, double g, double b}) grey =
          regionMean(t, <int>[170, 215], <int>[10, 60]);

      // Red block: channel 0 high, others low. An R/B swap fails this immediately.
      expect(red.r, greaterThan(0.6), reason: 'red block must be red in channel 0');
      expect(red.g, lessThan(-0.6));
      expect(red.b, lessThan(-0.6));

      // Blue block: channel 2 high. A channel swap or wrong colour conversion fails this.
      expect(blue.b, greaterThan(0.6), reason: 'blue block must be blue in channel 2');
      expect(blue.r, lessThan(-0.6));

      // Green block: channel 1 high.
      expect(green.g, greaterThan(0.4));
      expect(green.r, lessThan(-0.6));

      // Empty corner stays neutral; a flip would move a coloured block here.
      expect(grey.r, lessThan(-0.5));
      expect(grey.b, lessThan(-0.5));

      // Positions: blue must not appear upper right, red must not appear lower right.
      final ({double r, double g, double b}) upperRight =
          regionMean(t, <int>[160, 210], <int>[20, 90]);
      expect(upperRight.b, lessThan(-0.5),
          reason: 'a horizontal or vertical flip would move the blue block here');
      expect(upperRight.r, lessThan(-0.5));
    });

    test('every EXIF orientation value produces the upright layout', () {
      // Fixtures: for each EXIF orientation 1-8, the stored pixels were written by Pillow such
      // that Pillow's own `ImageOps.exif_transpose` recovers one upright layout. The expected
      // layout is therefore fixed, and this asserts it per channel region for all eight values.
      //
      // This bit: it caught a real defect. `img.bakeOrientation` from the `image` package rotates
      // the stored pixels the wrong way for orientation 6 (see the note in the preprocessor), so
      // the app now applies the transform itself.
      for (int orientation = 1; orientation <= 8; orientation++) {
        final ModelInput input =
            fromFile('test/fixtures/exif/orientation_$orientation.png');
        final Float32List t = input.tensor;

        final ({double r, double g, double b}) tl =
            regionMean(t, <int>[20, 60], <int>[20, 90]);
        final ({double r, double g, double b}) lr =
            regionMean(t, <int>[160, 210], <int>[130, 200]);
        final ({double r, double g, double b}) ll =
            regionMean(t, <int>[20, 60], <int>[160, 215]);
        final ({double r, double g, double b}) tr =
            regionMean(t, <int>[160, 210], <int>[20, 90]);

        expect(tl.r, greaterThan(0.6), reason: 'orientation $orientation: red not upper-left');
        expect(lr.b, greaterThan(0.6), reason: 'orientation $orientation: blue not lower-right');
        expect(ll.g, greaterThan(0.4), reason: 'orientation $orientation: green not lower-left');
        expect(tr.r, lessThan(-0.5), reason: 'orientation $orientation: upper-right not empty');
        expect(tr.b, lessThan(-0.5), reason: 'orientation $orientation: upper-right not empty');
      }
    });

    test('applying the wrong orientation transform is detected', () {
      // Meta-test: the region assertions above must be able to fail. Orientation 6 stored
      // pixels are rotated, so running them through the orientation-1 path (i.e. ignoring
      // EXIF) leaves the red block in the wrong place and the assertion trips.
      final img.Image raw = img.decodePng(
        File('test/fixtures/exif/orientation_6.png').readAsBytesSync(),
      )!;
      final img.Image wronglyOriented = applyOrientationValue(raw, 1);
      final Float32List t = preprocessor
          .fromImageBytes(_encodePng(wronglyOriented))
          .tensor;
      final ({double r, double g, double b}) tl =
          regionMean(t, <int>[20, 60], <int>[20, 90]);
      expect(tl.r, lessThan(0.6),
          reason: 'ignoring EXIF must move the red block away from the upper left');
    });
  });


    test('JPEG orientation fixtures land upright too (the double-orientation regression)', () {
      // The `image` package's JPEG decoder applies EXIF orientation itself while its PNG decoder
      // does not, so the production path used to rotate JPEG photos a second time. These JPEG
      // fixtures are the regression: before the fix, orientations 2-8 all produced a wrongly
      // rotated layout, and the PNG-only coverage could not see it.
      for (final String extension in <String>['png', 'jpg']) {
        for (int orientation = 1; orientation <= 8; orientation++) {
          final ModelInput input =
              fromFile('test/fixtures/exif/orientation_$orientation.$extension');
          final Float32List t = input.tensor;
          final ({double r, double g, double b}) tl =
              regionMean(t, <int>[20, 60], <int>[20, 90]);
          final ({double r, double g, double b}) lr =
              regionMean(t, <int>[160, 210], <int>[130, 200]);
          final ({double r, double g, double b}) ll =
              regionMean(t, <int>[20, 60], <int>[160, 215]);

          final String where = '$extension orientation $orientation';
          expect(tl.r, greaterThan(0.6), reason: '$where: red not upper-left');
          expect(lr.b, greaterThan(0.6), reason: '$where: blue not lower-right');
          expect(ll.g, greaterThan(0.3), reason: '$where: green not lower-left');
        }
      }
    });

    test('JPEG and PNG agree for every orientation', () {
      // Same stored pixels, same tag, two containers: the produced tensors must match closely.
      for (int orientation = 1; orientation <= 8; orientation++) {
        final Float32List png =
            fromFile('test/fixtures/exif/orientation_$orientation.png').tensor;
        final Float32List jpg =
            fromFile('test/fixtures/exif/orientation_$orientation.jpg').tensor;
        double maxDelta = 0;
        for (int i = 0; i < png.length; i++) {
          final double delta = (png[i] - jpg[i]).abs();
          maxDelta = delta > maxDelta ? delta : maxDelta;
        }
        // JPEG is lossy, so equality is not expected; a wrongly applied rotation is a huge delta.
        expect(maxDelta, lessThan(0.6),
            reason: 'orientation $orientation: JPEG and PNG disagree (max delta $maxDelta), which '
                'means one of the two paths applied a different transform');
      }
    });

  group('a real photo compared with the Python reference', () {
    test('per-element residual stays within the measured band', () {
      final ModelInput input = fromFile('test/fixtures/reference_sample.jpg');
      final Float32List reference = _loadTensor('assets/test/reference_input.f32');

      expect(input.tensor.length, reference.length);

      double sumAbs = 0;
      double maxAbs = 0;
      int overThreshold = 0;
      for (int i = 0; i < reference.length; i++) {
        final double delta = (input.tensor[i] - reference[i]).abs();
        sumAbs += delta;
        maxAbs = delta > maxAbs ? delta : maxAbs;
        if (delta > 0.25) {
          overThreshold++;
        }
      }
      final double meanAbs = sumAbs / reference.length;
      final double fractionOver = overThreshold / reference.length;

      // The two pipelines use different resampling implementations (TensorFlow antialiased
      // bilinear vs the Dart area average), so element-wise equality is not expected. What is
      // required: small average residual and rare large differences.
      expect(meanAbs, lessThan(0.05),
          reason: 'mean absolute element difference vs the reference was $meanAbs '
              '(max $maxAbs, fraction over 0.25: $fractionOver)');
      expect(fractionOver, lessThan(0.02),
          reason: '$overThreshold elements differed by more than 0.25');
    });

    test('the region checks can actually fail: a channel-swapped tensor is rejected', () {
      // Meta-test so a future regression in channel order cannot pass silently.
      final ModelInput input = fromFile('test/fixtures/synthetic_orientation_1.png');
      final Float32List swapped = Float32List(input.tensor.length);
      for (int i = 0; i < input.tensor.length; i += 3) {
        swapped[i] = input.tensor[i + 2];
        swapped[i + 1] = input.tensor[i + 1];
        swapped[i + 2] = input.tensor[i];
      }
      final ({double r, double g, double b}) red =
          regionMean(swapped, <int>[20, 60], <int>[20, 90]);
      expect(red.r, lessThan(0.4), reason: 'the swapped tensor must fail the red assertion');
      expect(red.b, greaterThan(0.4), reason: 'the swapped tensor holds red in channel B');
    });
  });
}

/// Re-encodes a decoded image to PNG so it can be fed back through the preprocessor.
Uint8List _encodePng(img.Image image) => Uint8List.fromList(img.encodePng(image));

Float32List _loadTensor(String path) {
  final Uint8List bytes = File(path).readAsBytesSync();
  return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
}
