// Three.js single-room scene + character controller for Poképals.
// Loads real rigged Collada models (Pikachu / Mudkip / Charmander) and animates
// them procedurally — the source .dae files carry no baked animation clips.
import {
  Scene,
  PerspectiveCamera,
  WebGLRenderer,
  Group,
  Color,
  Fog,
  Vector2,
  Vector3,
  Quaternion,
  Euler,
  Box3,
  AmbientLight,
  HemisphereLight,
  DirectionalLight,
  PointLight,
  Mesh,
  MeshStandardMaterial,
  MeshBasicMaterial,
  SpriteMaterial,
  Sprite,
  BoxGeometry,
  PlaneGeometry,
  CylinderGeometry,
  SphereGeometry,
  TorusGeometry,
  CircleGeometry,
  CanvasTexture,
  RepeatWrapping,
  ClampToEdgeWrapping,
  NearestFilter,
  LinearMipmapLinearFilter,
  DoubleSide,
  FrontSide,
  SRGBColorSpace,
  ACESFilmicToneMapping,
  PCFSoftShadowMap,
  Raycaster,
  LoadingManager,
  MathUtils,
} from "three";
import { ColladaLoader } from "three/examples/jsm/loaders/ColladaLoader.js";
import { mergeVertices } from "three/examples/jsm/utils/BufferGeometryUtils.js";
import { clone as cloneSkeleton } from "three/examples/jsm/utils/SkeletonUtils.js";

const TARGET_HEIGHT = 2; // world units, "roughly 2 world units height"
const CHAR_ANCHOR = new Vector3(0.9, 0, 0.1); // center-right of stage so left sidebar never covers it
const CAMERA_LOOK = new Vector3(0.55, 0.95, 0);
const CAMERA_POS = new Vector3(0.55, 1.55, 4.6);
const Y_AXIS = new Vector3(0, 1, 0);

// Calibrated against the actual bind-pose geometry of these three .dae rips: the
// hand-to-hand heuristic below yields a "right" vector that needs a 180° flip on
// all three models to make the belly face the camera, so this sign is a rig-family
// constant, not a per-species guess.
const FACE_SIGN = -1;

const MODEL_SOURCES = {
  pikachu: "/assets/models/pikachu/Pikachu/Pikachu.dae",
  mudkip: "/assets/models/mudkip/Mizugorouout.dae",
  charmander: "/assets/models/charmander/Charmander/Hitokage.dae",
};

// Bone maps, hand-inspected from each .dae's <library_visual_scenes>. Names differ
// per rig (different exporters/skeletons); chains are ordered root-to-tip.
const RIGS = {
  pikachu: {
    waist: "Waist",
    spine: ["Spine1", "Spine2"],
    head: "Head",
    neck: null,
    jaw: null,
    earsL: ["LEar1", "LEar2"],
    earsR: ["REar1", "REar2"],
    feelers: [],
    tail: ["Tail1", "Tail2", "Tail3"],
    armL: ["LArm", "LForeArm", "LHand"],
    armR: ["RArm", "RForeArm", "RHand"],
    legL: ["LThigh", "LLeg", "LFoot", "LToe"],
    legR: ["RThigh", "RLeg", "RFoot", "RToe"],
    handL: ["LHand", "LForeArm", "LArm"],
    handR: ["RHand", "RForeArm", "RArm"],
    flameHead: null,
    flameTail: null,
  },
  mudkip: {
    waist: "Waist",
    spine: ["Spine"],
    head: "Head",
    neck: null,
    jaw: "Jaw",
    earsL: ["LFeeler"],
    earsR: ["RFeeler"],
    feelers: ["Feeler1", "Feeler2"],
    tail: ["Tail1", "Tail2"],
    armL: ["LArm", "LForeArm", "LHand"],
    armR: ["RArm", "RForeArm", "RHand"],
    legL: ["LThigh", "LLeg", "LFoot"],
    legR: ["RThigh", "RLeg", "RFoot"],
    handL: ["LHand", "LForeArm", "LArm"],
    handR: ["RHand", "RForeArm", "RArm"],
    flameHead: null,
    flameTail: null,
  },
  charmander: {
    waist: "Waist",
    spine: ["Spine"],
    head: "Head",
    neck: "Neck",
    jaw: "Jaw",
    earsL: [],
    earsR: [],
    feelers: [],
    tail: ["Tail", "Tail1", "Tail2"],
    armL: ["LArm", "LForeArm"],
    armR: ["RArm", "RForeArm"],
    legL: ["LThigh", "LLeg", "LFoot", "LToe"],
    legR: ["RThigh", "RLeg", "RFoot", "RToe"],
    handL: ["LForeArm", "LArm"],
    handR: ["RForeArm", "RArm"],
    flameHead: "FLAME",
    flameTail: "EfFire",
  },
};

const IDLE_ANIM_NOTES =
  "Procedural bone animation only (no baked <library_animations> clips exist in any of the three .dae source files) — idle breathing/ear/tail/head sway plus sit/jump/spin/shake/eat/drink/call/happy/throw gesture overlays are all driven by per-frame quaternion offsets applied on top of each bone's bind pose.";

// ---------- small math/geometry helpers ----------

function resolveBone(root, names) {
  for (const n of names) {
    const b = root.getObjectByName(n);
    if (b) return b;
  }
  return null;
}
function resolveChain(root, names) {
  return names.map((n) => root.getObjectByName(n)).filter(Boolean);
}

const _q = new Quaternion();
const _e = new Euler();
function poseBone(bone, x = 0, y = 0, z = 0) {
  if (!bone) return;
  const bind = bone.userData.bindQuaternion;
  if (!bind) return;
  _e.set(x, y, z);
  _q.setFromEuler(_e);
  bone.quaternion.copy(bind);
  if (bone.userData.worldBindInverse) {
    bone.quaternion
      .multiply(bone.userData.worldBindInverse)
      .multiply(_q)
      .multiply(bone.userData.worldBind);
  } else bone.quaternion.multiply(_q);
}
function resetBone(bone) {
  if (!bone || !bone.userData.bindQuaternion) return;
  bone.quaternion.copy(bone.userData.bindQuaternion);
}

function makeCanvas(w, h) {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  return c;
}
function canvasTexture(canvas, repeatX = 1, repeatY = 1) {
  const tex = new CanvasTexture(canvas);
  tex.wrapS = RepeatWrapping;
  tex.wrapT = RepeatWrapping;
  tex.repeat.set(repeatX, repeatY);
  tex.colorSpace = SRGBColorSpace;
  tex.anisotropy = 4;
  tex.needsUpdate = true;
  return tex;
}

// ---------- procedural room textures (no external art needed for the shell) ----------

function woodFloorCanvas() {
  const c = makeCanvas(256, 256);
  const g = c.getContext("2d");
  const planks = 8;
  const ph = c.height / planks;
  for (let i = 0; i < planks; i++) {
    const base = 178 + Math.round(Math.sin(i * 12.9) * 10);
    g.fillStyle = `rgb(${base + 22},${base - 4},${base - 44})`;
    g.fillRect(0, i * ph, c.width, ph);
    g.fillStyle = "rgba(255,255,255,0.06)";
    g.fillRect(0, i * ph, c.width, 2);
    g.fillStyle = "rgba(90,55,30,0.35)";
    g.fillRect(0, i * ph + ph - 1, c.width, 1);
    for (let j = 0; j < 5; j++) {
      const gx = (j * 53 + i * 17) % c.width;
      g.strokeStyle = `rgba(90,55,25,${0.05 + (j % 3) * 0.03})`;
      g.beginPath();
      g.moveTo(gx, i * ph);
      g.bezierCurveTo(
        gx + 8,
        i * ph + ph * 0.3,
        gx - 6,
        i * ph + ph * 0.6,
        gx + 4,
        i * ph + ph,
      );
      g.stroke();
    }
  }
  return c;
}

function plasterCanvas() {
  const c = makeCanvas(256, 256);
  const g = c.getContext("2d");
  g.fillStyle = "#f3efe2";
  g.fillRect(0, 0, c.width, c.height);
  const id = g.getImageData(0, 0, c.width, c.height);
  for (let i = 0; i < id.data.length; i += 4) {
    const n = (Math.random() - 0.5) * 10;
    id.data[i] += n;
    id.data[i + 1] += n;
    id.data[i + 2] += n;
  }
  g.putImageData(id, 0, 0);
  return c;
}

function woodSlatCanvas() {
  const c = makeCanvas(256, 128);
  const g = c.getContext("2d");
  g.fillStyle = "#caa06d";
  g.fillRect(0, 0, c.width, c.height);
  const slats = 6;
  const sw = c.width / slats;
  for (let i = 0; i < slats; i++) {
    const base = 182 + Math.round(Math.sin(i * 7.3) * 12);
    g.fillStyle = `rgb(${base + 20},${base - 20},${base - 60})`;
    g.fillRect(i * sw, 0, sw - 3, c.height);
    g.fillStyle = "rgba(255,255,255,0.08)";
    g.fillRect(i * sw, 0, 2, c.height);
    g.fillStyle = "rgba(70,40,15,0.45)";
    g.fillRect(i * sw + sw - 3, 0, 3, c.height);
  }
  return c;
}

function gardenCanvas() {
  const c = makeCanvas(512, 320);
  const g = c.getContext("2d");
  const sky = g.createLinearGradient(0, 0, 0, c.height * 0.55);
  sky.addColorStop(0, "#bfe6ff");
  sky.addColorStop(1, "#eaf7e2");
  g.fillStyle = sky;
  g.fillRect(0, 0, c.width, c.height * 0.55);
  const lawn = g.createLinearGradient(0, c.height * 0.5, 0, c.height);
  lawn.addColorStop(0, "#8fca5c");
  lawn.addColorStop(1, "#5a9c3d");
  g.fillStyle = lawn;
  g.fillRect(0, c.height * 0.5, c.width, c.height * 0.5);
  g.fillStyle = "#fff7d6";
  g.beginPath();
  g.arc(c.width * 0.78, c.height * 0.18, 34, 0, Math.PI * 2);
  g.fill();
  for (let i = 0; i < 9; i++) {
    const x = (i * 71 + 30) % c.width;
    const baseY = c.height * 0.55;
    g.fillStyle = `rgb(${90 + (i % 3) * 8},${60 + (i % 4) * 6},34)`;
    g.fillRect(x - 4, baseY - 30, 8, 32);
    g.fillStyle = `rgb(${60 + (i % 3) * 20},${140 + (i % 4) * 15},${60 + (i % 2) * 20})`;
    g.beginPath();
    g.arc(x, baseY - 40, 26 + (i % 3) * 4, 0, Math.PI * 2);
    g.fill();
  }
  return c;
}

function grassCanvas() {
  const c = makeCanvas(128, 128);
  const g = c.getContext("2d");
  g.fillStyle = "#79b84b";
  g.fillRect(0, 0, c.width, c.height);
  for (let i = 0; i < 400; i++) {
    const x = Math.random() * c.width,
      y = Math.random() * c.height;
    g.strokeStyle =
      Math.random() > 0.5 ? "rgba(255,255,255,0.10)" : "rgba(30,60,15,0.18)";
    g.beginPath();
    g.moveTo(x, y);
    g.lineTo(x + (Math.random() - 0.5) * 4, y - 4 - Math.random() * 4);
    g.stroke();
  }
  return c;
}

function pathCanvas() {
  const c = makeCanvas(128, 256);
  const g = c.getContext("2d");
  g.fillStyle = "#d9c6a0";
  g.fillRect(0, 0, c.width, c.height);
  for (let i = 0; i < 60; i++) {
    g.fillStyle = `rgba(150,120,80,${0.08 + Math.random() * 0.1})`;
    const x = Math.random() * c.width,
      y = Math.random() * c.height,
      r = 3 + Math.random() * 6;
    g.beginPath();
    g.arc(x, y, r, 0, Math.PI * 2);
    g.fill();
  }
  return c;
}

function shadowBlobCanvas() {
  const c = makeCanvas(128, 128);
  const g = c.getContext("2d");
  const grd = g.createRadialGradient(64, 64, 4, 64, 64, 62);
  grd.addColorStop(0, "rgba(20,20,15,0.42)");
  grd.addColorStop(1, "rgba(20,20,15,0)");
  g.fillStyle = grd;
  g.fillRect(0, 0, c.width, c.height);
  return c;
}

function bubbleCanvas() {
  const c = makeCanvas(64, 64);
  const g = c.getContext("2d");
  const grd = g.createRadialGradient(24, 22, 2, 32, 32, 30);
  grd.addColorStop(0, "rgba(255,255,255,0.28)");
  grd.addColorStop(0.55, "rgba(174,221,255,0.12)");
  grd.addColorStop(1, "rgba(214,240,255,0)");
  g.fillStyle = grd;
  g.beginPath();
  g.arc(32, 32, 30, 0, Math.PI * 2);
  g.fill();
  g.strokeStyle = "rgba(255,255,255,0.8)";
  g.lineWidth = 1.5;
  g.beginPath();
  g.arc(32, 32, 28, 0, Math.PI * 2);
  g.stroke();
  return c;
}

let ROOM_TEXTURES = null;
function getRoomTextures() {
  if (ROOM_TEXTURES) return ROOM_TEXTURES;
  ROOM_TEXTURES = {
    floorWood: canvasTexture(woodFloorCanvas(), 3, 3),
    plaster: canvasTexture(plasterCanvas(), 3, 2),
    slats: canvasTexture(woodSlatCanvas(), 4, 1),
    garden: canvasTexture(gardenCanvas(), 1, 1),
    grass: canvasTexture(grassCanvas(), 10, 10),
    path: canvasTexture(pathCanvas(), 1, 6),
    shadowBlob: (() => {
      const t = new CanvasTexture(shadowBlobCanvas());
      t.needsUpdate = true;
      return t;
    })(),
    bubble: (() => {
      const t = new CanvasTexture(bubbleCanvas());
      t.needsUpdate = true;
      return t;
    })(),
  };
  ROOM_TEXTURES.garden.wrapS = ROOM_TEXTURES.garden.wrapT = ClampToEdgeWrapping;
  return ROOM_TEXTURES;
}

// ---------- bath tile atlas: crop real swatches out of /assets/ui/bathroom.png ----------

async function buildBathTiles() {
  const img = await new Promise((resolve, reject) => {
    const im = new Image();
    im.crossOrigin = "anonymous";
    im.onload = () => resolve(im);
    im.onerror = () => reject(new Error("bathroom.png failed to load"));
    im.src = "/assets/ui/bathroom.png";
  });
  const cropTo = (sx, sy, sw, sh, outSize) => {
    const c = makeCanvas(outSize, outSize);
    const g = c.getContext("2d");
    g.drawImage(img, sx, sy, sw, sh, 0, 0, outSize, outSize);
    return c;
  };
  const floor = cropTo(4, 4, 60, 60, 128);
  const wall = cropTo(4, 142, 58, 58, 128);
  return {
    floor: canvasTexture(floor, 6, 6),
    wall: canvasTexture(wall, 8, 3),
  };
}

// ---------- loading manager: fix case-mismatched texture paths without touching source ----------

function makeLoadingManager(onError) {
  const manager = new LoadingManager();
  manager.setURLModifier((url) => {
    // Mudkip's .dae references "MizugorouDh.PNG" / "MizugorouEyeDh.PNG" (uppercase
    // extension) but the shipped files are lowercase ".png" — normalize the
    // extension case at resolve time instead of editing the .dae or renaming assets.
    return url.replace(
      /\.(PNG|JPG|JPEG|TGA)(\?|$)/,
      (m, ext, tail) => `.${ext.toLowerCase()}${tail}`,
    );
  });
  manager.onError = (url) =>
    onError && onError(new Error(`Failed to load asset: ${url}`));
  return manager;
}

// ---------- character loading + normalization ----------

const characterCache = new Map();

function loadCharacter(species, manager, onError) {
  if (characterCache.has(species)) return characterCache.get(species);
  const src = MODEL_SOURCES[species];
  if (!src) return Promise.reject(new Error(`Unknown species: ${species}`));

  const promise = (async () => {
    const loader = new ColladaLoader(manager);
    let collada;
    try {
      collada = await loader.loadAsync(src);
    } catch (err) {
      throw new Error(
        `Could not load ${species} model (${src}): ${err && err.message ? err.message : err}`,
      );
    }

    const root = collada.scene;
    let meshCount = 0;
    root.traverse((o) => {
      if (o.isMesh) {
        meshCount++;
        o.castShadow = true;
        o.receiveShadow = true;
        const geometry = o.geometry;
        geometry.deleteAttribute("normal");
        o.geometry = mergeVertices(geometry);
        o.geometry.computeVertexNormals();
        geometry.dispose();
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
          if (!m) continue;
          m.side = FrontSide;
          m.flatShading = false;
          m.specular?.set(0x000000);
          m.emissive?.set(0x000000);
          if ("shininess" in m) m.shininess = Math.min(m.shininess ?? 6, 6);
          if (m.map) {
            m.map.magFilter = NearestFilter; // keeps the low-res DS-era textures crisp/pixel-ish
            m.map.minFilter = LinearMipmapLinearFilter;
            m.map.anisotropy = 4;
            m.map.colorSpace = SRGBColorSpace;
            m.map.needsUpdate = true;
          }
        }
      }
      if (o.isBone) {
        o.userData.bindQuaternion = o.quaternion.clone();
      }
    });

    if (meshCount === 0) {
      throw new Error(`${species} model parsed but contains no mesh geometry`);
    }

    root.updateMatrixWorld(true);

    // These rips carry no <up_axis> tag, so ColladaLoader assumes Y-up — but the
    // underlying skeleton data is actually Z-up for all three files. Detect the
    // true up axis at runtime from the whole-body span between the skeleton's
    // ground-anchored "Origin" joint and the head, rather than hardcoding it, so
    // a differently-authored rip degrades safely. (A single lower-body bone pair
    // such as waist->head is unreliable here: these rigs have a natural forward
    // lean baked into the upper-body bind pose that skews a local segment.)
    const rigDef = RIGS[species];
    const originBone =
      root.getObjectByName("Origin") || root.getObjectByName(rigDef.waist);
    const headBoneEarly = root.getObjectByName(rigDef.head);
    const axisFix = new Group();
    if (originBone && headBoneEarly) {
      const pf = originBone.getWorldPosition(new Vector3());
      const ph = headBoneEarly.getWorldPosition(new Vector3());
      const up = new Vector3(ph.x - pf.x, ph.y - pf.y, ph.z - pf.z);
      // This is a mislabeled-axis problem (missing/wrong <up_axis>), not a
      // continuous tilt: snap to the dominant cardinal axis so a genuine
      // forward-leaning bind pose (present on some of these rigs) doesn't get
      // baked in as a partial diagonal correction.
      const abs = [Math.abs(up.x), Math.abs(up.y), Math.abs(up.z)];
      const dominant = abs.indexOf(Math.max(...abs));
      const cardinal = new Vector3(
        dominant === 0 ? Math.sign(up.x) || 1 : 0,
        dominant === 1 ? Math.sign(up.y) || 1 : 0,
        dominant === 2 ? Math.sign(up.z) || 1 : 0,
      );
      if (cardinal.lengthSq() > 0) {
        axisFix.quaternion.setFromUnitVectors(cardinal, Y_AXIS);
      }
    }
    axisFix.add(root);
    axisFix.updateMatrixWorld(true);

    const box = new Box3().setFromObject(axisFix);
    const size = box.getSize(new Vector3());
    const height = size.y || 1;
    const scale = TARGET_HEIGHT / height;
    const center = box.getCenter(new Vector3());

    const handL = resolveBone(root, rigDef.handL);
    const handR = resolveBone(root, rigDef.handR);
    let rotY = 0;
    if (handL && handR) {
      const pL = handL.getWorldPosition(new Vector3());
      const pR = handR.getWorldPosition(new Vector3());
      const right = new Vector3(pR.x - pL.x, 0, pR.z - pL.z);
      if (right.lengthSq() > 1e-6) {
        right.normalize();
        const forward = new Vector3(right.z, 0, -right.x).multiplyScalar(
          FACE_SIGN,
        );
        rotY = Math.atan2(forward.x, forward.z);
      }
    }

    axisFix.position.x -= center.x;
    axisFix.position.z -= center.z;
    axisFix.position.y -= box.min.y;

    const wrapper = new Group();
    wrapper.name = `${species}-wrapper`;
    wrapper.add(axisFix);
    wrapper.rotation.y = rotY;
    wrapper.scale.setScalar(scale);

    const rig = {
      waist: root.getObjectByName(rigDef.waist),
      spine: resolveChain(root, rigDef.spine),
      head: root.getObjectByName(rigDef.head),
      neck: rigDef.neck ? root.getObjectByName(rigDef.neck) : null,
      jaw: rigDef.jaw ? root.getObjectByName(rigDef.jaw) : null,
      earsL: resolveChain(root, rigDef.earsL),
      earsR: resolveChain(root, rigDef.earsR),
      feelers: resolveChain(root, rigDef.feelers),
      tail: resolveChain(root, rigDef.tail),
      armL: resolveChain(root, rigDef.armL),
      armR: resolveChain(root, rigDef.armR),
      legL: resolveChain(root, rigDef.legL),
      legR: resolveChain(root, rigDef.legR),
      flameHead: rigDef.flameHead
        ? root.getObjectByName(rigDef.flameHead)
        : null,
      flameTail: rigDef.flameTail
        ? root.getObjectByName(rigDef.flameTail)
        : null,
    };
    // The biped exports use an arms-out bind pose. Set a relaxed resting pose
    // from each shoulder's actual world-space direction, independent of bone axes.
    if (species !== "mudkip") {
      wrapper.updateMatrixWorld(true);
      for (const chain of [rig.armL, rig.armR]) {
        if (chain.length < 2) continue;
        const shoulder = chain[0];
        const direction = chain[1]
          .getWorldPosition(new Vector3())
          .sub(shoulder.getWorldPosition(new Vector3()))
          .normalize();
        const target = direction
          .clone()
          .lerp(new Vector3(0, -1, 0), 0.65)
          .normalize();
        const worldRotation = shoulder.getWorldQuaternion(new Quaternion());
        const delta = new Quaternion().setFromUnitVectors(direction, target);
        const parentInverse = shoulder.parent
          .getWorldQuaternion(new Quaternion())
          .invert();
        shoulder.quaternion.copy(
          parentInverse.multiply(delta).multiply(worldRotation),
        );
        shoulder.userData.bindQuaternion.copy(shoulder.quaternion);
        wrapper.updateMatrixWorld(true);
      }
    }
    wrapper.updateMatrixWorld(true);
    root.traverse((bone) => {
      if (!bone.isBone) return;
      bone.userData.worldBind = bone.getWorldQuaternion(new Quaternion());
      bone.userData.worldBindInverse = bone.userData.worldBind.clone().invert();
    });

    return {
      species,
      wrapper,
      root,
      rig,
      baseRotation: rotY,
      footHeight: TARGET_HEIGHT,
    };
  })();

  characterCache.set(species, promise);
  promise.catch(() => characterCache.delete(species));
  return promise;
}

// ---------- gesture/idle animator ----------

const GESTURE_DURATIONS = {
  sit: 1.5,
  jump: 0.9,
  spin: 1.1,
  shake: 0.9,
  happy: 1.0,
  eat: 1.6,
  drink: 1.4,
  call: 0.9,
  throw: 0.55,
};

function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}
function envelope(t, dur) {
  const p = MathUtils.clamp(t / dur, 0, 1);
  return Math.sin(p * Math.PI); // 0 -> 1 -> 0, smooth in/out over the gesture window
}

function createAnimator(character) {
  const { wrapper, rig } = character;
  let gesture = null; // { name, t, duration }
  let sitHold = false; // 'sit' latches into a held pose instead of springing back
  let baseY = 0;
  const baseRotation = character.baseRotation;

  function play(name) {
    if (!GESTURE_DURATIONS[name]) return;
    gesture = { name, t: 0 };
    sitHold = name === "sit";
  }

  function clearSit() {
    sitHold = false;
  }

  function update(dt, t, energy, walking = false) {
    wrapper.position.y = baseY;
    wrapper.rotation.z = 0;
    wrapper.rotation.y = baseRotation;
    rig.legL.forEach(resetBone);
    rig.legR.forEach(resetBone);

    // idle base layer — breathing, ears/feelers, tail sway, subtle head look
    const breathe = Math.sin(t * 1.7) * 0.045 * energy;
    if (rig.spine[0])
      poseBone(rig.spine[0], breathe, Math.sin(t * 0.4) * 0.05, 0);
    if (rig.spine[1]) poseBone(rig.spine[1], breathe * 0.6, 0, 0);
    if (rig.neck) poseBone(rig.neck, Math.sin(t * 1.1 + 0.4) * 0.03, 0, 0);
    if (rig.head)
      poseBone(
        rig.head,
        Math.sin(t * 1.05 + 1) * 0.06 * energy,
        Math.sin(t * 0.35) * 0.12,
        0,
      );
    if (rig.jaw) poseBone(rig.jaw, Math.max(0, Math.sin(t * 0.6)) * 0.03, 0, 0);
    rig.earsL.forEach((b, i) =>
      poseBone(b, Math.sin(t * 2.3 + i * 0.7) * 0.16 * energy, 0, 0.05 * i),
    );
    rig.earsR.forEach((b, i) =>
      poseBone(
        b,
        Math.sin(t * 2.3 + i * 0.7 + 0.3) * 0.16 * energy,
        0,
        -0.05 * i,
      ),
    );
    rig.feelers.forEach((b, i) =>
      poseBone(
        b,
        Math.sin(t * 1.8 + i * 0.9) * 0.18 * energy,
        Math.cos(t * 1.3 + i) * 0.1,
        0,
      ),
    );
    rig.tail.forEach((b, i) =>
      poseBone(
        b,
        0,
        Math.sin(t * 1.9 - i * 0.8) * (0.14 + i * 0.05) * energy,
        0,
      ),
    );
    rig.armL.forEach((b, i) =>
      poseBone(b, Math.sin(t * 1.3 + i) * 0.03 * energy, 0, 0.02),
    );
    rig.armR.forEach((b, i) =>
      poseBone(b, Math.sin(t * 1.3 + i + 0.5) * 0.03 * energy, 0, -0.02),
    );
    if (rig.flameHead)
      poseBone(
        rig.flameHead,
        Math.sin(t * 6) * 0.08,
        Math.cos(t * 5) * 0.08,
        0,
      );
    if (rig.flameTail)
      poseBone(
        rig.flameTail,
        Math.sin(t * 7 + 1) * 0.1,
        Math.cos(t * 6 + 1) * 0.1,
        0,
      );
    if (walking && !sitHold && !gesture) {
      const stride = Math.sin(t * 9);
      rig.legL.forEach((b, i) => poseBone(b, (stride * 0.35) / (i + 1), 0, 0));
      rig.legR.forEach((b, i) => poseBone(b, (-stride * 0.35) / (i + 1), 0, 0));
      rig.armL.forEach((b) => poseBone(b, -stride * 0.14, 0, 0));
      rig.armR.forEach((b) => poseBone(b, stride * 0.14, 0, 0));
      wrapper.position.y = Math.abs(stride) * 0.025;
    }

    if (sitHold && (!gesture || gesture.name !== "sit")) applySitPose(1);

    if (!gesture) return;
    const dur = GESTURE_DURATIONS[gesture.name];
    gesture.t += dt;
    const env = envelope(gesture.t, dur);
    switch (gesture.name) {
      case "sit":
        applySitPose(easeInOut(Math.min(1, gesture.t / (dur * 0.6))));
        break;
      case "jump":
        applyJump(env, gesture.t, dur);
        break;
      case "spin":
        applySpin(gesture.t, dur);
        break;
      case "shake":
        applyShake(gesture.t);
        break;
      case "happy":
        applyHappy(env, gesture.t);
        break;
      case "eat":
        applyEat(gesture.t);
        break;
      case "drink":
        applyDrink(gesture.t);
        break;
      case "call":
        applyCall(env, gesture.t);
        break;
      case "throw":
        applyHappy(env, gesture.t);
        break;
      default:
        break;
    }
    if (gesture.t >= dur) {
      gesture = null;
      if (sitHold) applySitPose(1);
    }
  }

  function applySitPose(k) {
    wrapper.position.y = baseY;
    // lower the hips and bend the legs/tail rather than sinking the whole rig
    rig.legL.forEach((b, i) => poseBone(b, k * (0.9 - i * 0.18), 0, 0));
    rig.legR.forEach((b, i) => poseBone(b, k * (0.9 - i * 0.18), 0, 0));
    if (rig.spine[0]) poseBone(rig.spine[0], -k * 0.18, 0, 0);
    if (rig.head) poseBone(rig.head, k * 0.1, 0, 0);
    rig.tail.forEach((b) => poseBone(b, -k * 0.22, 0, 0));
  }

  function applyJump(env, t, dur) {
    const hop = Math.sin(Math.min(1, t / dur) * Math.PI);
    wrapper.position.y = baseY + hop * 0.42;
    const crouch = t < dur * 0.25 ? 1 - t / (dur * 0.25) : 0;
    rig.legL.forEach((b) => poseBone(b, crouch * 0.5 - hop * 0.35, 0, 0));
    rig.legR.forEach((b) => poseBone(b, crouch * 0.5 - hop * 0.35, 0, 0));
    rig.armL.forEach((b, i) => poseBone(b, -hop * 0.5, 0, 0.15 + i * 0.1));
    rig.armR.forEach((b, i) => poseBone(b, -hop * 0.5, 0, -0.15 - i * 0.1));
    if (rig.head) poseBone(rig.head, -hop * 0.12, 0, 0);
    rig.tail.forEach((b, i) => poseBone(b, 0, Math.sin(t * 14 - i) * 0.2, 0));
  }

  function applySpin(t, dur) {
    const p = Math.min(1, t / dur);
    wrapper.rotation.y = baseRotation + p * Math.PI * 2;
    wrapper.position.y = baseY + Math.sin(p * Math.PI) * 0.12;
    rig.tail.forEach((b, i) => poseBone(b, 0, 0.35 * (i + 1) * 0.2, 0));
    rig.earsL.forEach((b) => poseBone(b, 0.25, 0, 0));
    rig.earsR.forEach((b) => poseBone(b, 0.25, 0, 0));
    if (t >= dur) wrapper.rotation.y = baseRotation;
  }

  function applyShake(t) {
    const s = Math.sin(t * 26) * Math.max(0, 1 - t / 0.9);
    if (rig.spine[0]) poseBone(rig.spine[0], 0, s * 0.28, 0);
    if (rig.head) poseBone(rig.head, 0, -s * 0.35, 0);
    rig.earsL.forEach((b) => poseBone(b, 0, s * 0.4, 0));
    rig.earsR.forEach((b) => poseBone(b, 0, -s * 0.4, 0));
    rig.tail.forEach((b) => poseBone(b, 0, -s * 0.3, 0));
  }

  function applyHappy(env, t) {
    wrapper.position.y = baseY + Math.abs(Math.sin(t * 9)) * 0.14 * env;
    rig.tail.forEach((b, i) =>
      poseBone(b, 0, Math.sin(t * 12 - i) * 0.35 * env, 0),
    );
    rig.earsL.forEach((b) => poseBone(b, -0.2 * env, 0, 0));
    rig.earsR.forEach((b) => poseBone(b, -0.2 * env, 0, 0));
    if (rig.head)
      poseBone(rig.head, -0.08 * env, Math.sin(t * 8) * 0.08 * env, 0);
  }

  function applyEat(t) {
    const bite = (Math.sin(t * 8) + 1) / 2;
    if (rig.head) poseBone(rig.head, 0.35 + bite * 0.08, 0, 0);
    if (rig.neck) poseBone(rig.neck, 0.15, 0, 0);
    if (rig.jaw) poseBone(rig.jaw, bite * 0.22, 0, 0);
    if (rig.spine[0]) poseBone(rig.spine[0], 0.1, 0, 0);
  }

  function applyDrink(t) {
    const lap = (Math.sin(t * 10) + 1) / 2;
    if (rig.head) poseBone(rig.head, 0.42 + lap * 0.04, 0, 0);
    if (rig.neck) poseBone(rig.neck, 0.18, 0, 0);
    if (rig.jaw) poseBone(rig.jaw, lap * 0.12, 0, 0);
  }

  function applyCall(env, t) {
    wrapper.position.y = baseY + Math.max(0, Math.sin(t * 10)) * 0.1 * env;
    if (rig.head) poseBone(rig.head, -0.15 * env, 0, 0);
    rig.earsL.forEach((b) => poseBone(b, -0.3 * env, 0, 0));
    rig.earsR.forEach((b) => poseBone(b, -0.3 * env, 0, 0));
  }

  return {
    play,
    update,
    clearSit,
    get isSitting() {
      return sitHold;
    },
  };
}

// ---------- room / environment builders ----------

function disposeGroup(group) {
  if (!group) return;
  group.traverse((o) => {
    if (o.isMesh) {
      o.geometry?.dispose();
      const mats = Array.isArray(o.material) ? o.material : [o.material];
      mats.forEach((m) => m && m.dispose && m.dispose());
    }
  });
}

function buildIndoorShell(tex, { warm = true } = {}) {
  const group = new Group();
  const floorMat = new MeshStandardMaterial({
    map: tex.floorWood,
    roughness: 0.75,
    metalness: 0.02,
  });
  const floor = new Mesh(new PlaneGeometry(8, 6), floorMat);
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  group.add(floor);

  const wallMat = new MeshStandardMaterial({
    map: tex.plaster,
    roughness: 0.95,
  });
  const back = new Mesh(new PlaneGeometry(8, 3.4), wallMat);
  back.position.set(0, 1.7, -3);
  back.receiveShadow = true;
  group.add(back);

  const side = new Mesh(new PlaneGeometry(6, 3.4), wallMat);
  side.rotation.y = Math.PI / 2;
  side.position.set(-4, 1.7, 0);
  side.receiveShadow = true;
  group.add(side);

  // wood slat wainscoting along the base of both walls
  const slatMat = new MeshStandardMaterial({ map: tex.slats, roughness: 0.7 });
  const backSlats = new Mesh(new PlaneGeometry(8, 1.0), slatMat);
  backSlats.position.set(0, 0.5, -2.98);
  group.add(backSlats);
  const sideSlats = new Mesh(new PlaneGeometry(6, 1.0), slatMat);
  sideSlats.rotation.y = Math.PI / 2;
  sideSlats.position.set(-3.98, 0.5, 0);
  group.add(sideSlats);

  // large garden window on the back wall, sunny warm light "through" it
  const windowGroup = new Group();
  const glow = new Mesh(
    new PlaneGeometry(2.6, 1.8),
    new MeshBasicMaterial({ map: tex.garden }),
  );
  glow.position.set(1.6, 1.9, -2.97);
  windowGroup.add(glow);
  const frameMat = new MeshStandardMaterial({
    color: 0x6b4a2f,
    roughness: 0.6,
  });
  const mkFrameBar = (w, h, x, y) => {
    const bar = new Mesh(new BoxGeometry(w, h, 0.06), frameMat);
    bar.position.set(x, y, -2.94);
    return bar;
  };
  windowGroup.add(mkFrameBar(2.7, 0.08, 1.6, 2.8));
  windowGroup.add(mkFrameBar(2.7, 0.08, 1.6, 1.0));
  windowGroup.add(mkFrameBar(0.08, 1.85, 0.32, 1.9));
  windowGroup.add(mkFrameBar(0.08, 1.85, 2.88, 1.9));
  windowGroup.add(mkFrameBar(0.06, 1.8, 1.6, 1.9));
  group.add(windowGroup);

  if (warm) {
    const sunFill = new PointLight(0xffe2b0, 1.1, 6, 2);
    sunFill.position.set(1.6, 1.9, -1.6);
    group.add(sunFill);
  }

  return group;
}

function buildKennelExtras(tex) {
  const group = new Group();
  const bedMat = new MeshStandardMaterial({ color: 0x8a5a3a, roughness: 0.85 });
  const cushionMat = new MeshStandardMaterial({
    color: 0xe2c48c,
    roughness: 0.9,
  });
  const bed = new Mesh(new CylinderGeometry(0.85, 0.9, 0.22, 20), bedMat);
  bed.position.set(-1.4, 0.11, 0.9);
  bed.castShadow = true;
  bed.receiveShadow = true;
  group.add(bed);
  const cushion = new Mesh(
    new CylinderGeometry(0.65, 0.7, 0.14, 20),
    cushionMat,
  );
  cushion.position.set(-1.4, 0.24, 0.9);
  cushion.castShadow = true;
  cushion.receiveShadow = true;
  group.add(cushion);
  return group;
}

function buildBathShell(bathTex) {
  const group = new Group();
  const floor = new Mesh(
    new PlaneGeometry(8, 6),
    new MeshStandardMaterial({
      map: bathTex.floor,
      roughness: 0.4,
      metalness: 0.05,
    }),
  );
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  group.add(floor);
  const wallMat = new MeshStandardMaterial({
    map: bathTex.wall,
    roughness: 0.5,
  });
  const back = new Mesh(new PlaneGeometry(8, 3.4), wallMat);
  back.position.set(0, 1.7, -3);
  back.receiveShadow = true;
  group.add(back);
  const side = new Mesh(new PlaneGeometry(6, 3.4), wallMat);
  side.rotation.y = Math.PI / 2;
  side.position.set(-4, 1.7, 0);
  side.receiveShadow = true;
  group.add(side);

  const tubMat = new MeshStandardMaterial({
    color: 0xf5f5f0,
    roughness: 0.3,
    metalness: 0.1,
  });
  const tub = new Mesh(
    new CylinderGeometry(1.05, 0.95, 0.55, 24, 1, true),
    tubMat,
  );
  tub.position.set(1.5, 0.28, -1.6);
  tub.castShadow = true;
  tub.receiveShadow = true;
  group.add(tub);
  const tubFloor = new Mesh(
    new CircleGeometry(0.95, 24),
    new MeshStandardMaterial({ color: 0xcfeeff, roughness: 0.15 }),
  );
  tubFloor.rotation.x = -Math.PI / 2;
  tubFloor.position.set(1.5, 0.02, -1.6);
  group.add(tubFloor);

  return group;
}

function buildOutdoorShell(tex, variant) {
  const group = new Group();
  const lawn = new Mesh(
    new PlaneGeometry(20, 20),
    new MeshStandardMaterial({ map: tex.grass, roughness: 1 }),
  );
  lawn.rotation.x = -Math.PI / 2;
  lawn.receiveShadow = true;
  group.add(lawn);

  const sky = new Mesh(
    new PlaneGeometry(24, 10),
    new MeshBasicMaterial({ map: tex.garden, side: DoubleSide }),
  );
  sky.position.set(0, 4.6, -8);
  group.add(sky);

  const pathMesh = new Mesh(
    new PlaneGeometry(1.4, 10),
    new MeshStandardMaterial({ map: tex.path, roughness: 0.9 }),
  );
  pathMesh.rotation.x = -Math.PI / 2;
  pathMesh.position.set(0.6, 0.01, 1);
  pathMesh.receiveShadow = true;
  group.add(pathMesh);

  const postMat = new MeshStandardMaterial({ color: 0x9a7a4d, roughness: 0.8 });
  const railMat = new MeshStandardMaterial({ color: 0xb08d5c, roughness: 0.8 });
  for (let side = -1; side <= 1; side += 2) {
    for (let i = 0; i < 5; i++) {
      const post = new Mesh(new CylinderGeometry(0.05, 0.05, 0.7, 8), postMat);
      post.position.set(side * 3.2, 0.35, -4 + i * 2);
      post.castShadow = true;
      group.add(post);
    }
    const rail = new Mesh(new BoxGeometry(0.06, 0.06, 8.2), railMat);
    rail.position.set(side * 3.2, 0.55, -0.2);
    rail.castShadow = true;
    group.add(rail);
  }

  const treeAt = (x, z, s = 1) => {
    const t = new Group();
    const trunk = new Mesh(
      new CylinderGeometry(0.09 * s, 0.12 * s, 1.1 * s, 8),
      new MeshStandardMaterial({ color: 0x6b4a2f, roughness: 0.9 }),
    );
    trunk.position.y = 0.55 * s;
    trunk.castShadow = true;
    t.add(trunk);
    const leaves = new Mesh(
      new SphereGeometry(0.55 * s, 12, 10),
      new MeshStandardMaterial({ color: 0x5f9c48, roughness: 0.95 }),
    );
    leaves.position.y = 1.25 * s;
    leaves.castShadow = true;
    t.add(leaves);
    t.position.set(x, 0, z);
    return t;
  };
  group.add(treeAt(-3.4, -2.5, 1.2));
  group.add(treeAt(3.4, -3, 1));
  group.add(treeAt(-2.6, -5, 0.8));

  if (variant === "contest") {
    const podium = new Group();
    const tierMat = new MeshStandardMaterial({
      color: 0xdba53c,
      roughness: 0.6,
      metalness: 0.15,
    });
    [0.9, 0.6, 0.9].forEach((h, i) => {
      const tier = new Mesh(new CylinderGeometry(0.55, 0.6, h, 16), tierMat);
      tier.position.set(-2.3 + i * 1.1, h / 2, -2.4);
      tier.castShadow = true;
      tier.receiveShadow = true;
      podium.add(tier);
    });
    const ribbon = new Mesh(
      new TorusGeometry(0.14, 0.045, 10, 20),
      new MeshStandardMaterial({ color: 0xd23a5c, roughness: 0.4 }),
    );
    ribbon.position.set(-1.2, 1.55, -2.4);
    podium.add(ribbon);
    group.add(podium);
  }

  return group;
}

// ---------- projectile / prop / particle systems ----------

function makeToyTexture(kind) {
  const c = makeCanvas(64, 64);
  const g = c.getContext("2d");
  if (kind === "ball") {
    g.fillStyle = "#e94b4b";
    g.fillRect(0, 0, 64, 32);
    g.fillStyle = "#f7f4ea";
    g.fillRect(0, 32, 64, 32);
    g.strokeStyle = "#20242c";
    g.lineWidth = 3;
    g.beginPath();
    g.moveTo(0, 32);
    g.lineTo(64, 32);
    g.stroke();
  } else {
    g.fillStyle = "#4fb3d9";
    g.fillRect(0, 0, 64, 64);
    g.strokeStyle = "#ffffff";
    g.lineWidth = 4;
    g.beginPath();
    g.arc(32, 32, 22, 0, Math.PI * 2);
    g.stroke();
  }
  return canvasTexture(c);
}

function makeBowlMesh(kind) {
  const group = new Group();
  const bowl = new Mesh(
    new CylinderGeometry(0.22, 0.16, 0.12, 20, 1, true),
    new MeshStandardMaterial({
      color: 0xdedad0,
      roughness: 0.5,
      side: DoubleSide,
    }),
  );
  bowl.castShadow = true;
  bowl.receiveShadow = true;
  group.add(bowl);
  const fillColor = kind === "water" ? 0x5fb6e0 : 0xa87747;
  const fill = new Mesh(
    new CircleGeometry(0.2, 20),
    new MeshStandardMaterial({
      color: fillColor,
      roughness: kind === "water" ? 0.1 : 0.85,
    }),
  );
  fill.rotation.x = -Math.PI / 2;
  fill.position.y = 0.045;
  group.add(fill);
  if (kind === "food") {
    for (let i = 0; i < 8; i++) {
      const crumb = new Mesh(
        new SphereGeometry(0.025, 6, 6),
        new MeshStandardMaterial({ color: 0x8a5a2e, roughness: 0.9 }),
      );
      crumb.position.set(
        (Math.random() - 0.5) * 0.28,
        0.06,
        (Math.random() - 0.5) * 0.28,
      );
      group.add(crumb);
    }
  }
  return group;
}

// ---------- main entry point ----------

export function createScene(
  container,
  { onPet, onGesture, onReady, onError } = {},
) {
  const errorOut = (err) => {
    try {
      onError && onError(err);
    } catch {
      /* ignore listener errors */
    }
  };

  const scene = new Scene();
  scene.background = new Color(0xcfe6cf);
  scene.fog = new Fog(0xcfe6cf, 9, 20);

  const camera = new PerspectiveCamera(38, 1, 0.1, 60);
  camera.position.copy(CAMERA_POS);
  camera.lookAt(CAMERA_LOOK);

  let renderer;
  try {
    renderer = new WebGLRenderer({ antialias: true, alpha: false });
  } catch (err) {
    errorOut(
      new Error(
        `WebGL renderer failed to initialize: ${err && err.message ? err.message : err}`,
      ),
    );
    return {
      setSpecies: () => Promise.reject(new Error("renderer unavailable")),
      setMode: () => {},
      react: () => {},
      setTool: () => {},
      dispose: () => {},
    };
  }
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = PCFSoftShadowMap;
  renderer.toneMapping = ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.domElement.style.width = "100%";
  renderer.domElement.style.height = "100%";
  renderer.domElement.style.display = "block";
  renderer.domElement.style.touchAction = "none";
  container.appendChild(renderer.domElement);

  const webglLostHandler = (e) => {
    e.preventDefault();
    errorOut(new Error("WebGL context lost"));
  };
  renderer.domElement.addEventListener("webglcontextlost", webglLostHandler);

  // lighting: warm hemisphere fill + a directional "sun" through the window, casting contact shadows
  const hemi = new HemisphereLight(0xfff3d6, 0x4a5a3e, 0.65);
  scene.add(hemi);
  const sun = new DirectionalLight(0xfff0cf, 1.35);
  sun.position.set(2.6, 4.2, 2.2);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  sun.shadow.camera.near = 0.5;
  sun.shadow.camera.far = 12;
  sun.shadow.camera.left = -4;
  sun.shadow.camera.right = 4;
  sun.shadow.camera.top = 4;
  sun.shadow.camera.bottom = -4;
  sun.shadow.bias = -0.0025;
  scene.add(sun);
  const rim = new AmbientLight(0xffffff, 0.25);
  scene.add(rim);

  const tex = getRoomTextures();
  const shadowBlob = new Mesh(
    new PlaneGeometry(1.1, 1.1),
    new MeshBasicMaterial({
      map: tex.shadowBlob,
      transparent: true,
      depthWrite: false,
    }),
  );
  shadowBlob.rotation.x = -Math.PI / 2;
  shadowBlob.position.set(CHAR_ANCHOR.x, 0.005, CHAR_ANCHOR.z);
  scene.add(shadowBlob);

  const environmentGroup = new Group();
  scene.add(environmentGroup);
  let currentMode = null; // no environment built yet; forces the initial setEnvironment('home') call below to run
  let bathTexPromise = null;

  const characterHolder = new Group();
  characterHolder.position.copy(CHAR_ANCHOR);
  scene.add(characterHolder);

  const manager = makeLoadingManager(errorOut);

  let current = null; // { species, wrapper, root, rig, animator }
  let currentSpecies = null;
  let speciesRequest = 0;
  let clockStart = performance.now();
  let walkPaused = false,
    encounterVersion = 0,
    visitor = null,
    gift = null;
  function clearEncounter() {
    encounterVersion++;
    if (visitor) {
      scene.remove(visitor);
      visitor = null;
    }
    if (gift) {
      scene.remove(gift);
      disposeGroup(gift);
      gift = null;
    }
  }
  function showGift() {
    gift = new Group();
    const paper = new Mesh(
      new BoxGeometry(0.36, 0.32, 0.36),
      new MeshStandardMaterial({ color: 0xfff8dc }),
    );
    paper.position.y = 0.16;
    gift.add(paper);
    for (const [x, z] of [
      [0.07, 0.37],
      [0.37, 0.07],
    ]) {
      const ribbon = new Mesh(
        new BoxGeometry(x, 0.33, z),
        new MeshStandardMaterial({ color: 0xc84137 }),
      );
      ribbon.position.y = 0.17;
      gift.add(ribbon);
    }
    gift.position.set(CHAR_ANCHOR.x - 0.6, 0, CHAR_ANCHOR.z + 0.5);
    scene.add(gift);
  }
  async function showVisitor() {
    const version = encounterVersion;
    const species = currentSpecies === "pikachu" ? "mudkip" : "pikachu";
    const source = await loadCharacter(species, manager, errorOut);
    if (version !== encounterVersion || currentMode !== "walk") return;
    visitor = cloneSkeleton(source.wrapper);
    visitor.scale.multiplyScalar(0.72);
    visitor.position.set(-0.7, 0, -0.65);
    visitor.rotation.y = source.baseRotation + 0.45;
    scene.add(visitor);
  }

  function setEnvironment(mode) {
    if (mode === currentMode) return; // same-mode setMode calls must not tear down/rebuild the shell
    disposeGroup(environmentGroup);
    while (environmentGroup.children.length)
      environmentGroup.remove(environmentGroup.children[0]);
    currentMode = mode;

    if (mode === "bath") {
      if (!bathTexPromise)
        bathTexPromise = buildBathTiles().catch((err) => {
          errorOut(err);
          return null;
        });
      bathTexPromise.then((bathTex) => {
        if (currentMode !== "bath") return;
        environmentGroup.add(
          bathTex ? buildBathShell(bathTex) : buildIndoorShell(tex),
        );
      });
      return;
    }
    if (mode === "walk" || mode === "park" || mode === "contest") {
      environmentGroup.add(buildOutdoorShell(tex, mode));
      return;
    }
    // home / kennel share the indoor room shell
    environmentGroup.add(buildIndoorShell(tex, { warm: true }));
    if (mode === "kennel") environmentGroup.add(buildKennelExtras(tex));
  }
  setEnvironment("home");

  // ---------- toys / props / particles ----------
  const toyTextures = {
    ball: makeToyTexture("ball"),
    disc: makeToyTexture("disc"),
  };
  let activeToy = null; // { mesh, kind, phase: 'flying'|'returning', t, from, to, duration }
  let bowlMesh = null;
  let bowlTimer = 0;
  // Foam blobs share one unit-radius sphere geometry + material; each blob only
  // varies its mesh scale for radius. The shared pair is disposed exactly once
  // in dispose() — never per removed mesh, since that would free GPU resources
  // still referenced by every other live foam blob.
  const foamGeometry = new SphereGeometry(1, 8, 8);
  const foamMaterial = new MeshStandardMaterial({
    color: 0xffffff,
    roughness: 0.5,
    transparent: true,
    opacity: 0.92,
  });
  const foamBlobs = []; // { mesh, life }
  const waterDrops = []; // { mesh, life, vy }
  const bubbles = []; // detached decorative bubbles { sprite, vy, life, maxLife }

  function clearToy() {
    if (activeToy) {
      scene.remove(activeToy.mesh);
      disposeGroup(activeToy.mesh);
      activeToy = null;
    }
  }
  function clearBowl() {
    if (bowlMesh) {
      scene.remove(bowlMesh);
      disposeGroup(bowlMesh);
      bowlMesh = null;
    }
  }
  function clearFoam() {
    // Blobs share foamGeometry/foamMaterial — detach only, never dispose per-mesh.
    foamBlobs.forEach((f) => characterHolder.remove(f.mesh));
    foamBlobs.length = 0;
  }

  function spawnFoam(localPoint) {
    if (foamBlobs.length >= 50) {
      const oldest = foamBlobs.shift();
      characterHolder.remove(oldest.mesh);
    }
    const blob = new Mesh(foamGeometry, foamMaterial);
    blob.scale.setScalar(0.07 + Math.random() * 0.04);
    blob.position.copy(localPoint);
    blob.position.x += (Math.random() - 0.5) * 0.08;
    blob.position.y += (Math.random() - 0.5) * 0.08;
    characterHolder.add(blob);
    foamBlobs.push({ mesh: blob });
  }

  function spawnWaterDrop(localPoint) {
    const drop = new Mesh(
      new SphereGeometry(0.02, 6, 6),
      new MeshStandardMaterial({
        color: 0x8fd4f5,
        transparent: true,
        opacity: 0.8,
        roughness: 0.1,
      }),
    );
    drop.position.copy(localPoint);
    characterHolder.add(drop);
    waterDrops.push({ mesh: drop, life: 0.6, vy: -0.6 - Math.random() * 0.4 });
  }

  function spawnBubbles(worldPoint) {
    for (let i = 0; i < 6; i++) {
      const sprite = new Sprite(
        new SpriteMaterial({
          map: tex.bubble,
          transparent: true,
          depthWrite: false,
        }),
      );
      const s = 0.12 + Math.random() * 0.1;
      sprite.scale.set(s, s, 1);
      sprite.position.set(
        worldPoint.x + (Math.random() - 0.5) * 0.2,
        worldPoint.y + (Math.random() - 0.5) * 0.1,
        worldPoint.z + (Math.random() - 0.5) * 0.2,
      );
      scene.add(sprite);
      bubbles.push({
        sprite,
        vy: 0.35 + Math.random() * 0.35,
        life: 0,
        maxLife: 1.6 + Math.random() * 1.2,
        drift: (Math.random() - 0.5) * 0.3,
      });
      if (bubbles.length > 60) {
        const old = bubbles.shift();
        scene.remove(old.sprite);
        old.sprite.material.dispose();
      }
    }
  }

  function throwToy(kind, worldTarget) {
    clearToy();
    const from = characterHolder.position
      .clone()
      .add(new Vector3(0.3, 1.1, 0.5));
    const mesh = new Mesh(
      kind === "disc"
        ? new CylinderGeometry(0.14, 0.14, 0.035, 20)
        : new SphereGeometry(0.11, 16, 12),
      new MeshStandardMaterial({ map: toyTextures[kind], roughness: 0.4 }),
    );
    mesh.castShadow = true;
    mesh.position.copy(from);
    scene.add(mesh);
    activeToy = {
      mesh,
      kind,
      phase: "flying",
      t: 0,
      from,
      to: worldTarget.clone(),
      duration: 0.7,
      homePos: characterHolder.position.clone(),
    };
    onGesture && onGesture("throw");
  }

  // ---------- pointer interaction ----------

  const raycaster = new Raycaster();
  const pointerNDC = new Vector2();
  const floorForRay = new PlaneGeometry(40, 40);
  const floorRayMesh = new Mesh(
    floorForRay,
    new MeshBasicMaterial({ visible: false }),
  );
  floorRayMesh.rotation.x = -Math.PI / 2;
  scene.add(floorRayMesh);

  let currentTool = "pet";
  let dragState = null; // { pointerId, startX, startY, lastX, lastY, onCharacter, moved }

  function setPointerFromEvent(ev) {
    const rect = renderer.domElement.getBoundingClientRect();
    pointerNDC.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
    pointerNDC.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;
  }

  function raycastCharacter() {
    if (!current) return null;
    raycaster.setFromCamera(pointerNDC, camera);
    const hits = raycaster.intersectObject(current.wrapper, true);
    return hits.length ? hits[0] : null;
  }

  function raycastFloor() {
    raycaster.setFromCamera(pointerNDC, camera);
    const hits = raycaster.intersectObject(floorRayMesh, false);
    return hits.length ? hits[0].point : null;
  }

  function onPointerDown(ev) {
    if (ev.target !== renderer.domElement) return;
    setPointerFromEvent(ev);
    renderer.domElement.setPointerCapture?.(ev.pointerId);

    if (currentTool === "ball" || currentTool === "disc") {
      const p = raycastFloor();
      if (p) throwToy(currentTool, p);
      return;
    }
    if (currentTool === "food" || currentTool === "water") {
      clearBowl();
      bowlMesh = makeBowlMesh(currentTool);
      bowlMesh.position.set(
        characterHolder.position.x + 0.55,
        0,
        characterHolder.position.z + 0.35,
      );
      scene.add(bowlMesh);
      bowlTimer = 6;
      current?.animator.play(currentTool === "food" ? "eat" : "drink");
      return;
    }
    if (currentTool === "bubbles") {
      raycaster.setFromCamera(pointerNDC, camera);
      const p = raycaster.ray.at(
        camera.position.distanceTo(characterHolder.position) * 0.75,
        new Vector3(),
      );
      p.y = Math.max(0.2, p.y);
      spawnBubbles(p);
      return;
    }

    const hit = raycastCharacter();
    dragState = {
      pointerId: ev.pointerId,
      startX: ev.clientX,
      startY: ev.clientY,
      lastX: ev.clientX,
      lastY: ev.clientY,
      onCharacter: !!hit,
      moved: false,
    };
  }

  function onPointerMove(ev) {
    if (!dragState || ev.pointerId !== dragState.pointerId) return;
    setPointerFromEvent(ev);
    const dx = ev.clientX - dragState.lastX;
    const dy = ev.clientY - dragState.lastY;
    const moveDist = Math.hypot(dx, dy);
    if (moveDist < 2) return;
    dragState.lastX = ev.clientX;
    dragState.lastY = ev.clientY;
    dragState.moved = true;

    if (!dragState.onCharacter) return;
    const hit = raycastCharacter();
    if (!hit) return;

    if (currentTool === "pet" || currentTool === "brush") {
      onPet && onPet();
    } else if (currentTool === "sponge") {
      const local = characterHolder.worldToLocal(hit.point.clone());
      spawnFoam(local);
      onGesture && onGesture("wash", 1);
    } else if (currentTool === "shower") {
      const local = characterHolder.worldToLocal(hit.point.clone());
      spawnWaterDrop(local);
      if (foamBlobs.length) {
        const removed = foamBlobs.splice(0, Math.min(2, foamBlobs.length));
        removed.forEach((f) => characterHolder.remove(f.mesh));
      }
      onGesture && onGesture("rinse", 1);
    }
  }

  function onPointerUp(ev) {
    if (!dragState || ev.pointerId !== dragState.pointerId) {
      dragState = null;
      return;
    }
    const totalDX = ev.clientX - dragState.startX;
    const totalDY = ev.clientY - dragState.startY;
    const dist = Math.hypot(totalDX, totalDY);

    const gestureTool = currentTool === "pet" || currentTool === "brush";
    if (dragState.onCharacter && gestureTool && dist > 28) {
      const angle = Math.atan2(Math.abs(totalDY), Math.abs(totalDX));
      const vertical = angle > Math.PI / 4;
      if (vertical && totalDY > 0) {
        onGesture && onGesture("sit");
      } else if (vertical && totalDY < 0) {
        onGesture && onGesture("jump");
      } else if (!vertical) {
        onGesture && onGesture("spin");
      }
    } else if (
      dragState.onCharacter &&
      !dragState.moved &&
      (currentTool === "pet" || currentTool === "brush")
    ) {
      onPet && onPet();
    }
    dragState = null;
  }

  function onPointerCancel() {
    dragState = null;
  }

  renderer.domElement.addEventListener("pointerdown", onPointerDown);
  renderer.domElement.addEventListener("pointermove", onPointerMove);
  renderer.domElement.addEventListener("pointerup", onPointerUp);
  renderer.domElement.addEventListener("pointercancel", onPointerCancel);

  // ---------- resize ----------

  function resize() {
    const w = container.clientWidth || 1;
    const h = container.clientHeight || 1;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(w, h, false);
    const aspect = w / h;
    camera.aspect = aspect;

    if (aspect < 1) {
      // Narrow/portrait viewports (e.g. phones): the desktop framing holds a
      // fixed vertical FOV, so horizontal FOV shrinks with aspect and clips
      // the character off the right edge. Back the camera off along its
      // existing desktop viewing direction and re-center the look target on
      // the character's own anchor (instead of the desktop-tuned, off-center
      // CAMERA_LOOK) so the full ~2-unit-tall model stays framed.
      const vFov = MathUtils.degToRad(camera.fov);
      const hFov = 2 * Math.atan(Math.tan(vFov / 2) * aspect);
      const targetWidth = TARGET_HEIGHT * 1.15;
      const desktopDistance = CAMERA_POS.distanceTo(CAMERA_LOOK);
      const fitDistance = Math.max(
        targetWidth / 2 / Math.tan(hFov / 2),
        desktopDistance,
      );
      const dir = CAMERA_POS.clone().sub(CAMERA_LOOK).normalize();
      const look = new Vector3(CHAR_ANCHOR.x, CAMERA_LOOK.y, CAMERA_LOOK.z);
      camera.position.copy(look).addScaledVector(dir, fitDistance);
      camera.lookAt(look);
    } else {
      camera.position.copy(CAMERA_POS);
      camera.lookAt(CAMERA_LOOK);
    }

    camera.updateProjectionMatrix();
  }
  const resizeObserver = new ResizeObserver(resize);
  resizeObserver.observe(container);
  resize();

  // ---------- animation loop ----------

  // Reused every frame to avoid per-frame Vector3 allocation while a toy is airborne/returning.
  const _toyPos = new Vector3();
  const _toyMeshOffset = new Vector3(0.25, 0.5, 0.4);

  function stepToy(dt) {
    if (!activeToy) return;
    activeToy.t += dt;
    if (activeToy.phase === "flying") {
      const p = Math.min(1, activeToy.t / activeToy.duration);
      _toyPos.copy(activeToy.from).lerp(activeToy.to, p);
      _toyPos.y += Math.sin(p * Math.PI) * 0.9;
      activeToy.mesh.position.copy(_toyPos);
      activeToy.mesh.rotation.x += dt * 10;
      if (p >= 1) {
        activeToy.phase = "chasing";
        activeToy.t = 0;
        activeToy.chaseFrom = characterHolder.position.clone();
        current?.animator.play("happy");
      }
    } else if (activeToy.phase === "chasing") {
      const dist = activeToy.chaseFrom.distanceTo(activeToy.to);
      const dur = MathUtils.clamp(dist / 2.4, 0.4, 2.2);
      const p = Math.min(1, activeToy.t / dur);
      characterHolder.position.lerpVectors(
        activeToy.chaseFrom,
        activeToy.to,
        easeInOut(p),
      );
      shadowBlob.position.set(
        characterHolder.position.x,
        0.005,
        characterHolder.position.z,
      );
      if (p >= 1) {
        activeToy.phase = "returning";
        activeToy.t = 0;
      }
    } else if (activeToy.phase === "returning") {
      const dur = 1.1;
      const p = Math.min(1, activeToy.t / dur);
      characterHolder.position.lerpVectors(
        activeToy.to,
        activeToy.homePos,
        easeInOut(p),
      );
      shadowBlob.position.set(
        characterHolder.position.x,
        0.005,
        characterHolder.position.z,
      );
      activeToy.mesh.position
        .copy(characterHolder.position)
        .add(_toyMeshOffset);
      if (p >= 1) {
        characterHolder.position.copy(activeToy.homePos);
        clearToy();
      }
    }
  }

  function stepParticles(dt) {
    for (let i = waterDrops.length - 1; i >= 0; i--) {
      const d = waterDrops[i];
      d.life -= dt;
      d.mesh.position.y += d.vy * dt;
      d.mesh.material.opacity = MathUtils.clamp(d.life / 0.6, 0, 0.8);
      if (d.life <= 0) {
        characterHolder.remove(d.mesh);
        disposeGroup(d.mesh);
        waterDrops.splice(i, 1);
      }
    }
    for (let i = bubbles.length - 1; i >= 0; i--) {
      const b = bubbles[i];
      b.life += dt;
      b.sprite.position.y += b.vy * dt;
      b.sprite.position.x += b.drift * dt;
      const p = b.life / b.maxLife;
      b.sprite.material.opacity =
        p < 0.15 ? p / 0.15 : Math.max(0, 1 - (p - 0.15) / 0.85);
      if (b.life >= b.maxLife) {
        scene.remove(b.sprite);
        b.sprite.material.dispose();
        bubbles.splice(i, 1);
      }
    }
    if (bowlMesh) {
      bowlTimer -= dt;
      if (bowlTimer <= 0) clearBowl();
    }
  }

  let raf = true;
  renderer.setAnimationLoop(() => {
    if (!raf) return;
    const now = performance.now();
    const t = (now - clockStart) / 1000;
    const dt = Math.min(
      0.05,
      (renderer._lastT ? now - renderer._lastT : 16) / 1000,
    );
    renderer._lastT = now;

    if (current) {
      const sitting = current.animator.isSitting;
      current.animator.update(
        dt,
        t,
        sitting ? 0.4 : 1,
        currentMode === "walk" && !walkPaused,
      );
    }
    stepToy(dt);
    stepParticles(dt);

    renderer.render(scene, camera);
  });

  // ---------- public API ----------

  async function setSpecies(species) {
    if (!MODEL_SOURCES[species]) throw new Error(`Unknown species: ${species}`);
    const request = ++speciesRequest;
    if (currentSpecies === species && current) return;
    let loaded;
    try {
      loaded = await loadCharacter(species, manager, errorOut);
      if (request !== speciesRequest) return;
    } catch (err) {
      errorOut(err);
      throw err;
    }
    if (current) {
      characterHolder.remove(current.wrapper);
    }
    currentSpecies = species;
    current = { ...loaded, animator: createAnimator(loaded) };
    characterHolder.add(current.wrapper);
    characterHolder.position.copy(CHAR_ANCHOR);
    shadowBlob.position.set(CHAR_ANCHOR.x, 0.005, CHAR_ANCHOR.z);
  }

  function setMode(mode) {
    clearEncounter();
    walkPaused = false;
    setEnvironment(mode);
  }

  function react(action) {
    if (!current) return;
    if (action === "gift" || action === "greet") {
      clearEncounter();
      walkPaused = true;
      current.animator.play("happy");
      if (action === "gift") showGift();
      else showVisitor().catch(errorOut);
      return;
    }
    if (action === "walk") {
      clearEncounter();
      walkPaused = false;
      current.animator.play("call");
      return;
    }
    if (action === "sit") {
      current.animator.play("sit");
      return;
    }
    if (action === "throw") {
      const target = characterHolder.position
        .clone()
        .add(new Vector3((Math.random() - 0.5) * 1.6, 0, -1.6 - Math.random()));
      throwToy(currentTool === "disc" ? "disc" : "ball", target);
      return;
    }
    current.animator.play(action);
  }

  function setTool(tool) {
    currentTool = tool;
    if (tool === "food" || tool === "water") {
      clearBowl();
      bowlMesh = makeBowlMesh(tool);
      bowlMesh.position.set(
        characterHolder.position.x + 0.35,
        0,
        characterHolder.position.z + 0.65,
      );
      scene.add(bowlMesh);
      bowlTimer = 6;
    } else {
      clearBowl();
    }
    if (tool === "pet") {
      clearFoam();
      clearToy();
      characterHolder.position.copy(CHAR_ANCHOR);
      shadowBlob.position.set(CHAR_ANCHOR.x, 0.005, CHAR_ANCHOR.z);
    }
  }

  function dispose() {
    raf = false;
    speciesRequest++; // invalidate any in-flight setSpecies load so it can't touch a disposed scene
    clearEncounter(); // also bumps encounterVersion, invalidating any in-flight showVisitor load
    renderer.setAnimationLoop(null);
    resizeObserver.disconnect();
    renderer.domElement.removeEventListener("pointerdown", onPointerDown);
    renderer.domElement.removeEventListener("pointermove", onPointerMove);
    renderer.domElement.removeEventListener("pointerup", onPointerUp);
    renderer.domElement.removeEventListener("pointercancel", onPointerCancel);
    renderer.domElement.removeEventListener(
      "webglcontextlost",
      webglLostHandler,
    );
    clearToy();
    clearBowl();
    clearFoam();
    bubbles.forEach((b) => {
      scene.remove(b.sprite);
      b.sprite.material.dispose();
    });
    bubbles.length = 0;
    foamGeometry.dispose();
    foamMaterial.dispose();
    toyTextures.ball.dispose();
    toyTextures.disc.dispose();
    disposeGroup(environmentGroup);
    // current.wrapper (if any) lives in the module-level characterCache and is
    // shared by every scene instance for this species — detach it before the
    // generic sweep so disposeGroup(scene) never frees cached GPU resources
    // that other scene instances (or a future reload) still depend on.
    scene.remove(characterHolder);
    disposeGroup(scene);
    renderer.dispose();
    if (renderer.domElement.parentNode === container)
      container.removeChild(renderer.domElement);
  }

  onReady && onReady({ notes: IDLE_ANIM_NOTES });

  return { setSpecies, setMode, react, setTool, dispose };
}
