"""Storyboard petting/call tier, built through author_clips.py -- --tier3."""
import hashlib
import math
from author_clips import SIT, LIE, TAU, blend, add, ease, pulse
from tier2_clips import window
from clip_pipeline import Rig, WORK, CLIPS, matrix_error, read_clip_channels, write_report
from review_render import render_review

# Only previously accepted disk states go in incoming/outgoing. New states are
# compared separately in CHAINS, including held final poses rather than frame 1.
SPECS = {
    'shiba_pet_head_loop': (60, True, None, None),
    'shiba_pet_settle': (90, False, 'shiba_idle_loop', None),
    'shiba_lie_side_loop': (120, True, None, None),
    'shiba_belly_loop': (90, True, None, None),
    'shiba_lie_side_up': (45, False, None, 'shiba_sit_idle_loop'),
    'shiba_call_stun': (15, False, 'shiba_idle_loop', None),
    'shiba_call_curious': (40, False, None, None),
    'shiba_paws_up_enter': (30, False, None, None),
    'shiba_paws_up_loop': (90, True, None, None),
    'shiba_paws_down': (30, False, None, 'shiba_sit_idle_loop'),
}

SIDE_EXTENDED = dict(LIE)
SIDE_EXTENDED.update({
    'skl_root': (0, 0, 75), 'root_location': (0, -1.15, 0),
    'waist': (0, 0, 2), 'neck': (0, 0, 0), 'head': (30, 0, 25),
    'Lleg2': (-40, 0, 18), 'Rleg2': (-40, 0, 70),
    'Lfoot1': (35, 0, 8), 'Rfoot1': (35, 0, 0),
    'Lfoot2': (5, 0, 0), 'Rfoot2': (5, 0, 0),
    'Larm2': (-30, 0, 0), 'Rarm2': (-30, 0, 70),
    'Lhand1': (25, 0, 0), 'Rhand1': (25, 0, 0),
    'Lhand2': (5, 0, 0), 'Rhand2': (5, 0, 0),
    'Lear1': (-12, 0, 0), 'Rear1': (-12, 0, 0), 'mouth': (10, 0, 0),
})
SIDE = blend(SIDE_EXTENDED, {}, .1)
# Keep support placement: relaxing the whole-root roll would lift the side again.
SIDE.update({'skl_root': (0, 0, 75), 'root_location': (0, -1.15, 0),
             'Lear1': (-8, 0, 0), 'Rear1': (-8, 0, 0), 'mouth': (4, 0, 0)})
STUN = {'head': (-5, 0, 0), 'Lear1': (10, 0, 0), 'Rear1': (10, 0, 0)}
PAWS = dict(SIT)
PAWS.update({'spin': (-2, 0, 0), 'head': (-15, 0, 0),
             'Lear1': (6, 0, 0), 'Rear1': (6, 0, 0),
             'Larm2': (-70, 0, 0), 'Rarm2': (-70, 0, 0),
             'Lhand1': (40, 0, 0), 'Rhand1': (40, 0, 0),
             'Lhand2': (-34, 0, 0), 'Rhand2': (-34, 0, 0)})


def pet_head(t):
    # Integer harmonics close the 60-frame loop; face/gaze/breathing are runtime.
    return {'spin': (-1, 0, 0),
            'head': (-10 + 2*math.sin(TAU*t), 0, 8 + 3*math.sin(TAU*t)),
            'Lear1': (-18 + 2*math.sin(TAU*2*t), 0, 0),
            'Rear1': (-18 + 2*math.sin(TAU*2*t), 0, 0),
            'mouth': (12 + 1.5*math.sin(TAU*3*t), 0, 0),
            'tail2': (-8, 0, 0), 'tail3': (-14, 0, 0)}


def pet_settle(t):
    frame = 1 + 89*t
    seated = dict(SIT, head=(-10, 0, 8), mouth=(12, 0, 0),
                  Lear1=(-18, 0, 0), Rear1=(-18, 0, 0))
    if frame <= 30:
        return blend({}, seated, ease((frame-1)/29))
    if frame <= 55:
        p = blend(seated, SIDE_EXTENDED, ease((frame-30)/25))
        p['head'] = tuple(a+(b-a)*ease((frame-40)/15)
                          for a,b in zip(seated['head'], SIDE_EXTENDED['head']))
        return p
    return blend(SIDE_EXTENDED, SIDE, ease((frame-55)/35))


def lie_side(t):
    p = dict(SIDE)
    add(p, 'Lfoot2', pitch=-10*pulse(t, 69/119, 75/119))
    add(p, 'Lear1', pitch=-8*pulse(t, 36/119, 44/119))
    add(p, 'tail3', yaw=4*math.sin(TAU*2*t))
    return p


def belly(t):
    p = dict(SIDE)
    p.update({'skl_root': (-12, 0, 170), 'root_location': (0, -1.25, 0),
              'head': (80, 15, 0), 'mouth': (25, 0, 0),
              'tail2': (-35, 0, 0), 'tail3': (-20, 0, 0),
              'Larm2': (-40, 0, 18), 'Rarm2': (-40, 0, -18),
              'Lhand1': (35, 0, 0), 'Rhand1': (35, 0, 0),
              'Lhand2': (8*math.sin(TAU*2*t), 0, 0),
              'Rhand2': (-8*math.sin(TAU*2*t), 0, 0)})
    return p


def lie_side_up(t):
    frame = 1+44*t
    raised = dict(SIDE, head=(-8, 0, 0))
    if frame <= 15:
        return blend(SIDE, raised, ease((frame-1)/14))
    return blend(raised, SIT, ease((frame-15)/25))


def call_stun(t):
    return blend({}, STUN, ease(t*14/2))


def call_curious(t):
    frame = 1+39*t
    response = window(frame, 1, 12, 27, 39)
    p = dict(STUN)
    add(p, 'head', yaw=25*response, roll=15*response)
    add(p, 'Lear1', pitch=2*response)
    add(p, 'Rear1', pitch=-10*response)
    return p


def paws_up_enter(t):
    p = blend(STUN, PAWS, ease(t/.93))
    # Lower the pelvis before the folded knees lift the hind paws. The existing
    # floor guard prevents over-lowering, and the held endpoint stays exact.
    p['root_location'] = (0, SIT['root_location'][1]*ease(t/.60), 0)
    return p


def paws_up(t):
    p = dict(PAWS)
    add(p, 'waist', yaw=3*math.sin(TAU*t))
    add(p, 'head', pitch=2*math.sin(TAU*3*t))
    # Small distal elbow/wrist opposition pushes the pad forward without
    # moving the rigid shoulder or changing pad-facing orientation.
    for side, start in [('L', .10), ('R', .50)]:
        push = pulse(t, start, start+.20)
        add(p, side+'arm2', pitch=5.9*push)
        add(p, side+'hand1', pitch=-5.9*push)
    return p


def paws_down(t):
    p = blend(PAWS, SIT, ease(t/.93))
    for side in 'LR':
        lift = 15*pulse(t, 0, .93)
        add(p, side+'arm2', pitch=-lift)
        add(p, side+'hand1', pitch=lift)
    return p


CHAINS = [
    ('shiba_call_stun', -1, 'shiba_call_curious', 0),
    ('shiba_call_stun', -1, 'shiba_paws_up_enter', 0),
    ('shiba_call_curious', -1, 'shiba_paws_up_enter', 0),
    ('shiba_paws_up_enter', -1, 'shiba_paws_up_loop', 0),
    ('shiba_paws_up_loop', 0, 'shiba_paws_up_loop', -1),
    ('shiba_paws_up_loop', 0, 'shiba_paws_down', 0),
    ('shiba_pet_settle', -1, 'shiba_lie_side_loop', 0),
    ('shiba_lie_side_loop', 0, 'shiba_lie_side_up', 0),
]


def check_chains(channels):
    reports = []
    for a, ai, b, bi in CHAINS:
        error = max(matrix_error(channels[a][j][ai], channels[b][j][bi]) for j in channels[a])
        assert error < 1e-3, ('chain', a, b, error)
        reports.append(dict(from_clip=a, from_index=ai, to_clip=b, to_index=bi,
                            max_matrix_error=error, joints=list(channels[a])))
    joints = [side+joint for side in 'LR' for joint in ('leg1','leg2','foot1','foot2')]
    a, b = 'shiba_lie_side_loop', 'shiba_belly_loop'
    error = max(matrix_error(channels[a][j][0], channels[b][j][0]) for j in joints)
    assert error < 1e-3, ('hind-leg local chain', error)
    reports.append(dict(from_clip=a, to_clip=b, from_index=0, to_index=0, joints=joints,
                        max_matrix_error=error, excluded_joints=sorted(set(channels[a])-set(joints)),
                        exclusion_reason='Only hind-leg local matrices match: whole-root roll/support height, forepaws and head intentionally differ; other joints are outside this contract comparison.'))
    return reports


def build_tier3(render=True):
    rig = Rig()
    protected = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in CLIPS.glob('*.dae') if p.stem not in SPECS}
    references = {name: read_clip_channels(CLIPS/(name+'.dae'))
                  for name in {'shiba_idle_loop', 'shiba_sit_idle_loop'}}
    poses = [pet_head, pet_settle, lie_side, belly, lie_side_up,
             call_stun, call_curious, paws_up_enter, paws_up, paws_down]
    reports, handoffs, channels = [], [], {}
    for (name, (frames, looping, incoming, outgoing)), fn in zip(SPECS.items(), poses):
        rig.action(name, frames, fn, floor_contact=True)
        report, samples = rig.export(name, joint_limit=7)
        channels[name] = samples
        report['loop'] = looping
        if looping:
            error = max(matrix_error(ms[0],ms[-1]) for ms in samples.values())
            assert error < 2e-5, (name, 'loop', error)
            report['loop_endpoint_max_error'] = error
        else:
            for state,index,endpoint in [(incoming,0,'entry'),(outgoing,-1,'handoff')]:
                if state is None:
                    continue
                error = max(matrix_error(samples[j][index],references[state][j][0]) for j in samples)
                assert error < 2e-5, (name,endpoint,state,error)
                handoffs.append(dict(clip=name,endpoint=endpoint,state=state,max_matrix_error=error))
        reports.append(report)
        print('TIER3_PASS', name, frames, flush=True)
    chains = check_chains(channels)
    assert protected == {name:hashlib.sha256((CLIPS/name).read_bytes()).hexdigest() for name in protected}
    rig.activate(rig.actions['shiba_pet_head_loop'])
    rig.save(WORK/'shiba_clips_tier3.blend', selected_bone='head')
    write_report(WORK/'tier3_validation.json', dict(clips=reports,state_handoffs=handoffs,chains=chains,
                 protected_assets_unchanged_sha256=protected,
                 runtime_only=['eyes','tongue','blink','breathing','gaze','mood_tail_wag'],
                 mac_playback='Pending Mac review; Blender checks are not acceptance'))
    if render:
        directory = WORK/'qa_frames'
        directory.mkdir(exist_ok=True)
        representatives = [20,65,73,24,26,8,18,30,19,15]
        review_frames = [[1,16,41,60], [1,30,55,90], [1,40,73,120],
                         [1,12,34,90], [1,15,28,45], [1,2,3,15],
                         [1,12,30,40], [1,11,21,30], [1,19,54,90], [1,11,21,30]]
        for (name,(frames,_,_,_)), representative, key_frames in zip(SPECS.items(),representatives,review_frames):
            rig.activate(rig.actions[name])
            for frame in key_frames:
                render_review(rig,directory/f'{name}_{frame:03d}.png',frame,front='paws' in name or 'call' in name)
            render_review(rig,WORK/'previews'/(name+'.png'),representative,front='paws' in name or 'call' in name)
            print('TIER3_PREVIEW',name,flush=True)
