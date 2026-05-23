# Building Disk Inventory Z

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15.x

## Build from source

```sh
git clone https://github.com/danifunker/disk-inventory-z.git
cd disk-inventory-z
xcodebuild -project "Disk Inventory Z.xcodeproj" \
           -scheme "Disk Inventory Z" \
           -configuration Release build
```

The build product lands at `build/Release/Disk Inventory Z.app`.

For a quick debug build you can drop `-configuration Release` (the default
is Debug, which writes to `build/Debug/`).

## Project layout

Everything the Xcode target builds lives under `src/`; the repository root
holds only docs, the project file, and CI config.

| Path                 | Contents                                                        |
| -------------------- | --------------------------------------------------------------- |
| `src/Source/`        | Application Objective-C sources                                 |
| `src/Resources/`     | Images, toolbar definition, and other bundled assets            |
| `src/Vendor/`        | Third-party / derived code (OmniAppKit shims, CocoaTech helpers)|
| `src/TreeMapView/`   | The folded-in treemap rendering sources                         |
| `src/*.lproj/`       | Localized nibs and strings (en, de, es, fr)                     |
| `src/Images.xcassets`| App icon and asset catalog                                      |
| `src/Info.plist`     | App bundle configuration and entitlements                       |
| `scripts/`           | Build and maintenance scripts                                   |
| `docs/`              | Developer notes and reference material                          |

## Releases

Tagged builds (`v*`) run [`.github/workflows/release.yml`](.github/workflows/release.yml)
on macOS. The workflow signs the app with the project's Developer ID,
notarizes it through Apple's notary service, and attaches a stapled `.dmg`
to the GitHub release.

To cut a release, push a tag:

```sh
git tag v2.1.0
git push origin v2.1.0
```

## Lineage

Disk Inventory Z is a fork of
[Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x) by
Tjark Derlien. Notable structural changes from upstream:

- Removed the OmniAppKit / OmniFoundation / OmniBase dependencies (the
  original framework set is no longer maintained for current macOS / Xcode).
- Folded the standalone
  [`treemapview-framework`](https://gitlab.com/tderlien/treemapview-framework)
  sources directly into the app target — one repo, one build, no embedded
  framework.
- macOS 13+ targeting, hardened runtime, Developer ID signing, and
  notarization driven by GitHub Actions.
