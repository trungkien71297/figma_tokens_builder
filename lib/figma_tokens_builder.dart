library figma_tokens_builder;

import 'package:build/build.dart';

import 'src/figma_token_builder.dart';

export 'src/figma_token_builder.dart';

/// Factory function for build_runner to create the [FigmaTokenBuilder].
Builder figmaTokenBuilder(BuilderOptions options) => FigmaTokenBuilder(options);
