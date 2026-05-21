# Disk Inventory Y

A native macOS disk usage explorer that visualizes folders and files as a [tree map](https://en.wikipedia.org/wiki/Treemapping). Pick a volume or folder, scan it, and see where your disk space actually went.

This is a fork of [Disk Inventory X](https://gitlab.com/tderlien/disk-inventory-x) by Tjark Derlien, with the following changes:

- Removed the OmniAppKit / OmniFoundation / OmniBase dependencies (the original framework set is no longer maintained for current macOS / Xcode).
- Folded the standalone [`treemapview-framework`](https://gitlab.com/tderlien/treemapview-framework) sources directly into the app target — one repo, one build, no embedded framework.
- Privacy / Full Disk Access flow: probes protected folders before scanning and skips the warning entirely when access is already granted; the prompt now has an **Open System Settings** button that deep-links to the Full Disk Access pane.
- macOS 12+ targeting, hardened runtime, Developer ID signing, and notarization driven by GitHub Actions.

## Building

```sh
xcodebuild -project "Disk Inventory Y.xcodeproj" \
           -scheme "Disk Inventory Y" \
           -configuration Release build
```

The build product lands at `build/Release/Disk Inventory Y.app`. Xcode 15.x on macOS 13+ is the supported environment.

## Releases

Tagged builds (`v*`) run `.github/workflows/release.yml` on macOS, which signs with the project's Developer ID, notarizes via Apple's notary service, and attaches a stapled `.dmg` to the GitHub release.

## License

GPL v3 — same as the upstream project. See `gpl-3.0.txt`.

Original copyright © Tjark Derlien.
