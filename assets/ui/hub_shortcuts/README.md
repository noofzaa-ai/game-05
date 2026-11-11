# Hub shortcut artwork

User-provided transparent 2172×724 PNG, retained unchanged. `client/hub_shortcut_button.gd` uses native AtlasTexture regions for Menu / Player Info / Bag. Import size capped at1024; region coordinates scale with the imported texture dimensions.

2026-10-20: Boss requested half-size artwork after the first preview: maximum art height12.5 CSS px (a second 50% reduction requested by Boss), independent60×60 CSS px rectangular hit target. Hub shortcut root is separate from the menu content fitting so panel scaling cannot shrink touch targets. Mobile review is landscape only.

2026-10-20: Artwork now fits the existing60×60CSS target with3px inset, preserving aspect ratio. Captions overlay the bottom edge. Button size and spacing unchanged.

Keyboard PNG supplied2026-10-20, unchanged transparent source; AtlasTexture crops outer padding. Desktop-web Controls shortcut below Bag reopens browser key guide. Original top-right text button hidden.
