import 'package:flutter_test/flutter_test.dart';
import 'package:aura_guide_fyp/services/spoken_pin_parser.dart';

void main() {
  group('SpokenPinParser.extractDigitTokens', () {
    test('extracts English word digits', () {
      expect(SpokenPinParser.extractDigitTokens('one two three four'), ['1', '2', '3', '4']);
      expect(SpokenPinParser.extractDigitTokens('nine zero eight five'), ['9', '0', '8', '5']);
      expect(SpokenPinParser.extractDigitTokens('o seven won tree'), ['0', '7', '1', '3']);
    });

    test('extracts Malay word digits', () {
      expect(SpokenPinParser.extractDigitTokens('satu dua tiga empat'), ['1', '2', '3', '4']);
      expect(SpokenPinParser.extractDigitTokens('kosong lima lapan sembilan'), ['0', '5', '8', '9']);
      expect(SpokenPinParser.extractDigitTokens('sifar tujuh enam dua'), ['0', '7', '6', '2']);
    });

    test('extracts Chinese character digits (with or without spaces)', () {
      expect(SpokenPinParser.extractDigitTokens('一二三四'), ['1', '2', '3', '4']);
      expect(SpokenPinParser.extractDigitTokens('五 六 七 八'), ['5', '6', '7', '8']);
      expect(SpokenPinParser.extractDigitTokens('九零壹贰'), ['9', '0', '1', '2']);
      expect(SpokenPinParser.extractDigitTokens('两 叁 肆 伍'), ['2', '3', '4', '5']);
    });

    test('extracts mixed representations and numeric digits', () {
      expect(SpokenPinParser.extractDigitTokens('1 two tiga 四'), ['1', '2', '3', '4']);
      expect(SpokenPinParser.extractDigitTokens('8 9 0 1'), ['8', '9', '0', '1']);
      expect(SpokenPinParser.extractDigitTokens('1234'), ['1', '2', '3', '4']);
    });

    test('extracts up to 4 digits', () {
      expect(SpokenPinParser.extractDigitTokens('one two three four five'), ['1', '2', '3', '4']);
    });
  });

  group('SpokenPinParser.mergeDigitTokens', () {
    test('handles cumulative transcripts without duplication', () {
      List<String> existing = [];
      
      existing = SpokenPinParser.mergeDigitTokens(existing, 'one');
      expect(existing, ['1']);

      existing = SpokenPinParser.mergeDigitTokens(existing, 'one two');
      expect(existing, ['1', '2']);

      existing = SpokenPinParser.mergeDigitTokens(existing, 'one two three');
      expect(existing, ['1', '2', '3']);

      existing = SpokenPinParser.mergeDigitTokens(existing, 'one two three four');
      expect(existing, ['1', '2', '3', '4']);
    });

    test('handles non-cumulative/segmented transcripts by appending', () {
      List<String> existing = [];

      existing = SpokenPinParser.mergeDigitTokens(existing, 'one');
      expect(existing, ['1']);

      existing = SpokenPinParser.mergeDigitTokens(existing, 'two');
      expect(existing, ['1', '2']);

      existing = SpokenPinParser.mergeDigitTokens(existing, 'three');
      expect(existing, ['1', '2', '3']);

      existing = SpokenPinParser.mergeDigitTokens(existing, 'four');
      expect(existing, ['1', '2', '3', '4']);
    });

    test('handles segment overlap merges', () {
      List<String> existing = ['1', '2'];
      
      // Overlapping "two three" with "one two"
      existing = SpokenPinParser.mergeDigitTokens(existing, 'two three');
      expect(existing, ['1', '2', '3']);
    });

    test('handles cumulative transcript corrections/updates', () {
      List<String> existing = ['1', '2'];

      // User correction from "one two" to "one three"
      existing = SpokenPinParser.mergeDigitTokens(existing, 'one three');
      expect(existing, ['1', '3']);
    });
  });
}
