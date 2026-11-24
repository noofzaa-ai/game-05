# Steam release plan (draft, 2026-11-15)

Boss decisions: plan first; online with the existing Nakama server; login with Steam.
Boss's personal Steam account is a player account only. Selling needs a new Steamworks partner account.

## Status
- 2026-11-15: Boss registered Steamworks. Tax/identity (TaxIdentity by Lilaham) is pending verification, up to 45 business days, cannot be rushed. App fee and App ID come after it. Team works with App ID 480 meanwhile.

- 2026-11-15 Boss decision: Google/Guest login will be removed (no account linking, Steam accounts start fresh). Current staging is only for friends to give feedback, as the first step toward Steam Early Access. So the target is Steam Early Access, not a full launch. Staging keeps Google/Guest until the Steam login works (not yet decided: remove at once or after friends' testing ends).

## A. Boss must do (cannot be done by the team)
1. Register at partner.steamgames.com (new Steamworks account, not the personal one; use the Steam login as the owner).
2. Tax interview, bank account, identity check (Thailand). Can take days to weeks. Start first.
3. Pay the $100 app fee per game. Steam gives the App ID.
4. Decide: store price, release date, age rating answers, game name.

## B. Team work (blocked items marked)
| # | Work | Owner | Notes |
|---|------|-------|-------|
| 1 | Windows export preset + desktop smoke run | tech-artist | game is Web-only now (`export_presets.cfg` has only Web). Needs Godot export templates. |
| 2 | Desktop performance/input pass (mouse/keyboard, fullscreen, window sizes, settings screen) | ui-programmer, tech-artist | web touch layout vs desktop. |
| 3 | GodotSteam (GDExtension for the current Godot version) | gameplay-programmer | pin version; test with App ID 480 first. Blocked on nothing. |
| 4 | Steam login: client sends a Steam auth session ticket; server verifies via Steam Web API and maps the SteamID to a Nakama account | network-programmer, security-engineer | Nakama has no built-in Steam auth for custom flow: use custom auth id from server-verified ticket. Needs Steam publisher Web API key (blocked on A3). Account linking with existing Google/Guest accounts: ASK Boss. |
| 5 | Drop web-only flow on Steam build (Turnstile, landing, browser login) | gameplay-programmer | keep web build unchanged. |
| 6 | Achievements, cloud save (optional), overlay/rich presence (optional) | gameplay-programmer | not required for launch. |
| 7 | Store page: capsule art (several sizes), screenshots, trailer, description, tags | art-director, writer | art via Codex workflow, Boss reviews before use. Store page must be live "coming soon" at least 2 weeks before release. |
| 8 | SteamPipe depot + build scripts, branches (default/beta) | release-manager | uses steamcmd, needs A3. |
| 9 | Steam build review (Valve ~3-5 days) and store page review | release-manager | submit early. |
| 10 | Server capacity/load test for launch day on k3s production | tech-artist, network-programmer | production namespace exists. |
| 11 | Privacy policy + EULA text (online accounts, data) | writer, security-engineer | required by store page. |

## C. Open questions for Boss
- Link existing Google/Guest accounts to Steam accounts, or Steam accounts start fresh?
- Price and free-to-play vs paid? (changes need for server cost/anti-abuse)
- Web version stays alongside Steam?
- Languages on the store page (Thai/English)?

## D. Suggested order
A (Boss, start now) -> B3 + B1 with App ID 480 in parallel -> B4 -> B2/B5 -> B7 -> B8 -> B9 -> B10 -> release.
