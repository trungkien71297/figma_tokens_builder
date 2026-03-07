# Figma Tokens Builder

A `build_runner` code generator that converts **Figma Variable** exports into type-safe Dart `ThemeExtension` classes — bridging the gap between design and code.

## Why Figma Variables?

![Figma Variables with modes](https://github.com/hautvfami/figma_tokens_builder/blob/main/example/assets/images/figma_variable.png?raw=true)

[Figma Variables](https://help.figma.com/hc/en-us/articles/15339657135383-Guide-to-variables-in-Figma) provide a **single source of truth** for design dimensions (spacing, sizing, radii, etc.) that both designers and developers follow. Instead of hardcoding pixel values across your codebase, you reference variables that automatically adapt to different device contexts.

**How it works in practice:**

1. **Designers** define variables in Figma with **modes** (e.g. Mobile, Tablet, Desktop) — each mode specifies different values for the same token (e.g. `card-padding` = 16px on Mobile, 24px on Tablet).
2. When combined with **Auto Layout**, Figma designs automatically stretch and reflow to match each mode — meaning a single design file covers phone, tablet, and desktop without creating separate mockups.
3. **This builder** takes those exported variables and generates Dart code that mirrors the same structure — so your Flutter app uses the exact same tokens and modes as the Figma design.

**The result:** Designers update a variable in Figma → you re-export and rebuild → your app automatically reflects the new values. No hardcoded numbers, no design-code drift, no manual breakpoint management.

## Features

- 🎨 Auto-generates `ThemeExtension` classes from Figma Design Tokens
- 📱 Static presets for each mode (`mobile`, `tablet`, `desktop`, …)
- 📦 Multi-collection support — organize tokens by type (`Spacing/`, `Avata/`, `Icon/`, …)
- 🔧 Flat token detection — tokens with `$type`/`$value` are placed directly on the class
- 🧩 `BuildContext` extensions — `context.spacing.spaceBlock`
- 🏗️ Namespace accessor — `Figma.spacing.mobile.spaceBlock`
- 🚀 Mode getters — `Figma.mobile` returns all collections at once
- ♻️ Includes `copyWith`, `lerp`, `hashCode`, `operator ==` boilerplate

---

## Getting Started

### 1. Add dependencies

In your **main project's** `pubspec.yaml`:

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  figma_tokens_builder:
    path: figma_tokens_builder
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
| `base_class` | `Figma`    | Base name for generated classes        |

### 3. Place token files

Export tokens from Figma using the **Variables** export (W3C format), placing each collection in a subdirectory:

```
assets/figma/
  ├── Avata/
  │   ├── Desktop.tokens.json
  │   ├── Mobile.tokens.json
  │   └── Tablet.tokens.json
  ├── Icon/
  │   ├── Desktop.tokens.json
  │   ├── Mobile.tokens.json
  │   └── Tablet.tokens.json
  ├── Image/
  │   ├── Mobile.tokens.json
  │   └── Tablet.tokens.json
  └── Spacing/
      ├── Desktop.tokens.json
      ├── Mobile.tokens.json
      └── Tablet.tokens.json
```

> Directory names are auto-converted to PascalCase for class names: `Spacing/` → `FigmaSpacing`

### 4. Run build_runner

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated file: `{output_dir}/{base_class_lowercase}.g.dart`  
Example: `lib/resources/figma.g.dart`

---

## Token JSON Format

The builder supports two token formats:

### Flat tokens (recommended)

Tokens directly at the root level — each with `$type` and `$value`:

```json
{
  "space-inline-tight": {
    "$type": "number",
    "$value": 4,
    "$extensions": { ... }
  },
  "space-inline": {
    "$type": "number",
    "$value": 8,
    "$extensions": { ... }
  },
  "$extensions": {
    "com.figma.modeName": "Mobile"
  }
}
```

→ Generates properties directly on the class: `FigmaSpacing.mobile.spaceInlineTight`

### Grouped tokens

Tokens nested inside groups (maps without `$type`):

```json
{
  "Size": {
    "image-thumbnail": { "$type": "number", "$value": 64 },
    "image-card":      { "$type": "number", "$value": 128 }
  },
  "Ratio": {
    "ratio-square":    { "$type": "number", "$value": 1.0 },
    "ratio-portrait":  { "$type": "number", "$value": 0.75 }
  },
  "$extensions": { "com.figma.modeName": "Mobile" }
}
```

→ Generates sub-group classes: `FigmaImage.mobile.size.imageThumbnail`

> **Mode name** is detected from `$extensions.com.figma.modeName`, or falls back to filename.

---

## Generated Classes

For the directory structure above, the builder generates:

| Collection | Class          | Type                  | Modes                   |
| ---------- | -------------- | --------------------- | ----------------------- |
| `Avata/`   | `FigmaAvata`   | flat tokens           | desktop, mobile, tablet |
| `Icon/`    | `FigmaIcon`    | flat tokens           | desktop, mobile, tablet |
| `Image/`   | `FigmaImage`   | grouped (Size, Ratio) | mobile, tablet          |
| `Spacing/` | `FigmaSpacing` | flat tokens           | desktop, mobile, tablet |

Plus:
- `Figma` — top-level namespace accessor with mode getters
- `BuildContext` extensions for each collection

---

## 3 Ways to Access Tokens

### 1. Namespace accessor (no context needed)

Directly access static presets — no `BuildContext` required:

```dart
Figma.spacing.mobile.spaceInlineTight   // → 4.0
Figma.spacing.tablet.spaceComponentMd   // → 32.0
Figma.avata.mobile.avataCompact         // → 32.0
Figma.icon.desktop.icoDefault           // → 24.0

// Or directly via the class
FigmaSpacing.mobile.spaceBlock          // → 16.0
```

**Use when:** You want a specific mode's value and don't need dynamic theming.

### 2. Namespace + context

Access the `ThemeExtension` registered in the current `ThemeData`:

```dart
Figma.spacing.of(context).spaceBlock
Figma.avata.of(context).avataCompact
```

**Use when:** You've registered extensions in `ThemeData` and want the active mode's values.

### 3. BuildContext extension (shortest syntax)

```dart
context.spacing.spaceBlock
context.avata.avataCompact
context.icon.icoDefault
context.image.size.imageThumbnail
```

**Use when:** Same as #2, but you prefer the shortest syntax.

> ⚠️ **Methods 2 & 3** require registering extensions in `ThemeData` (see below).

---

## Integrating with ThemeData

### Basic setup

Register all collections at once using `Figma.{mode}`:

```dart
MaterialApp(
  theme: ThemeData(
    extensions: Figma.mobile,
  ),
);
```

`Figma.mobile` returns `[FigmaAvata.mobile, FigmaIcon.mobile, FigmaImage.mobile, FigmaSpacing.mobile]` — no need to list each collection manually.

### Responsive setup (auto-switch by screen size)

```dart
MaterialApp(
  builder: (context, child) {
    final width = MediaQuery.of(context).size.width;
    final extensions = width > 1024
        ? Figma.desktop
        : width > 600
            ? Figma.tablet
            : Figma.mobile;

    return Theme(
      data: Theme.of(context).copyWith(extensions: [...extensions]),
      child: child!,
    );
  },
  theme: ThemeData(
    // other theme properties...
  ),
);
```

Now all widgets simply use `context.spacing.spaceBlock` — the correct mode values are applied automatically based on screen width.

> **Note:** When adding new collections, `Figma.mobile` / `Figma.tablet` / `Figma.desktop` auto-include them. No code changes needed.

---

## Full Example

### Token file: `assets/figma/Spacing/Mobile.tokens.json`

```json
{
  "space-inline-tight": { "$type": "number", "$value": 4,  "$extensions": { ... } },
  "space-inline":       { "$type": "number", "$value": 8,  "$extensions": { ... } },
  "space-component-sm": { "$type": "number", "$value": 16, "$extensions": { ... } },
  "space-block":        { "$type": "number", "$value": 16, "$extensions": { ... } },
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

class MyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      // Static preset (no context needed)
      margin: EdgeInsets.all(Figma.spacing.mobile.spaceBlock),

      // Dynamic from ThemeData (responsive)
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.spaceComponentSm,
        vertical: context.spacing.spaceInlineTight,
      ),

      child: Row(
        children: [
          CircleAvatar(
            radius: context.avata.avataCompact / 2,
          ),
          SizedBox(width: context.spacing.spaceInline),
          Text('Hello World'),
        ],
      ),
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
- For multi-collection, files must be in **subdirectories** (e.g. `assets/figma/Spacing/*.tokens.json`)

### Builder not detected
- Ensure `figma_tokens_builder` is in `dev_dependencies`
- Run `dart pub get` or `flutter pub get` after adding the dependency

### Empty generated classes
- Ensure tokens have `"$type"` and `"$value"` fields
- Keys starting with `$` are treated as metadata and skipped
