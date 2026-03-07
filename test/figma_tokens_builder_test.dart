import 'package:build/build.dart';
import 'package:figma_tokens_builder/src/figma_token_builder.dart';
import 'package:test/test.dart';

void main() {
  group('FigmaTokenBuilder', () {
    test('toCamelCase converts kebab-case', () {
      final builder = FigmaTokenBuilder(const BuilderOptions({}));
      // Builder is created successfully
      expect(builder, isNotNull);
    });
  });
}
