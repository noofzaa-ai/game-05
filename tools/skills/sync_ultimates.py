#!/usr/bin/env python3
"""Writes data/combat/ultimates.json from the imported skill packs.

    python3 tools/skills/sync_ultimates.py            # rewrite the data file
    python3 tools/skills/sync_ultimates.py --check     # only say whether it is up to date

Every number here is copied from the pack's own art/skills/<type>/<skill>/skill.json (hit times,
range in body lengths, dash window, throw/recall times, when locomotion is released), so the
gameplay data can never drift from the animation. The game turns these seconds into move frames in
logic/combat_data_loader.gd; tests/test_ultimates.gd re-reads the packs and compares.
Hand-made parts of the file (which skill each weapon type casts by default, and the tuning knobs at
the top) are kept when the file is rewritten.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKILLS = os.path.join(ROOT, "art", "skills")
MANIFEST = os.path.join(SKILLS, "skill_manifest.json")
OUT = os.path.join(ROOT, "data", "combat", "ultimates.json")

# Which pack a weapon type casts when nothing else picks one. Items have no "element" field yet
# (data/items/catalog.json: only weapon_type), so these are a design choice, written down in the
# file's comment: the weapon's skill name in data/combat/weapons.json decides.
DEFAULTS = {
    "blade": "blade_solar_slam_ultimate",         # fire: current airborne pose + owner camera
    "dagger": "dagger_shadow_extraction_ultimate",  # "Shadow Hunt": the shadow pack, cast in place
    "spear": "spear_thunder_sky_throw_ultimate",  # approved New v1 lightning throw / recall
    "hammer": "hammer_ground_drag_ultimate",      # current drag / side lift / earth blast
}
KNOBS = {
    "body_length_m": 1.7,
    "min_active_ticks": 6,
    "dash_front_body_lengths": 0.35,
    # The camera of a pack that brings none: one small shake when its last hit lands.
    "camera_default": {"shake_strength_m": 0.035, "shake_seconds": 0.2},
}

# ---- Camera ----------------------------------------------------------------------------------
# The packs describe their camera in three places, all read here:
#  * skill.json "camera" with kind "blade_slam_pose" (the 4 blade slams): a close front shot that
#    drifts round the leaping caster; numbers in the file, motion in the demo's blade_slam_camera.gd.
#  * skill.json "camera" without a kind (dagger shadow extraction): timings and a darker view tone
#    in the file; the two shot positions are constants of the demo's shadow_extraction_camera.gd.
#  * weapon_delivery "throw_recall" + camera_owner_only (the 4 spear sky throws): the whole move is
#    in the demo's spear_sky_throw_camera.gd / spear_throw_camera.gd, started by combat_camera.gd
#    with apex 0.40 s, pose end 1.40 s, return end 2.96 s and the pack's attack.range_m.
#  * the elemental presentation scripts (shared/*_presentation.gd) shake the camera when the
#    flight lands (flight.arrival_time_s): amplitude and fade below, per script.
# Positions are metres of the pack's body (reference_body_height_m) in the caster's frame:
# [right, up, forward]; the game scales them to its own body. "game" = the player's chosen angle.
PRESENTATION_SHAKE = {  # script -> (strength m, fade s), copied from each script's _process
    "earth_slam_presentation.gd": (0.064, 0.28),
    "solar_slam_presentation.gd": (0.052, 0.26),
    "thunder_slam_presentation.gd": (0.049, 0.24),
    "tidal_slam_presentation.gd": (0.042, 0.23),
}
SHADOW_SHOT = {  # shadow_extraction_camera.gd present_cast()
    "start": [2.2, 1.78, 4.55], "end": [-0.46, 1.64, 4.40], "look": [0.0, 1.0, -0.34],
    "fov_start": 42.0, "fov_end": 38.0, "ambient": 0.66,
}
SKY_THROW = {  # spear_sky_throw_camera.gd + spear_throw_camera.gd + combat_camera.gd begin_cast
    "apex_s": 0.40, "pose_end_s": 1.40, "pose_lead_s": 0.18,
    "pose_look": [-0.08, 2.70, 0.0],
    "wide_s": 1.84, "wide_hold_s": 2.04, "receive_s": 2.38, "receive_hold_s": 2.64, "return_end_s": 2.96,
    "wide_fov": 58.0, "receive_fov": 48.0,
    "reference_range_m": 3.013466552,
    "receive": [3.4, 3.4, -5.0], "receive_look": [-0.12, 1.0, 0.4],
}


def _smooth(a, b, t):
    if b <= a:
        return 1.0 if t >= b else 0.0
    x = min(1.0, max(0.0, (t - a) / (b - a)))
    return x * x * (3.0 - 2.0 * x)


def _r(values):
    return [round(float(v), 4) for v in values]


def _blade_slam_keys(cam):
    import math
    def pose(t):
        drift = _smooth(cam["pose_start_s"], cam["pose_end_s"], t)
        lerp = lambda a, b: a + (b - a) * drift
        yaw = math.radians(lerp(cam["yaw_start_deg"], cam["yaw_end_deg"]))
        radius = lerp(cam["radius_start_m"], cam["radius_end_m"])
        height = lerp(cam["height_start_m"], cam["height_end_m"])
        return {"shot": "frame", "position_m": _r([math.sin(yaw) * radius, height, math.cos(yaw) * radius]),
                "look_m": _r([0.0, cam["focus_height_m"], 0.05]),
                "fov_deg": round(lerp(cam["fov_start_deg"], cam["fov_end_deg"]), 3)}
    hold = min(cam["pose_end_s"], cam["return_start_s"])
    keys = [{"time_s": cam["enter_start_s"], "shot": "game"},
            dict(time_s=cam["enter_end_s"], **pose(cam["enter_end_s"])),
            dict(time_s=hold, **pose(hold)),
            {"time_s": cam["return_end_s"], "shot": "game"}]
    return keys


def _shadow_keys(cam):
    s = SHADOW_SHOT
    frame = lambda p, fov: {"shot": "frame", "position_m": _r(p), "look_m": _r(s["look"]), "fov_deg": fov}
    return [{"time_s": 0.0, "shot": "game"},
            dict(time_s=cam["pose_start_s"], **frame(s["start"], s["fov_start"])),
            dict(time_s=cam["pose_end_s"], **frame(s["end"], s["fov_end"])),
            dict(time_s=cam["return_start_s"], **frame(s["end"], s["fov_end"])),
            {"time_s": cam["return_end_s"], "shot": "game"}]


def _sky_throw_keys(range_m):
    s = SKY_THROW
    extra = max(0.0, range_m - s["reference_range_m"])
    wide = {"shot": "frame", "position_m": _r([8.0 + extra * 0.4, 7.0 + extra * 0.4, -8.0]),
            "look_m": _r([0.0, 0.9, range_m * 0.53]), "fov_deg": s["wide_fov"]}
    receive = {"shot": "frame", "position_m": _r(s["receive"]), "look_m": _r(s["receive_look"]), "fov_deg": s["receive_fov"]}
    orbit = lambda yaw, dist, height, fov: {"shot": "orbit", "yaw_deg": yaw, "distance_scale": dist,
                                           "height_scale": height, "look_m": _r(s["pose_look"]), "fov_scale": fov}
    return [{"time_s": round(s["apex_s"] - s["pose_lead_s"], 4), "shot": "game"},
            dict(time_s=s["apex_s"], **orbit(-12.0, 0.90, 0.80, 0.90)),
            dict(time_s=s["pose_end_s"], **orbit(-34.0, 0.86, 0.72, 0.86)),
            dict(time_s=s["wide_s"], **wide),
            dict(time_s=s["wide_hold_s"], **wide),
            dict(time_s=s["receive_s"], **receive),
            dict(time_s=s["receive_hold_s"], **receive),
            {"time_s": s["return_end_s"], "shot": "game"}]


def camera_entry(manifest, events, default):
    """The camera of one pack: keys (shots over the clip), shakes, an optional view tone."""
    cam = manifest.get("camera") or {}
    delivery = manifest.get("weapon_delivery") or {}
    presentation = os.path.basename(str(manifest.get("godot_visual", {}).get("presentation", "")))
    out = {"source": "pack", "owner_only": True, "keys": [], "shakes": []}
    if cam.get("kind") == "hammer_ground_drag":
        out["from"] = "approved hammer_drag_camera.gd + preview_config.json v4"
        out["hammer_drag"] = cam
        out["keys"] = [{"time_s": 0, "shot": "game"}, {"time_s": cam["return_end_s"], "shot": "game"}]
        out["shakes"] = [{"time_s": 3.04, "strength_m": 0.064, "seconds": 0.28}]
    elif cam.get("kind") == "blade_slam_pose":
        out["from"] = "skill.json camera (blade_slam_pose) + demo blade_slam_camera.gd"
        out["keys"] = _blade_slam_keys(cam)
    elif cam and "pose_start_s" in cam:
        out["from"] = "skill.json camera + demo shadow_extraction_camera.gd"
        out["keys"] = _shadow_keys(cam)
        out["tone"] = {
            "brightness": cam.get("brightness", 0.7), "saturation": cam.get("saturation", 0.83),
            "contrast": cam.get("contrast", 1.08), "ambient": SHADOW_SHOT["ambient"],
            "in_start_s": 0.0, "in_end_s": cam["pose_start_s"],
            "out_start_s": cam["return_start_s"], "out_end_s": cam["return_end_s"],
        }
    elif delivery.get("kind") == "throw_recall" and delivery.get("camera_owner_only"):
        out["from"] = "weapon_delivery throw_recall + demo spear_sky_throw_camera.gd"
        out["keys"] = _sky_throw_keys(float(manifest["attack"].get("range_m", SKY_THROW["reference_range_m"])))
    if presentation in PRESENTATION_SHAKE:
        strength, seconds = PRESENTATION_SHAKE[presentation]
        impact = float(manifest.get("flight", {}).get("arrival_time_s", 1.12))
        out["shakes"].append({"time_s": round(impact, 4), "strength_m": strength, "seconds": seconds})
        out["from"] = (out.get("from", "") + " + " if out.get("from") else "") + presentation + " impact shake"
    if not out["keys"] and not out["shakes"]:
        last = events[-1]["time_s"] if events else round(float(manifest["duration_s"]) * 0.5, 4)
        out = {"source": "default", "owner_only": True, "keys": [], "shakes": [
            {"time_s": last, "strength_m": default["shake_strength_m"], "seconds": default["shake_seconds"]}]}
    for key in out["keys"]:
        key["time_s"] = round(float(key["time_s"]), 4)
    return out
COMMENT = (
    "Which skill pack (art/skills/) each weapon type's ultimate uses, and the facts of every pack: "
    "generated by tools/skills/sync_ultimates.py, do not edit the \"skills\" block by hand. "
    "To change what a weapon casts, point its entry in \"defaults\" at another skill of the same "
    "weapon_type; everything else (hit frames, range, dash, how long the move holds the fighter) "
    "follows from the pack. The packs' own rule (art/skills/ultimate_defaults.json) is that an "
    "ultimate always strikes FORWARD, never around the user. body_length_m = 1 body length in game "
    "(the chibi's 1.5067 m without hair x its 1.128 scale); a pack's range_body_lengths times that "
    "is how far the move reaches. min_active_ticks is the shortest hit window a pack with a single "
    "hit event gets (a one-tick window would be unfair to aim). dash_front_body_lengths is how far "
    "past the landing point a forward_dash pack still hits (its box covers the ground it crossed). "
    "defaults: the weapon has no element in the item catalog yet, so the pack is chosen to match "
    "the weapon's skill_names in weapons.json; by_element is ready for the day items carry an "
    "element (element -> pack, per weapon type). "
    "camera (per skill): what the player's camera does while that ultimate is cast, read from the pack "
    "(see the CAMERA notes in tools/skills/sync_ultimates.py) and played by client/ultimate_camera.gd: "
    "keys = shots on the clip's time (game = the player's chosen angle, frame = camera and aim in the "
    "caster's frame [right, up, forward] in pack metres, orbit = the chosen angle turned yaw_deg round "
    "the caster), shakes, an optional darker view tone. source default = the pack brings no camera: "
    "one small shake (camera_default) on its last hit. Special shots are PvE-only and owner-only."
)


def read(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def pack_entry(skill, folder, camera_default):
    """The facts of one pack, as the game needs them."""
    manifest = read(os.path.join(folder, "skill.json"))
    attack = manifest["attack"]
    control = manifest.get("control", {})
    events = []
    for event in manifest.get("gameplay_events", []):
        events.append({
            "time_s": round(float(event["time_s"]), 4),
            "name": str(event["name"]),
            "range_factor": round(float(event["range_factor"]), 4),
        })
    entry = {
        "weapon_type": str(manifest["weapon_type"]),
        "name": str(manifest.get("name", skill["id"])),
        "element": str(manifest.get("element", "")),
        "folder": "res://" + os.path.relpath(folder, ROOT).replace(os.sep, "/") + "/",
        "animation": str(manifest.get("animation", "")),
        "duration_s": round(float(manifest["duration_s"]), 4),
        "caster_motion": str(attack.get("caster_motion", "in_place")),
        "range_body_lengths": round(float(attack["range_body_lengths"]), 4),
        "near_body_lengths": round(float(attack.get("near_body_lengths", 0.05)), 4),
        "width_body_lengths": round(float(attack.get("width_body_lengths", 1.1)), 4),
        "height_body_lengths": round(float(attack.get("height_body_lengths", 1.0)), 4),
        "reference_body_height_m": round(float(attack["reference_body_height_m"]), 6),
        "locomotion_resume_s": round(float(control.get("locomotion_resume_time_s", manifest["duration_s"])), 4),
        "blend_out_s": round(float(control.get("blend_out_s", 0.1)), 4),
        "vfx_end_s": round(float(skill.get("vfx_end_time_s", manifest["duration_s"])), 4),
        "events": events,
    }
    if manifest.get("impact_anchor"):
        entry["impact_anchor"] = manifest["impact_anchor"]
    movement = manifest.get("movement")
    if str(attack.get("caster_motion", "")) == "forward_dash" and movement:
        entry["dash"] = {
            "distance_body_lengths": round(float(movement["distance_body_lengths"]), 4),
            "start_time_s": round(float(movement["start_time_s"]), 4),
            "end_time_s": round(float(movement["end_time_s"]), 4),
        }
    delivery = manifest.get("weapon_delivery")
    if delivery and str(delivery.get("kind", "")) == "throw_recall":
        entry["throw"] = {
            "release_time_s": round(float(delivery["release_time_s"]), 4),
            "catch_time_s": round(float(delivery["catch_time_s"]), 4),
        }
    presentation = str(manifest.get("godot_visual", {}).get("presentation", ""))
    if presentation:
        entry["presentation"] = presentation
    entry["camera"] = camera_entry(manifest, events, camera_default)
    return entry


def build():
    index = read(MANIFEST)
    old = read(OUT) if os.path.exists(OUT) else {}
    skills = {}
    by_element = {}
    camera_default = old.get("camera_default", KNOBS["camera_default"])
    for skill in index["skills"]:
        folder = os.path.join(ROOT, str(skill["manifest_path"]).replace("res://", "").replace("/", os.sep))
        folder = os.path.dirname(folder)
        entry = pack_entry(skill, folder, camera_default)
        skills[str(skill["id"])] = entry
        if entry["element"]:
            by_element.setdefault(entry["weapon_type"], {}).setdefault(entry["element"], str(skill["id"]))
    out = {"version": 1, "_comment": COMMENT}
    for key, value in KNOBS.items():
        out[key] = old.get(key, value)
    out["defaults"] = old.get("defaults", DEFAULTS)
    out["by_element"] = {kind: dict(sorted(by_element.get(kind, {}).items())) for kind in sorted(by_element)}
    out["skills"] = {name: skills[name] for name in sorted(skills)}
    return out


def main():
    built = build()
    text = json.dumps(built, indent="\t", ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        current = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        print("up to date" if current == text else "OUT OF DATE: run tools/skills/sync_ultimates.py")
        return 0 if current == text else 1
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("wrote %s (%d packs)" % (os.path.relpath(OUT, ROOT), len(built["skills"])))
    for kind, skill in sorted(built["defaults"].items()):
        print("  %-7s -> %s" % (kind, skill))
    return 0


if __name__ == "__main__":
    sys.exit(main())
