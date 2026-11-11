# Font credits and sources

The UI fonts in `art/fonts/` give zorx Thai glyphs (the engine default font, Open Sans SemiBold,
has none, so Thai shows as boxes on the web — see `docs/design/ui_style_guide.md` §11). Both are
from the official Google Fonts repository and are licensed under the SIL Open Font License 1.1.

| Shipped file | Weight / use | Source | Licence |
|---|---|---|---|
| `art/fonts/Sarabun-Regular.woff2` | Body text (default `FONT`) | [google/fonts `ofl/sarabun`](https://github.com/google/fonts/tree/main/ofl/sarabun), Suppakit Chalermlarp / Cadson Demak | SIL OFL 1.1 (`Sarabun-OFL.txt`) |
| `art/fonts/Sarabun-SemiBold.woff2` | Body emphasis (kept for a bold slot) | same | SIL OFL 1.1 (`Sarabun-OFL.txt`) |
| `art/fonts/Taviraj-SemiBold.woff2` | Display / headings (`DISPLAY_FONT`) | [google/fonts `ofl/taviraj`](https://github.com/google/fonts/tree/main/ofl/taviraj), Cadson Demak | SIL OFL 1.1 (`Taviraj-OFL.txt`) |

Fonts chosen by the Boss on 2026-10-12: **Taviraj** for display/headings, **Sarabun** for body.

The shipped `.woff2` files are **subset** to the characters the UI uses (the whole Thai block
U+0E00–U+0E7F, basic Latin + Latin-1, and the punctuation/symbols the screens show), to keep the
web data pack small: ~73 KB total (Sarabun Regular 19.1 KB, Sarabun SemiBold 19.3 KB,
Taviraj SemiBold 34.7 KB) versus ~394 KB for the full TTFs.

The full source TTFs and their original `OFL.txt` are kept in `art_source/fonts/` (which has a
`.gdignore`, so Godot does not import them and they do not ship). A copy of each OFL licence also
ships next to the fonts (`Sarabun-OFL.txt`, `Taviraj-OFL.txt`), as the OFL requires.

Regenerate the subset WOFF2 files:

    python3 -m pip install --user fonttools brotli   # once (brotli = woff2 support)
    PATH="$HOME/Library/Python/3.10/bin:$PATH" python3 tools/fonts/subset_fonts.py

- Changa One Italic — Eduardo Tunni / Google Fonts, SIL Open Font License1.1. Used for compact floating loot labels; license ChangaOne-OFL.txt. Existing Sarabun supplies Thai glyph fallback.
