"""Author the contract's 12 clips. Run in Blender 4.2 LTS from the repo root.

Angles are source-space pitch/yaw/roll degrees. Pose Mode keys only; no rig,
geometry, UV, weight, object transform or material edits. Loop seams and state
handoffs are checked after native sampled export and source-basis conversion.
"""
import argparse
import math
from pathlib import Path
import sys
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from clip_pipeline import Rig, WORK, write_report, matrix_error, positions

TAU = math.tau


def ease(t):
    t = max(0, min(1, t))
    return t * t * t * (t * (t * 6 - 15) + 10)


def pulse(t, a, b):
    return math.sin(math.pi * (t - a) / (b - a)) ** 2 if a < t < b else 0


def blend(a, b, amount):
    return {key: tuple(x + (y - x) * amount for x, y in zip(a.get(key, (0, 0, 0)), b.get(key, (0, 0, 0)))) for key in a.keys() | b.keys()}


def add(pose, bone, pitch=0, yaw=0, roll=0):
    pose[bone] = tuple(a + b for a, b in zip(pose.get(bone, (0, 0, 0)), (pitch, yaw, roll)))


SIT = {
    "skl_root": (-24, 0, 0), "root_location": (0, -0.61, 0),
    "head": (18, 0, 0), "tail2": (22, 0, 0), "tail3": (28, 0, 0),
    "Lleg2": (-125, 0, 0), "Rleg2": (-125, 0, 0),
    "Lfoot1": (75, 0, 0), "Rfoot1": (75, 0, 0),
    "Lfoot2": (74, 0, 0), "Rfoot2": (74, 0, 0),
    "Larm2": (18, 0, 0), "Rarm2": (18, 0, 0),
    "Lhand1": (6, 0, 0), "Rhand1": (6, 0, 0),
}
LIE = {
    "root_location": (0, -0.76, 0), "head": (62, 0, 0),
    "neck": (3, 0, 0), "tail2": (5, 14, 0), "tail3": (10, 12, 0),
    "Lleg2": (-145, 0, 0), "Rleg2": (-145, 0, 0),
    "Lfoot1": (70, 0, 0), "Rfoot1": (70, 0, 0),
    "Lfoot2": (75, 0, 0), "Rfoot2": (75, 0, 0),
    "Larm2": (-65, 0, 0), "Rarm2": (-65, 0, 0),
    "Lhand1": (20, 0, 0), "Rhand1": (20, 0, 0),
    "Lhand2": (45, 0, 0), "Rhand2": (45, 0, 0),
}


def idle(t):
    p = {"chest": (0.45 * math.sin(TAU * t), 0, 0),
         "head": (0.8 * math.sin(TAU * t), 2 * math.sin(TAU * t), 0),
         "tail2": (0, 3 * math.sin(TAU * t), 0)}
    add(p, "Lear1", pitch=-12 * pulse(t, .36, .48))
    add(p, "Rear1", pitch=-8 * pulse(t, .43, .56))
    return p


def sit(t):
    return blend({}, SIT, ease((t - .08) / .70))


def sit_idle(t):
    p = dict(SIT)
    add(p, "chest", pitch=.4 * math.sin(TAU * t))
    add(p, "head", pitch=.7 * math.sin(TAU * t), yaw=2 * math.sin(TAU * t))
    add(p, "tail2", yaw=4 * math.sin(TAU * t))
    add(p, "Lear1", pitch=-9 * pulse(t, .60, .73))
    return p


def lie_down(t):
    return blend(SIT, LIE, ease((t - .08) / .72))


def sleep(t):
    p = dict(LIE)
    add(p, "chest", pitch=.3 * math.sin(TAU * t))
    add(p, "head", pitch=.5 * math.sin(TAU * t))
    return p


def eat(t):
    chew = .5 - .5 * math.cos(TAU * 4 * t)
    p = {"neck": (5, 0, 0), "head": (48 + 2 * chew, 0, 0),
         "mouth": (12 * chew, 0, 0), "tail2": (0, 2 * math.sin(TAU * t), 0)}
    return p


def bark(t):
    opening = pulse(t, .16, .34) + pulse(t, .48, .66)
    return {"mouth": (18 * opening, 0, 0), "head": (-7 * opening, 0, 0),
            "neck": (-1.5 * opening, 0, 0), "chest": (-.7 * opening, 0, 0),
            "Lear1": (-7 * opening, 0, 0), "Rear1": (-7 * opening, 0, 0)}


def fetch(t):
    dip = ease((t - .06) / .3) * (1 - ease((t - .61) / .24))
    open_ = ease((t - .21) / .13) * (1 - ease((t - .45) / .09))
    return {"head": (57 * dip, 0, 0), "neck": (5 * dip, 0, 0),
            "mouth": (15 * open_, 0, 0), "tail2": (0, 8 * math.sin(TAU * 2 * t) * math.sin(math.pi * t) ** 2, 0)}


def happy(t):
    envelope = math.sin(math.pi * t) ** 2
    wag = math.sin(TAU * 4 * t) * envelope
    bounce = .12 * (pulse(t, .16, .38) + pulse(t, .48, .70))
    return {"root_location": (0, bounce, 0), "tail2": (0, 24 * wag, 0),
            "tail3": (0, 12 * math.sin(TAU * 4 * t - .4) * envelope, 0),
            "head": (-3 * envelope, 4 * math.sin(TAU * t) * envelope, 0),
            "Lear1": (-8 * envelope, 0, 0), "Rear1": (-8 * envelope, 0, 0)}


def stretch(t):
    # Sleeping pose -> forequarters extended -> standing; held neutral ending.
    extended = dict(LIE)
    extended.update({"head": (18, 0, 0), "neck": (2, 0, 0),
                     "root_location": (0, -.45, 0), "skl_root": (9, 0, 0),
                     "Larm2": (-66, 0, 0), "Rarm2": (-66, 0, 0),
                     "Lhand1": (27, 0, 0), "Rhand1": (27, 0, 0),
                     "Lhand2": (30, 0, 0), "Rhand2": (30, 0, 0),
                     "Lleg2": (-65, 0, 0), "Rleg2": (-65, 0, 0),
                     "Lfoot1": (30, 0, 0), "Rfoot1": (30, 0, 0),
                     "Lfoot2": (26, 0, 0), "Rfoot2": (26, 0, 0)})
    if t < .38:
        return blend(LIE, extended, ease(t / .32))
    return blend(extended, {}, ease((t - .48) / .38))


def wrap(angle):
    return (angle + 180) % 360 - 180


def gait(rig, t, running=False):
    # Four-beat walk, diagonal-pair trot/run. No root translation or rotation.
    phases = {"Larm": 0, "Rarm": .5, "Lleg": .5 if running else .75, "Rleg": 0 if running else .25}
    p = {"head": ((2 if running else 1) * math.sin(TAU * 2 * t), 0, 0)}
    for limb, offset in phases.items():
        phase = TAU * (t + offset)
        p[limb + "1"] = ((7 if running else 4) * math.cos(phase), 0, 0)
    rig.set_pose(p)
    anchors = {limb: rig.arm.pose.bones[limb + "2"].matrix.translation.copy() for limb in phases}
    for limb, offset in phases.items():
        fore = "arm" in limb
        mid = limb[0] + ("hand1" if fore else "foot1")
        toe = limb[0] + ("hand2" if fore else "foot2")
        joint = limb + "2"
        phase = TAU * (t + offset)
        stride = (.24 if fore else .32) if running else (.17 if fore else .23)
        lift = (.18 if running else .12) * max(0, math.sin(phase)) ** 2
        target = rig.rest[toe].translation.copy()
        target.z += stride * math.cos(phase)
        target.y += lift + .025
        anchor = anchors[limb]
        delta = target - anchor
        v1 = rig.rest[mid].translation - rig.rest[joint].translation
        v2 = rig.rest[toe].translation - rig.rest[mid].translation
        l1, l2 = v1.length, v2.length
        distance = math.sqrt(delta.y ** 2 + delta.z ** 2)
        # A small bend reserve prevents the straight-knee IK singularity.
        distance = max(abs(l1 - l2) + 1e-5, min(.96 * (l1 + l2), distance))
        direction = math.atan2(delta.y, delta.z)
        bend = math.acos(max(-1, min(1, (l1*l1 + distance*distance - l2*l2) / (2*l1*distance))))
        alpha = direction + (bend if fore else -bend)
        beta = math.atan2(distance * math.sin(direction) - l1 * math.sin(alpha), distance * math.cos(direction) - l1 * math.cos(alpha))
        parent_pitch = p[limb + "1"][0]
        pitch2 = wrap(-math.degrees(alpha - math.atan2(v1.y, v1.z)) - parent_pitch)
        pitch_mid = wrap(-math.degrees(beta - math.atan2(v2.y, v2.z)) - parent_pitch - pitch2)
        p[joint] = (pitch2, 0, 0)
        p[mid] = (pitch_mid, 0, 0)
        p[toe] = (-parent_pitch - pitch2 - pitch_mid, 0, 0)
    p["tail2"] = (8, (7 if running else 4) * math.sin(TAU * t), 0)
    p["tail3"] = (12, 3 * math.sin(TAU * t), 0)
    return p


def build(render=True):
    rig = Rig()
    specs = [
        ("shiba_idle_loop", 120, idle, True, [1, 31, 54]),
        ("shiba_sit", 60, sit, False, [1, 30, 60]),
        ("shiba_sit_idle_loop", 120, sit_idle, True, [1, 31, 82]),
        ("shiba_lie_down", 75, lie_down, False, [1, 38, 75]),
        ("shiba_sleep_loop", 150, sleep, True, [1, 39, 76]),
        ("shiba_eat_loop", 90, eat, True, [1, 12, 23]),
        ("shiba_walk_loop", 40, lambda t: gait(rig, t), True, [1, 11, 21]),
        ("shiba_run_loop", 28, lambda t: gait(rig, t, True), True, [1, 8, 15]),
        ("shiba_bark", 60, bark, False, [1, 16, 35]),
        ("shiba_fetch_pickup", 75, fetch, False, [1, 31, 41]),
        ("shiba_happy", 75, happy, False, [1, 24, 45]),
        ("shiba_stretch", 105, stretch, False, [1, 41, 105]),
    ]
    reports, channels = [], {}
    for name, frames, fn, looping, previews in specs:
        action = rig.action(name, frames, fn, floor_contact=name not in {"shiba_walk_loop", "shiba_run_loop"})
        report, samples = rig.export(name)
        if looping:
            error = max(matrix_error(ms[0], ms[-1]) for ms in samples.values())
            assert error < 2e-5, ("Loop discontinuity", name, error)
            report["loop_endpoint_max_error"] = error
        if name in {"shiba_walk_loop", "shiba_run_loop"}:
            rest = samples["skl_root"][0].translation
            assert max((m.translation - rest).length for m in samples["skl_root"]) < 1e-6
            report["root_translation_range"] = 0
        report["loop"] = looping
        reports.append(report)
        channels[name] = samples
        print("CLIP_PASS", name, frames, flush=True)
    transitions = [("shiba_sit", "shiba_sit_idle_loop"),
                   ("shiba_sit_idle_loop", "shiba_lie_down"),
                   ("shiba_lie_down", "shiba_sleep_loop"),
                   ("shiba_sleep_loop", "shiba_stretch"),
                   ("shiba_stretch", "shiba_idle_loop")]
    handoffs = []
    for first, next_ in transitions:
        error = max(matrix_error(channels[first][b][-1], channels[next_][b][0]) for b in rig.nodes)
        assert error < 2e-5, ("State handoff discontinuity", first, next_, error)
        handoffs.append(dict(from_clip=first, to_clip=next_, max_matrix_error=error))
    rig.activate(rig.actions["shiba_idle_loop"])
    rig.save(WORK / "shiba_clips.blend", selected_bone="head")
    write_report(WORK / "clips_validation.json", dict(clips=reports, state_handoffs=handoffs,
                                                      mac_playback="Pending Mac validation"))
    if render:
        directory = WORK / "qa_frames"
        directory.mkdir(exist_ok=True)
        for name, frames, fn, looping, previews in specs:
            rig.activate(rig.actions[name])
            for frame in previews:
                rig.render(directory / f"{name}_{frame:03d}.png", frame, side_view=True)
            print("PREVIEW_DONE", name, flush=True)
        proof_directory = WORK / "previews"
        proof_directory.mkdir(exist_ok=True)
        for name, frame in [("shiba_sit", 60), ("shiba_sleep_loop", 1),
                            ("shiba_walk_loop", 11), ("shiba_stretch", 41)]:
            rig.activate(rig.actions[name])
            rig.render(proof_directory / (name + ".png"), frame, side_view=True)


if __name__ == "__main__":
    if "--tier2" in sys.argv:
        from tier2_clips import build_tier2
        build_tier2(render="--no-render" not in sys.argv)
    else:
        build(render="--no-render" not in sys.argv)
