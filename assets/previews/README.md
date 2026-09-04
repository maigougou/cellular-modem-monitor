# README preview assets

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
