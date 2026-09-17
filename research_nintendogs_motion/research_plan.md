# Video-to-rig animation research plan

## Question
How can a Blender modeller reconstruct the dogs' visible animation sequences and interaction responses in https://www.youtube.com/watch?v=hb5j2v10eYs on this project's Collada skeleton?

## Evidence streams
1. Main: acquire video, inspect timestamped contact sheets and dense motion samples, catalogue sequences and subtle expressions. Distinguish visible events, inferred triggers, and proposed authoring parameters.
2. Rig research: inspect original Collada hierarchy, transforms, weights, facial capabilities, existing clip contract and authoring constraints. Return exact mapping and fidelity limitations without changing assets.
3. Biomechanics research: primary or specialist sources for canine gait, posture changes and expressive signals. Explain what can and cannot be inferred from a stylized game recording.

## Synthesis
Write a detailed reference in docs/reference with timestamped event inventory, pose/timing sheets, rig mapping, context and transition rules, uncertainty labels, source citations and a Blender comparison workflow. Keep original clips and implementation unchanged. Raw downloaded video and temporary frame extracts remain outside Git. Do not present existing procedural clip values as measurements from the video.
