# World Map — 2026-10-21

Camp warp opens client/world_map_screen.gd, reusing WarpGateScreen destinations and enter(). Journey/Farm select existing content; unseen islands have no hit targets. Original supplied image in art/ui/world_map/archipelago.png, fog is runtime shader client/world_map.gdshader (no baked buttons). Reveals: orange canyon(.175,.535),home crystal(.19,.79). Saturation.62,dense slate fog. Geographic coordinates remain relative to original1448x1086 image; TextureRect contains the full image without cropping and markers use the same fitted rectangle.

Native desktop1600x720 and mobile landscape844x390 captured. All action buttons visible; thumbnail hidden below550px height. No portrait work. Backend selection/economy/security unchanged. Orc still uses existing ink_road/Farm content IDs.

Boss camera: restore previous camera target when timed intro ends,including ultimate interruption and tree exit. Existing coop spectator target continues to update in StageView.

Replacement2026-10-21:1672x941 map,central Orc(.43,.38),home top-left(.105,.15),preview region535,245,420,245. Texture import lossy.82,actual ctex~461KiB. Source image preserved unchanged.
