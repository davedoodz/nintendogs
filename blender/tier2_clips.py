"""Second-tier poses; invoked through author_clips.py -- --tier2.

Accepted base clips are read for entry/exit pose checks and never regenerated.
"""
import hashlib
import math
from author_clips import SIT, LIE, TAU, ease, pulse, blend, add, gait, root_motion
from clip_pipeline import Rig, WORK, CLIPS, matrix_error, read_clip_channels, write_report

# Frames, loop flag, incoming state's first frame, outgoing state's first frame.
SPECS = {
    "shiba_stand_from_sit": (45, False, "shiba_sit_idle_loop", "shiba_idle_loop"),
    "shiba_sit_from_lie": (60, False, "shiba_sleep_loop", "shiba_sit_idle_loop"),
    "shiba_wake": (60, False, "shiba_sleep_loop", "shiba_sit_idle_loop"),
    "shiba_beg_loop": (90, True, None, None),
    "shiba_yawn": (60, False, "shiba_idle_loop", "shiba_idle_loop"),
    "shiba_scratch": (75, False, "shiba_sit_idle_loop", "shiba_sit_idle_loop"),
    "shiba_look_around_loop": (150, True, None, None),
    "shiba_drink_loop": (60, True, None, None),
    "shiba_alert": (30, False, "shiba_idle_loop", "shiba_idle_loop"),
    "shiba_pet_react": (75, False, "shiba_idle_loop", "shiba_idle_loop"),
    "shiba_shake": (45, False, "shiba_idle_loop", "shiba_idle_loop"),
    "shiba_fetch_carry_loop": (40, True, None, None),
}


def window(t, start, peak, release, end):
    return ease((t - start) / (peak - start)) * (1 - ease((t - release) / (end - release)))


def stand_from_sit(t):
    return blend(SIT, {}, ease((t - .06) / .76))


def sit_from_lie(t):
    return blend(LIE, SIT, ease((t - .06) / .76))


def wake(t):
    raised = dict(LIE, head=(15, 0, 0), neck=(1.5, 0, 0))
    p = blend(LIE, raised, ease(t / .24)) if t < .24 else blend(raised, SIT, ease((t - .24) / .58))
    add(p, "Lear1", pitch=-12 * pulse(t, .27, .46))
    add(p, "Rear1", pitch=-9 * pulse(t, .36, .54))
    return p


def beg(t):
    p = dict(SIT)
    p["head"] = (-6 + 1.8 * math.sin(TAU * 2 * t), 2 * math.sin(TAU * t), 0)
    p["Lear1"], p["Rear1"] = (-4, 0, 0), (-4, 0, 0)
    add(p, "tail2", yaw=4 * math.sin(TAU * t))
    return p


def yawn(t):
    opening = window(t, .10, .38, .59, .86)
    return {"mouth": (30 * opening, 0, 0), "head": (-20 * opening, 0, 0),
            "neck": (-2 * opening, 0, 0), "Lear1": (-10 * opening, 0, 0),
            "Rear1": (-10 * opening, 0, 0)}


def scratch(t):
    lift = window(t, .06, .26, .69, .92)
    strokes = math.sin(TAU * 6 * t) * window(t, .26, .34, .62, .72)
    scratching = dict(SIT)
    scratching.update({"head": (18, 35, -24), "Lleg1": (0, 0, 5),
                       "Lleg2": (-190, 0, 35), "Lfoot1": (65, 0, -12),
                       "Lfoot2": (25, 0, 0)})
    p = blend(SIT, scratching, lift)
    add(p, "Lfoot1", pitch=9 * strokes)
    add(p, "Lfoot2", pitch=-7 * strokes)
    add(p, "Lear1", pitch=-5 * strokes)
    return p


def look_around(t):
    stops = [(0, 0), (.08, 0), (.23, -28), (.38, -28),
             (.61, 32), (.76, 32), (.93, 0), (1, 0)]
    yaw = 0
    for (a, av), (b, bv) in zip(stops, stops[1:]):
        if a <= t <= b:
            yaw = av + (bv - av) * ease((t - a) / (b - a))
            break
    return {"head": (0, yaw, 0), "Lear1": (-5 * pulse(t, .28, .37), 0, 0)}


def drink(t):
    lap = .5 - .5 * math.cos(TAU * 6 * t)
    return {"head": (55 + .8 * lap, 0, 0), "neck": (5, 0, 0),
            "mouth": (8 * lap, 0, 0)}


def alert(t):
    attention = window(t, .02, .24, .48, .90)
    return {"head": (-4 * attention, 32 * attention, 0),
            "Lear1": (8 * attention, 0, -3 * attention),
            "Rear1": (8 * attention, 0, 3 * attention)}


def pet_react(t):
    response = window(t, .05, .26, .62, .94)
    return {"head": (6 * response, 8 * response, -15 * response),
            "Lear1": (-18 * response, 0, -4 * response),
            "Rear1": (-18 * response, 0, 4 * response),
            "tail2": (0, 18 * math.sin(TAU * 3 * t) * response, 0),
            "tail3": (0, 8 * math.sin(TAU * 3 * t - .4) * response, 0)}


def shake(t):
    envelope = window(t, .03, .19, .69, .94)
    wave = math.sin(TAU * 4 * t)
    return {"head": (0, 12 * wave * envelope, 0),
            "chest": (0, -2 * math.sin(TAU * 4 * t - .4) * envelope, 0),
            "waist": (0, 1.8 * math.sin(TAU * 4 * t - .9) * envelope, 0),
            "Lear1": (-4 * envelope, 0, 9 * wave * envelope),
            "Rear1": (-4 * envelope, 0, 9 * wave * envelope),
            "tail2": (0, 6 * math.sin(TAU * 4 * t - 1) * envelope, 0)}


def carry(rig, t):
    p = gait(rig, t)
    p["head"] = (-10 + .6 * math.sin(TAU * 2 * t), 0, 0)
    p["mouth"] = (0, 0, 0)
    return p


def build_tier2(render=True):
    rig = Rig()
    base_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in CLIPS.glob("*.dae") if p.stem not in SPECS}
    references = {name: read_clip_channels(CLIPS / (name + ".dae"))
                  for name in {"shiba_idle_loop", "shiba_sit_idle_loop", "shiba_sleep_loop", "shiba_walk_loop"}}
    poses = [stand_from_sit, sit_from_lie, wake, beg, yawn, scratch,
             look_around, drink, alert, pet_react, shake, lambda t: carry(rig, t)]
    reports, handoffs = [], []
    for (name, (frames, looping, incoming, outgoing)), fn in zip(SPECS.items(), poses):
        rig.action(name, frames, fn, floor_contact=name != "shiba_fetch_carry_loop")
        report, samples = rig.export(name, joint_limit=7)
        report["loop"] = looping
        if looping:
            error = max(matrix_error(ms[0], ms[-1]) for ms in samples.values())
            assert error < 2e-5, (name, "loop", error)
            report["loop_endpoint_max_error"] = error
        else:
            for state, index, endpoint in [(incoming, 0, "entry"), (outgoing, -1, "handoff")]:
                error = max(matrix_error(samples[b][index], references[state][b][0]) for b in rig.nodes)
                assert error < 2e-5, (name, endpoint, state, error)
                handoffs.append(dict(clip=name, endpoint=endpoint, state=state, max_matrix_error=error))
        if name == "shiba_fetch_carry_loop":
            excluded = {"head", "mouth"}
            gait_error = max(matrix_error(a, b) for joint in rig.nodes if joint not in excluded
                             for a, b in zip(samples[joint], references["shiba_walk_loop"][joint]))
            assert gait_error < 2e-5
            report["accepted_walk_channel_max_error"] = gait_error
            report.update(root_motion(samples))
        reports.append(report)
        print("TIER2_PASS", name, frames, flush=True)
    assert base_hashes == {name: hashlib.sha256((CLIPS / name).read_bytes()).hexdigest() for name in base_hashes}
    rig.activate(rig.actions["shiba_stand_from_sit"])
    rig.save(WORK / "shiba_clips_tier2.blend", selected_bone="head")
    write_report(WORK / "tier2_validation.json", dict(clips=reports, state_handoffs=handoffs,
                                                     accepted_assets_unchanged_sha256=base_hashes,
                                                     mac_playback="Pending second-tier Mac review"))
    if render:
        directory = WORK / "qa_frames"
        directory.mkdir(exist_ok=True)
        for name, (frames, _, _, _) in SPECS.items():
            rig.activate(rig.actions[name])
            for frame in [1, 1 + frames // 3, 1 + 2 * frames // 3, frames]:
                rig.render(directory / f"{name}_{frame:03d}.png", frame, side_view=True)
            print("TIER2_PREVIEW", name, flush=True)
        for name, frame in [("shiba_sit_from_lie", 34), ("shiba_beg_loop", 23),
                            ("shiba_shake", 18), ("shiba_pet_react", 30), ("shiba_scratch", 37),
                            ("shiba_fetch_carry_loop", 7)]:
            rig.activate(rig.actions[name])
            rig.render(WORK / "previews" / (name + ".png"), frame, side_view=True)
        rig.activate(rig.actions["shiba_shake"])
        for frame in [14, 19]:
            rig.render(WORK / "previews" / f"shiba_shake_{frame:03d}.png", frame, side_view=True)
