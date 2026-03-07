# Figma Tokens Builder

A `build_runner` builder that reads **Figma token JSON files** and generates type-safe Dart `ThemeExtension` classes with mode presets (Mobile, Tablet, Web, …).

## Features

- 🎨 Auto-generates `ThemeExtension` classes from Figma Design Tokens (W3C format)
- 📱 Static presets for each mode (`mobile`, `tablet`, `web`, …)
- 📦 Multi-collection support — organize tokens by type (spacing, colors, typography, …)
- 🔧 Single-group flattening — skip unnecessary nesting when a collection has only one group
- 🧩 `BuildContext` extensions — `context.spacing.cardPadding`
- 🏗️ Namespace accessor — `Figma.spacing.mobile.cardPadding`
- ♻️ Includes `copyWith`, `lerp`, `hashCode`, `operator ==` boilerplate

---

## Getting Started

### 1. Add dependencies

In your **main project's** `pubspec.yaml`:

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  figma_tokens_builder:
    path: figma_tokens_builder  # or publish to pub.dev
```

### 2. Configure `build.yaml`

In your **main project's** root `build.yaml`:

```yaml
targets:
  $default:
    builders:
      figma_tokens_builder|figma_token_builder:
        options:
          input_dir: "assets/figma"
          output_dir: "lib/resources"
          base_class: "Figma"
```

| Option       | Default         | Description                            |
| ------------ | --------------- | -------------------------------------- |
| `input_dir`  | `assets/figma`  | Directory containing token JSON files  |
| `output_dir` | `lib/generated` | Directory for generated `.g.dart` file |
| `base_class` | `AppSpacing`    | Base name for generated classes        |

### 3. Place token files

Export tokens from Figma using the **Design Tokens plugin** (W3C format).

### 4. Run build_runner

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated file: `{output_dir}/{base_class_lowercase}.g.dart`  
Example: `lib/resources/figma.g.dart`

---

## Directory Structure

The builder supports two layouts:

### Flat (single collection)

```
assets/figma/
  ├── Mobile.tokens.json
  ├── Tablet.tokens.json
  └── Web.tokens.json
```

Generates a **single** `ThemeExtension` class named `{base_class}` (e.g. `Figma`).

### Multi-collection (subdirectories)

```
assets/figma/
  ├── spacing/
  │   ├── Mobile.tokens.json
  │   ├── Tablet.tokens.json
  │   └── Web.tokens.json
  └── colors/
      ├── Mobile.tokens.json
      ├── Tablet.tokens.json
      └── Web.tokens.json
```

Generates:
- `FigmaSpacing` — ThemeExtension for spacing tokens
- `FigmaColors` — ThemeExtension for color tokens
- `Figma` — top-level namespace accessor class
- `BuildContext` extensions for each collection

> **Class naming:** `{base_class}` + `{directory_name_in_PascalCase}`  
> Example: base_class `Figma` + directory `spacing` → `FigmaSpacing`

---

## Token JSON Format

The builder expects the **W3C Design Tokens** format exported by Figma:

```json
{
  "GroupName": {
    "token-name": {
      "$type": "number",
      "$value": 16
    },
    "another-token": {
      "$type": "number",
      "$value": 24
    }
  },
  "$extensions": {
    "com.figma.modeName": "Mobile"
  }
}
```

- **Groups** — top-level keys (e.g. `"Semantic"`) become sub-group classes (or flattened if only one)
- **Tokens** — keys within a group (e.g. `"card-padding"`) become `camelCase` properties
- **Mode name** — detected from `$extensions.com.figma.modeName` or falls back to filename

---

## Generated Code & Usage

### Single-group collection (flattened)

When a collection has **one group**, tokens are placed directly on the class:

```dart
class FigmaSpacing extends ThemeExtension<FigmaSpacing> {
  final double componentGapTight;
  final double cardPadding;
  // ...

  static const mobile = FigmaSpacing(componentGapTight: 4.0, cardPadding: 16.0, ...);
  static const tablet = FigmaSpacing(componentGapTight: 8.0, cardPadding: 24.0, ...);
  static const web    = FigmaSpacing(componentGapTight: 8.0, cardPadding: 24.0, ...);
}
```

### Multi-group collection (nested)

When a collection has **multiple groups**, each group becomes a sub-class:

```dart
class FigmaSpacing extends ThemeExtension<FigmaSpacing> {
  final _FigmaSpacing_SemanticGroup semantic;
  final _FigmaSpacing_PrimitiveGroup primitive;
  // ...
}
```

Access: `FigmaSpacing.mobile.semantic.cardPadding`

---

## 3 Ways to Access Tokens

### 1. Namespace accessor (no context needed)

Directly access static presets without `BuildContext`:

```dart
// Access via top-level Figma class
Figma.spacing.mobile.cardPadding      // → 16.0
Figma.spacing.tablet.cardPadding      // → 24.0
Figma.spacing.web.cardGap             // → 32.0

// Or directly via the ThemeExtension class
FigmaSpacing.mobile.cardPadding       // → 16.0
```

**Use when:** You want a specific mode's value and don't need dynamic theming.

### 2. Namespace + context

Access the `ThemeExtension` registered in the current `ThemeData`:

```dart
Figma.spacing.of(context).cardPadding
```

**Use when:** You've registered a preset in `ThemeData` and want the currently active values.

### 3. BuildContext extension (shortest syntax)

```dart
context.spacing.cardPadding
```

Equivalent to `FigmaSpacing.of(context).cardPadding`.

**Use when:** Same as #2, but you prefer shorter syntax.

> ⚠️ **Methods 2 & 3** require registering the extension in `ThemeData` (see below).

---

## Integrating with ThemeData

### Basic setup

Register all collections at once using mode getters:

```dart
MaterialApp(
  theme: ThemeData(
    extensions: Figma.mobile,  // all collections for mobile mode!
  ),
);
```

Or register individual collections:

```dart
MaterialApp(
  theme: ThemeData(
    extensions: [
      FigmaSpacing.mobile,
      // FigmaColors.mobile,
    ],
  ),
);
```

### Responsive setup (auto-switch by screen size)

```dart
MaterialApp(
  builder: (context, child) {
    final width = MediaQuery.of(context).size.width;
    final extensions = width > 1024
        ? Figma.web
        : width > 600
            ? Figma.tablet
            : Figma.mobile;

    return Theme(
      data: Theme.of(context).copyWith(extensions: extensions),
      child: child!,
    );
  },
);
```

Now all widgets simply use `context.spacing.cardPadding` — the correct mode is selected automatically.

---

## Full Example

### Token file: `assets/figma/spacing/Mobile.tokens.json`

```json
{
  "Semantic": {
    "card-padding": { "$type": "number", "$value": 16 },
    "card-gap":     { "$type": "number", "$value": 16 }
  },
  "$extensions": { "com.figma.modeName": "Mobile" }
}
```

### Config: `build.yaml`

```yaml
targets:
  $default:
    builders:
      figma_tokens_builder|figma_token_builder:
        options:
          input_dir: "assets/figma"
          output_dir: "lib/resources"
          base_class: "Figma"
```

### Usage in widgets

```dart
import 'package:your_app/resources/figma.g.dart';

class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      // Option A: static preset
      padding: EdgeInsets.all(Figma.spacing.mobile.cardPadding),

      // Option B: from ThemeData (requires registration)
      // padding: EdgeInsets.all(context.spacing.cardPadding),

      child: Text('Hello'),
    );
  }
}
```

---

## Troubleshooting

### `UnexpectedOutputException`
```
Expected only: {package|lib/generated/figma.g.dart}
```
Make sure `output_dir` in `build.yaml` matches the expected output path. Run:
```bash
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### `No token files found`
- Verify JSON files are in `input_dir` with the `.tokens.json` extension
- For multi-collection, files must be in **subdirectories** (e.g. `assets/figma/spacing/*.tokens.json`)

### Builder not detected
- Ensure `figma_tokens_builder` is in `dev_dependencies`
- Run `dart pub get` or `flutter pub get` after adding the dependency
