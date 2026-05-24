# Bundled font

`ShipporiMincho-SemiBold.ttf` is a **subset** of Shippori Mincho SemiBold
(SIL Open Font License — see `OFL.txt`), reduced to only the glyphs Kaki renders
in its wordmark: **柿 k a i**.

The full upstream font is ~8.25 MB (thousands of CJK glyphs); we use four, so the
subset is ~3.4 KB. This keeps the `.app` lightweight without changing the look.

Regenerate from the upstream font (HarfBuzz `hb-subset`):

```bash
curl -fsSL -o full.ttf \
  https://github.com/google/fonts/raw/main/ofl/shipporimincho/ShipporiMincho-SemiBold.ttf
hb-subset full.ttf --text="柿kaki" --name-IDs='*' --output-file=ShipporiMincho-SemiBold.ttf
```

All `name` records are retained, so `NSFont fontWithName:@"Shippori Mincho SemiBold"`
still resolves after `CTFontManagerRegisterFontsForURL`.
