# Player feedback

Camp has a top-right Feedback button and a menu entry. Composer uses the camp's
CSS-aware UI scale, multi-line input and mobile virtual keyboard. It retains text
on failure, retries the same request ID, and reports success only after storage ACK.

`zorx_feedback_v1` requires an authenticated permitted account. Server derives the
user ID, character name and timestamp; only message/platform/build revision come
from the client. Three to2000 characters, one new submission per60s per account.
A private CAS quota and feedback record are written atomically. Retries are
idempotent, conflicting reuse rejected, both collections blocked by storage hooks.
No player can list feedback. Feedback messages are not written into application logs.

Admin: `https://zorx.daiyooo.com/admin` → **Feedback จากผู้เล่น**. Existing verified
Google admin email array and private service-token boundary apply. Newest first,
30 entries per page, keyset pagination; messages render as plain text (no HTML).
No extra admin emails or permissions are added. Collection `zorx_feedback_v1` is
persisted in Nakama/Postgres and included in normal DB backups.

Game/runtime sources are in this repo. Admin landing sources remain in sibling
`../zorx_web`; `server/landing/feedback-admin.patch` preserves the corresponding
public-source changes without copying `.env` or committing the parent workspace.
Apply that patch to the pre-feedback landing source when reconstructing the change;
current sibling source already contains it. Existing landing builder allowlists it.

Tests cover auth, identity spoofing, storage privacy/hooks, retry, quota, payload
bounds, admin pagination/access, actual Nakama/Postgres submission-to-admin query,
and landscape/portrait composer bounds. Physical Safari keyboard acceptance is manual.

Release2026-10-18: API/Web/landing `feedback-5031d89` active in zorx-staging.
Public Web build `597f19eaf567`; anonymous admin feed401, registered feedback RPC
requires authentication; existing admin email configuration retained. Full Godot2419/0
with empty stderr, Python58/0, TS12groups and actual isolated feedback/admin SQL pass.
