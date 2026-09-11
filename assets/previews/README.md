# README preview assets

## Menu-bar CA preview

`menu-bar-ca-preview.png` captures the production `MenuBarImageRenderer` inside
a real `NSStatusBarButton` in light and dark appearances. It covers NSA, SA,
LTE-only, compact, single-carrier, stale/unknown, long-value and icon-only labels.
SA and LTE-only are centered single-line labels; NSA uses two 9 pt lines in
the native 22 pt menu-bar height. The two RATs share identity, separator and
right-aligned count columns; their CC suffixes align even when one count has
more digits. Native captures assert equal count right-edge pixels for every
two-line scenario in both appearances. Images are Retina template images, so macOS
handles foreground contrast. The values are illustrative, not live modem data.

Compile `scripts/MenuBarScreenshotGenerator.swift` together with the files in
`Sources/SignalStatus` except `SignalStatusApp.swift`, then run the executable
with an output directory argument. It needs access to macOS WindowServer and
temporarily adds one status item, removed when the capture finishes. It does not
construct `StatusModel`, read stored credentials, or contact a modem.

## Panel previews

The main READMEs use 12 pairs per language, always light on the left and dark on the right. Both images in a pair use the same fixture, width and card state. English images live in `en/`; Simplified Chinese images live in `zh-CN/`.

These are renders of the app's actual SwiftUI views, not separately drawn mockups. All device identities, Cell IDs, radio measurements and speed results in this gallery are illustrative. They are not device benchmarks or a claim that every shown band combination is available on every network.

## Example consistency

| Scene | NR serving carrier | LTE serving carrier | Active aggregation |
| --- | --- | --- | --- |
| SA | n77, 50 MHz | None | None |
| NSA | n77, 50 MHz | B2, 20 MHz | None |
| CA / full overview | n77, 50 MHz | B2, 20 MHz | NR: n77 50 + n77 30 MHz; LTE: B2 20 + B66 20 MHz |

In the CA fixtures, n71 10 MHz and LTE B7 20 MHz are configured but inactive. They remain visible, but the active summaries count only **2CC · 80 MHz** for NR and **2CC · 40 MHz** for LTE. Every serving card matches the band, channel, bandwidth, signal and Cell ID of its PCell. A per-carrier LTE bandwidth never exceeds 20 MHz.

The `ReadmeFixture.validate()` checks in the renderer enforce these invariants before exporting. The screenshot build defines `README_SCREENSHOTS` to select individual real cards and configure an offline modem model. Those entry points are excluded from normal application builds. No modem connection, Ookla process or stored credential is used.

## Regenerate

From the repository root on macOS:

```sh
./scripts/generate-readme-screenshots.sh
python3 scripts/verify-readme-previews.py
```

The first command compiles the renderer and exports all 48 PNGs. The second checks README links, scene parity, left/right theme order, top alignment and equal dimensions within each pair.

For a smaller iteration, compile with `--compile-only`, then use for example:

```sh
README_SCENES='sa nsa ca' ./scripts/generate-readme-screenshots.sh --render-only
```

## Carrier column alignment regression

Pass `--alignment-stress` to `ReadmeScreenshotGenerator` with `--scene ca` to
render maximum-length Cell IDs next to short PCI values and all three UL labels.
Exercise `--compact`, the default standard width, and `--wide`, in both themes
and languages. Keep `-zh-` in Chinese output filenames for the OCR language selector.

Compile `scripts/VerifyCarrierAlignment.swift` with `swiftc -parse-as-library`
and pass the resulting screenshots as arguments. It uses macOS Vision to locate
labels, refines those boxes to actual glyph pixels, checks UL's left edge against
every other row and SINR/SNR (3 px tolerance), and verifies that the full 11-digit
NR Cell ID is still visible. It requires access to macOS Vision services.
