import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';

/// A collection of token data: groups → tokens, organized by mode.
class _CollectionData {
  final String name;
  final Map<String, Map<String, dynamic>> modeJsons; // modeName → full JSON

  _CollectionData(this.name, this.modeJsons);
}

/// A [Builder] that reads Figma token JSON files and generates
/// Dart ThemeExtension classes with typed values for each mode.
///
/// Supports two layouts:
/// - **Flat**: JSON files directly in `input_dir` → single ThemeExtension class
/// - **Multi-collection**: subdirectories in `input_dir` → one ThemeExtension
///   per subdirectory + a top-level accessor class
///
/// When a collection has only **one group**, tokens are flattened directly onto
/// the ThemeExtension class (no sub-group nesting).
class FigmaTokenBuilder implements Builder {
  final BuilderOptions options;

  FigmaTokenBuilder(this.options);

  String get _inputDir =>
      options.config['input_dir'] as String? ?? 'assets/figma';
  String get _outputDir =>
      options.config['output_dir'] as String? ?? 'lib/generated';
  String get _baseClass =>
      options.config['base_class'] as String? ?? 'Figma';

  @override
  Map<String, List<String>> get buildExtensions {
    var outDir = _outputDir;
    if (outDir.startsWith('lib/')) {
      outDir = outDir.substring(4);
    }
    return {
      r'$lib$': ['$outDir/${_baseClass.toLowerCase()}.g.dart'],
    };
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final collections = <_CollectionData>[];

    // Check for subdirectories first
    final subDirGlob = Glob('$_inputDir/*/*.tokens.json');
    final subDirAssets = <String, Map<String, Map<String, dynamic>>>{};

    await for (final asset in buildStep.findAssets(subDirGlob)) {
      final content = await buildStep.readAsString(asset);
      final json = jsonDecode(content) as Map<String, dynamic>;
      final modeName = _getModeName(json, asset.path);
      final parts = asset.path.split('/');
      final collectionName = parts[parts.length - 2];
      subDirAssets.putIfAbsent(collectionName, () => {});
      subDirAssets[collectionName]![modeName] = json;
    }

    for (final entry in subDirAssets.entries) {
      collections.add(_CollectionData(entry.key, entry.value));
    }

    // Flat structure fallback (backward compatible)
    if (collections.isEmpty) {
      final flatGlob = Glob('$_inputDir/*.tokens.json');
      final flatModes = <String, Map<String, dynamic>>{};

      await for (final asset in buildStep.findAssets(flatGlob)) {
        final content = await buildStep.readAsString(asset);
        final json = jsonDecode(content) as Map<String, dynamic>;
        final modeName = _getModeName(json, asset.path);
        flatModes[modeName] = json;
      }

      if (flatModes.isNotEmpty) {
        collections.add(_CollectionData('', flatModes));
      }
    }

    if (collections.isEmpty) {
      log.warning('FigmaTokenBuilder: No token files found in "$_inputDir".');
      return;
    }

    collections.sort((a, b) => a.name.compareTo(b.name));

    // Generate code
    final buffer = StringBuffer();
    _writeHeader(buffer);

    final isMultiCollection =
        collections.length > 1 ||
        (collections.length == 1 && collections.first.name.isNotEmpty);

    for (final collection in collections) {
      final className = isMultiCollection
          ? '$_baseClass${_toPascalCase(collection.name)}'
          : _baseClass;
      _generateCollectionClass(buffer, className, collection);
    }

    if (isMultiCollection) {
      _writeAccessorClass(buffer, collections);
    }

    // BuildContext extensions
    _writeContextExtensions(buffer, collections, isMultiCollection);

    final outputAsset = AssetId(
      buildStep.inputId.package,
      '$_outputDir/${_baseClass.toLowerCase()}.g.dart',
    );
    await buildStep.writeAsString(outputAsset, buffer.toString());

    log.info(
      'FigmaTokenBuilder: Generated ${outputAsset.path} '
      '(${collections.length} collection(s))',
    );
  }

  // ---------------------------------------------------------------------------
  // Collection generation
  // ---------------------------------------------------------------------------

  void _generateCollectionClass(
    StringBuffer buffer,
    String className,
    _CollectionData collection,
  ) {
    final firstJson = collection.modeJsons.values.first;

    // Separate flat tokens (have $type) from groups (nested maps without $type)
    final flatTokens = <String>[];
    final groups = <String, List<String>>{};

    firstJson.forEach((key, value) {
      if (key.startsWith(r'$')) return;
      if (value is Map<String, dynamic>) {
        if (value.containsKey(r'$type')) {
          // Flat token: has $type/$value directly
          flatTokens.add(key);
        } else {
          // Group: nested map containing tokens
          final tokens = value.keys.where((k) => !k.startsWith(r'$')).toList();
          if (tokens.isNotEmpty) {
            groups[key] = tokens;
          }
        }
      }
    });

    if (flatTokens.isEmpty && groups.isEmpty) return;

    if (flatTokens.isNotEmpty && groups.isEmpty) {
      // All tokens are flat → generate flat class (no groups)
      _generateFlatClassFromTokens(buffer, className, collection, flatTokens);
    } else if (flatTokens.isEmpty && groups.length == 1) {
      // Single group → flatten onto class
      _generateFlatClass(buffer, className, collection, groups);
    } else {
      // Multiple groups (and/or mix of flat + grouped) → nested classes
      if (flatTokens.isNotEmpty) {
        groups['_root'] = flatTokens;
      }
      _generateNestedClass(buffer, className, collection, groups);
    }
  }

  // ---------------------------------------------------------------------------
  // Flat mode: tokens directly on ThemeExtension class
  // ---------------------------------------------------------------------------

  /// Flat tokens at root level (no groups at all).
  /// Extracts value from json[tokenName].$value
  void _generateFlatClassFromTokens(
    StringBuffer b,
    String className,
    _CollectionData collection,
    List<String> tokens,
  ) {
    b.writeln('class $className extends ThemeExtension<$className> {');

    for (final t in tokens) {
      b.writeln('  final double ${_toCamelCase(t)};');
    }
    b.writeln();

    b.writeln('  const $className({');
    for (final t in tokens) {
      b.writeln('    required this.${_toCamelCase(t)},');
    }
    b.writeln('  });');
    b.writeln();

    final sortedModes = collection.modeJsons.keys.toList()..sort();
    for (final modeName in sortedModes) {
      final json = collection.modeJsons[modeName]!;
      b.writeln('  static const ${_toCamelCase(modeName)} = $className(');
      for (final t in tokens) {
        final value = _extractFlatValue(json, t);
        b.writeln('    ${_toCamelCase(t)}: ${value.toDouble()},');
      }
      b.writeln('  );');
      b.writeln();
    }

    _writeOfMethod(b, className);

    // copyWith
    b.writeln('  @override');
    b.writeln('  $className copyWith({');
    for (final t in tokens) {
      b.writeln('    double? ${_toCamelCase(t)},');
    }
    b.writeln('  }) {');
    b.writeln('    return $className(');
    for (final t in tokens) {
      final camel = _toCamelCase(t);
      b.writeln('      $camel: $camel ?? this.$camel,');
    }
    b.writeln('    );');
    b.writeln('  }');
    b.writeln();

    // lerp
    b.writeln('  @override');
    b.writeln('  $className lerp(covariant $className? other, double t) {');
    b.writeln('    if (other == null) return this;');
    b.writeln('    return $className(');
    for (final t in tokens) {
      final camel = _toCamelCase(t);
      b.writeln('      $camel: $camel + (other.$camel - $camel) * t,');
    }
    b.writeln('    );');
    b.writeln('  }');
    b.writeln();

    _writeHashEquals(b, className, tokens.map(_toCamelCase).toList());

    b.writeln('}');
    b.writeln();
  }

  /// Single group → flatten tokens onto class (legacy grouped format).

  void _generateFlatClass(
    StringBuffer b,
    String className,
    _CollectionData collection,
    Map<String, List<String>> groups,
  ) {
    final groupName = groups.keys.first;
    final tokens = groups[groupName]!;

    b.writeln('class $className extends ThemeExtension<$className> {');

    for (final t in tokens) {
      b.writeln('  final double ${_toCamelCase(t)};');
    }
    b.writeln();

    b.writeln('  const $className({');
    for (final t in tokens) {
      b.writeln('    required this.${_toCamelCase(t)},');
    }
    b.writeln('  });');
    b.writeln();

    // Static presets
    final sortedModes = collection.modeJsons.keys.toList()..sort();
    for (final modeName in sortedModes) {
      final json = collection.modeJsons[modeName]!;
      b.writeln('  static const ${_toCamelCase(modeName)} = $className(');
      for (final t in tokens) {
        final value = _extractValue(json, groupName, t);
        b.writeln('    ${_toCamelCase(t)}: ${value.toDouble()},');
      }
      b.writeln('  );');
      b.writeln();
    }

    _writeOfMethod(b, className);

    // copyWith
    b.writeln('  @override');
    b.writeln('  $className copyWith({');
    for (final t in tokens) {
      b.writeln('    double? ${_toCamelCase(t)},');
    }
    b.writeln('  }) {');
    b.writeln('    return $className(');
    for (final t in tokens) {
      final camel = _toCamelCase(t);
      b.writeln('      $camel: $camel ?? this.$camel,');
    }
    b.writeln('    );');
    b.writeln('  }');
    b.writeln();

    // lerp
    b.writeln('  @override');
    b.writeln('  $className lerp(covariant $className? other, double t) {');
    b.writeln('    if (other == null) return this;');
    b.writeln('    return $className(');
    for (final t in tokens) {
      final camel = _toCamelCase(t);
      b.writeln('      $camel: $camel + (other.$camel - $camel) * t,');
    }
    b.writeln('    );');
    b.writeln('  }');
    b.writeln();

    _writeHashEquals(b, className, tokens.map(_toCamelCase).toList());

    b.writeln('}');
    b.writeln();
  }

  // ---------------------------------------------------------------------------
  // Nested mode: multiple groups → sub-group classes
  // ---------------------------------------------------------------------------

  void _generateNestedClass(
    StringBuffer b,
    String className,
    _CollectionData collection,
    Map<String, List<String>> groups,
  ) {
    // Sub-group classes
    groups.forEach((groupName, tokens) {
      final groupClass = '_${className}_${_toPascalCase(groupName)}Group';
      b.writeln('class $groupClass {');

      for (final t in tokens) {
        b.writeln('  final double ${_toCamelCase(t)};');
      }
      b.writeln();

      b.writeln('  const $groupClass({');
      for (final t in tokens) {
        b.writeln('    required this.${_toCamelCase(t)},');
      }
      b.writeln('  });');
      b.writeln();

      b.writeln('  $groupClass copyWith({');
      for (final t in tokens) {
        b.writeln('    double? ${_toCamelCase(t)},');
      }
      b.writeln('  }) {');
      b.writeln('    return $groupClass(');
      for (final t in tokens) {
        final camel = _toCamelCase(t);
        b.writeln('      $camel: $camel ?? this.$camel,');
      }
      b.writeln('    );');
      b.writeln('  }');
      b.writeln();

      b.writeln(
        '  static $groupClass lerp($groupClass a, $groupClass b, double t) {',
      );
      b.writeln('    return $groupClass(');
      for (final t in tokens) {
        final camel = _toCamelCase(t);
        b.writeln('      $camel: a.$camel + (b.$camel - a.$camel) * t,');
      }
      b.writeln('    );');
      b.writeln('  }');

      b.writeln('}');
      b.writeln();
    });

    // Main ThemeExtension class
    b.writeln('class $className extends ThemeExtension<$className> {');

    for (final g in groups.keys) {
      b.writeln(
        '  final _${className}_${_toPascalCase(g)}Group ${_toCamelCase(g)};',
      );
    }
    b.writeln();

    b.writeln('  const $className({');
    for (final g in groups.keys) {
      b.writeln('    required this.${_toCamelCase(g)},');
    }
    b.writeln('  });');
    b.writeln();

    // Static presets
    final sortedModes = collection.modeJsons.keys.toList()..sort();
    for (final modeName in sortedModes) {
      final json = collection.modeJsons[modeName]!;
      b.writeln('  static const ${_toCamelCase(modeName)} = $className(');
      groups.forEach((groupName, tokens) {
        b.writeln(
          '    ${_toCamelCase(groupName)}: _${className}_${_toPascalCase(groupName)}Group(',
        );
        for (final t in tokens) {
          final value = _extractValue(json, groupName, t);
          b.writeln('      ${_toCamelCase(t)}: ${value.toDouble()},');
        }
        b.writeln('    ),');
      });
      b.writeln('  );');
      b.writeln();
    }

    _writeOfMethod(b, className);

    // copyWith
    b.writeln('  @override');
    b.writeln('  $className copyWith({');
    for (final g in groups.keys) {
      b.writeln(
        '    _${className}_${_toPascalCase(g)}Group? ${_toCamelCase(g)},',
      );
    }
    b.writeln('  }) {');
    b.writeln('    return $className(');
    for (final g in groups.keys) {
      final camel = _toCamelCase(g);
      b.writeln('      $camel: $camel ?? this.$camel,');
    }
    b.writeln('    );');
    b.writeln('  }');
    b.writeln();

    // lerp
    b.writeln('  @override');
    b.writeln('  $className lerp(covariant $className? other, double t) {');
    b.writeln('    if (other == null) return this;');
    b.writeln('    return $className(');
    for (final g in groups.keys) {
      final camel = _toCamelCase(g);
      b.writeln(
        '      $camel: _${className}_${_toPascalCase(g)}Group.lerp($camel, other.$camel, t),',
      );
    }
    b.writeln('    );');
    b.writeln('  }');
    b.writeln();

    _writeHashEquals(b, className, groups.keys.map(_toCamelCase).toList());

    b.writeln('}');
    b.writeln();
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  void _writeHeader(StringBuffer b) {
    b.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    b.writeln('// Generated by figma_tokens_builder');
    b.writeln();
    b.writeln(
      '// ignore_for_file: library_private_types_in_public_api, camel_case_types',
    );
    b.writeln();
    b.writeln("import 'package:flutter/material.dart';");
    b.writeln();
  }

  void _writeOfMethod(StringBuffer b, String className) {
    b.writeln('  /// Retrieve the nearest [$className] from the widget tree.');
    b.writeln('  static $className of(BuildContext context) {');
    b.writeln('    return Theme.of(context).extension<$className>()!;');
    b.writeln('  }');
    b.writeln();
  }

  void _writeHashEquals(StringBuffer b, String cls, List<String> fields) {
    b.writeln('  @override');
    b.writeln('  int get hashCode {');
    if (fields.length == 1) {
      b.writeln('    return ${fields.first}.hashCode;');
    } else {
      b.writeln('    return Object.hash(');
      b.writeln('      ${fields.join(',\n      ')},');
      b.writeln('    );');
    }
    b.writeln('  }');
    b.writeln();

    b.writeln('  @override');
    b.writeln('  bool operator ==(Object other) {');
    b.writeln('    if (identical(this, other)) return true;');
    b.writeln('    if (other is! $cls) return false;');
    final cond = fields.map((f) => '$f == other.$f').join(' && ');
    b.writeln('    return $cond;');
    b.writeln('  }');
  }

  /// Generates accessor classes and the top-level namespace class.
  void _writeAccessorClass(StringBuffer b, List<_CollectionData> collections) {
    for (final c in collections) {
      final className = '$_baseClass${_toPascalCase(c.name)}';
      final accessorName = '_${className}Accessor';

      b.writeln('class $accessorName {');
      b.writeln('  const $accessorName();');
      b.writeln();

      final sortedModes = c.modeJsons.keys.toList()..sort();
      for (final mode in sortedModes) {
        final camelMode = _toCamelCase(mode);
        b.writeln('  $className get $camelMode => $className.$camelMode;');
      }
      b.writeln();

      b.writeln('  /// Retrieve [$className] from the nearest [Theme].');
      b.writeln(
        '  $className of(BuildContext context) => $className.of(context);',
      );

      b.writeln('}');
      b.writeln();
    }

    // Collect all unique modes across collections
    final allModes = <String>{};
    for (final c in collections) {
      allModes.addAll(c.modeJsons.keys);
    }
    final sortedAllModes = allModes.toList()..sort();

    b.writeln('/// Top-level accessor for all Figma token collections.');
    b.writeln('class $_baseClass {');
    b.writeln('  $_baseClass._();');
    b.writeln();

    // Collection accessors (e.g. Figma.spacing)
    for (final c in collections) {
      final className = '$_baseClass${_toPascalCase(c.name)}';
      final accessorName = '_${className}Accessor';
      b.writeln('  static const ${_toCamelCase(c.name)} = $accessorName();');
    }
    b.writeln();

    // Mode getters returning List<ThemeExtension> (e.g. Figma.mobile)
    b.writeln('  // --- Mode presets (all collections at once) ---');
    b.writeln();
    for (final mode in sortedAllModes) {
      final camelMode = _toCamelCase(mode);
      final items = <String>[];
      for (final c in collections) {
        if (c.modeJsons.containsKey(mode)) {
          final className = '$_baseClass${_toPascalCase(c.name)}';
          items.add('$className.$camelMode');
        }
      }
      b.writeln(
        '  static List<ThemeExtension> get $camelMode => [${items.join(', ')}];',
      );
    }

    b.writeln('}');
    b.writeln();
  }

  /// Generates BuildContext extensions for convenient access.
  ///
  /// ```dart
  /// extension FigmaSpacingContext on BuildContext {
  ///   FigmaSpacing get spacing => FigmaSpacing.of(this);
  /// }
  /// ```
  void _writeContextExtensions(
    StringBuffer b,
    List<_CollectionData> collections,
    bool isMultiCollection,
  ) {
    b.writeln('// --- BuildContext extensions ---');
    b.writeln();

    if (isMultiCollection) {
      for (final c in collections) {
        final className = '$_baseClass${_toPascalCase(c.name)}';
        final fieldName = _toCamelCase(c.name);
        b.writeln('extension ${className}Context on BuildContext {');
        b.writeln('  $className get $fieldName => $className.of(this);');
        b.writeln('}');
        b.writeln();
      }
    } else {
      final className = _baseClass;
      final fieldName = _toCamelCase(_baseClass);
      b.writeln('extension ${className}Context on BuildContext {');
      b.writeln('  $className get $fieldName => $className.of(this);');
      b.writeln('}');
      b.writeln();
    }
  }

  // ---------------------------------------------------------------------------
  // Utility methods
  // ---------------------------------------------------------------------------

  num _extractValue(Map<String, dynamic> json, String group, String token) {
    if (group == '_root') {
      return _extractFlatValue(json, token);
    }
    final groupData = json[group] as Map<String, dynamic>?;
    if (groupData == null) return 0;
    final tokenData = groupData[token] as Map<String, dynamic>?;
    if (tokenData == null) return 0;
    final value = tokenData[r'$value'];
    if (value is num) return value;
    return 0;
  }

  /// Extracts value from a flat token (no group nesting).
  num _extractFlatValue(Map<String, dynamic> json, String token) {
    final tokenData = json[token] as Map<String, dynamic>?;
    if (tokenData == null) return 0;
    final value = tokenData[r'$value'];
    if (value is num) return value;
    return 0;
  }

  String _getModeName(Map<String, dynamic> json, String path) {
    final extensions = json[r'$extensions'] as Map<String, dynamic>?;
    if (extensions != null) {
      final modeName = extensions['com.figma.modeName'] as String?;
      if (modeName != null && modeName.isNotEmpty) return modeName;
    }
    final fileName = path.split('/').last;
    return fileName.split('.').first;
  }

  String _toCamelCase(String s) {
    final parts = s.split(RegExp(r'[-_]'));
    if (parts.isEmpty) return s;
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      if (i == 0) {
        buffer.write(part[0].toLowerCase());
        if (part.length > 1) buffer.write(part.substring(1));
      } else {
        buffer.write(part[0].toUpperCase());
        if (part.length > 1) buffer.write(part.substring(1));
      }
    }
    return buffer.toString();
  }

  String _toPascalCase(String s) {
    final parts = s.split(RegExp(r'[-_]'));
    if (parts.isEmpty) return s;
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part.isEmpty) continue;
      buffer.write(part[0].toUpperCase());
      if (part.length > 1) buffer.write(part.substring(1));
    }
    return buffer.toString();
  }
}
