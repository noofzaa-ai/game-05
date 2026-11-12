# Making images with the Codex CLI (agents call it through Bash)

Set up 2026-11-11 (Boss). Codex CLI 0.167.1 (`@openai/codex`) is installed globally and logged in with the Boss's ChatGPT account. Model: **gpt-6.1-sol**, reasoning effort **high**. Tested: it generated a cartoon card frame PNG (1254x1254, white background, no transparency).

## Always use it (Boss 2026-11-11)
Every 2D image task goes to one of the agents below, and they make the image with Codex, always. The PO does not draw images some other way.

## Who may use it
Image-making agents with a Bash tool: `art-director`, `character-artist`, `ux-ui-designer`, `ui-programmer`, `technical-artist`, `tech-artist`. Everyone else asks the PO.

## The command (one image per call)
```bash
codex exec --ephemeral --skip-git-repo-check -m gpt-6.1-sol -c model_reasoning_effort=high \
  -s workspace-write -C "C:/Users/wanwi/AppData/Local/Temp/zorx_codex_work" -o "C:/Users/wanwi/AppData/Local/Temp/zorx_codex_work/<name>_last.txt" \
  "<prompt: what to draw, style, size, file name to save in the current folder, reply with the file path only>"
```
- **Run Codex from the EMPTY folder `C:/Users/wanwi/AppData/Local/Temp/zorx_codex_work` (outside the repo).** Codex reads parent folders (it was seen reading CLAUDE.md, AI_SYNC.md, PROGRESS.md when run inside the repo), so never run it inside the repo. Afterwards copy the results into `art_source/codex_review/` (gitignored, hidden from Godot by `art_source/.gdignore`) and clean the work folder. Never point `-C` at the project root, never use `danger-full-access` or `--dangerously-bypass-approvals-and-sandbox`.
- Name files `<topic>_<what>_v<N>.png` and keep every version.

## Rules
1. **Add to every prompt: "use the image generation tool, not code"** (a run without it drew a flat image with code and was rejected).
1. **Send only what the image needs:** a text description and, if useful, a reference image (`-i`) that is already public game art. Never send source code, tokens, keys, account data, user data or private documents. Codex is an outside service.
2. **Style (Boss):** cartoon, thick ink outlines, flat cel colour, rounded chunky shapes. No realistic metal, engraving or dark gothic style. Landscape UI.
3. **Transparency is not guaranteed.** Ask for a flat chroma-key background (for example pure #00FF00) when a cut-out is needed and tell the PO it still needs cleaning.
4. **Review first, never auto-import.** Do not copy anything into `art/` or reference it from a scene until the PO reports that the Boss accepted it. Report the path, the prompt you used, and what is wrong with it.
5. **Use sparingly:** a few tries per asset, one image per call. Each call uses the Boss's ChatGPT quota.
6. Report only to the PO, in English (the normal reporting-line rule).

## Quota / rate limit (Boss 2026-11-13)
If a Codex call fails for usage, quota or rate limits: stop generating at once, do not retry in a loop, and report to the PO the exact error text, the reset time Codex gives (convert to Bangkok time, UTC+7) and how many images were finished before the limit. The PO tells the Boss when it resets.

