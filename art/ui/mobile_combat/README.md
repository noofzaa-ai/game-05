# Supplied mobile combat button artwork

Original PNG bytes supplied by the user on 2026-10-16, including Thai labels and alpha.
No image regeneration or background replacement. Godot imports at a 512px limit with mipmaps
to reduce runtime texture memory; source files stay unchanged.

The approved layout measurements are in client/mobile_controls.gd REFERENCE_BUTTONS.
Transparent padding differs per image. client/mobile_combat_art.gd BODY_UV maps the visible
rim into the button body rectangle; glow/shadow may draw outside the hit ellipse.
The bodies retain the approved reference aspect ratios and relative center offsets.

| Action | Original attachment | SHA256 |
|---|---|---|
| light | codex-clipboard-09ad7fc0-2602-4e58-b2e8-b9c6e373bedf.png | d7bd0af4c936a1f555369154f575f06c9bebab89092a604c53c81c65a1260958 |
| heavy | codex-clipboard-b5dcbd01-e469-4859-ad70-bc9af61e6a98.png | 158fbb8d7475f7e0615b70c635cca107ae7ea7973e69e38a8a83ff41bfac976f |
| special | codex-clipboard-7f5deaaf-bc0b-4379-807a-e87616616d67.png | b674a1954ee6d55850db9f047b2593adc7ecaf7f89c783d0265f96ebc0b5c738 |
| ultimate | codex-clipboard-8f31aebf-0892-4508-ae4b-08710cc74140.png | 68ff2511ec51079aee986f018a9b80547f4c2bb011a0583de2b3aba51da71bdf |
| guard | codex-clipboard-bd1c0ef6-caf1-4b06-aa89-d5df4c571cd1.png | e0b8f0a82fda731670e740eb7fe2215a288aa44fcd9bf52db20fc0df24d245d3 |
| dodge | codex-clipboard-e59c30f8-8c77-47db-a36b-095b3dc99656.png | 59fbfd2ba0414d68b46cb87a2a5e166c83dd0efab4d98005fe2a8505719ecf93 |
