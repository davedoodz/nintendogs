import { mkdir, mkdtemp, access, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);
const native = process.argv.includes("--native");
const root = fileURLToPath(
  new URL(native ? "../mac/Assets/" : "../public/assets/", import.meta.url),
);
const archives = native
  ? [
      [
        "shiba",
        "shiba/aSib_a.nsbmd/Sib_a.dae",
        "https://models.spriters-resource.com/media/assets/313/316384.zip",
      ],
    ]
  : [
      [
        "models/pikachu",
        "models/pikachu/Pikachu/Pikachu.dae",
        "https://models.spriters-resource.com/media/assets/282/284743.zip",
      ],
      [
        "models/mudkip",
        "models/mudkip/Mizugorouout.dae",
        "https://models.spriters-resource.com/media/assets/283/285740.zip",
      ],
      [
        "models/charmander",
        "models/charmander/Charmander/Hitokage.dae",
        "https://models.spriters-resource.com/media/assets/282/284772.zip",
      ],
      [
        "sounds",
        "sounds/menu_select1.wav",
        "https://sounds.spriters-resource.com/media/assets/435/437715.zip",
      ],
    ];
const images = native
  ? []
  : [
      [
        "ui/care.png",
        "https://www.spriters-resource.com/media/assets/71/73785.png",
      ],
      [
        "ui/walk.png",
        "https://www.spriters-resource.com/media/assets/80/83415.png",
      ],
      [
        "ui/bathroom.png",
        "https://textures.spriters-resource.com/media/assets/372/374972.png",
      ],
      ...[
        ["pikachu", 25],
        ["mudkip", 258],
        ["charmander", 4],
      ].map(([name, id]) => [
        `portraits/${name}.png`,
        `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${id}.png`,
      ]),
    ];
async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}
async function download(url, path) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${response.status} fetching ${url}`);
  await writeFile(path, Buffer.from(await response.arrayBuffer()));
}
console.log(
  "Preparing local copyrighted game assets. See README for provenance and rights. Assets are excluded from Git.",
);
await mkdir(root, { recursive: true });
const temp = await mkdtemp(join(tmpdir(), "pokepals-assets-"));
try {
  for (const [dir, check, url] of archives) {
    if (await exists(join(root, check))) continue;
    await mkdir(join(root, dir), { recursive: true });
    const zip = join(temp, "asset.zip");
    await download(url, zip);
    await exec("unzip", ["-o", "-q", zip, "-d", join(root, dir)]);
    await access(join(root, check));
  }
  for (const [file, url] of images) {
    const path = join(root, file);
    if (await exists(path)) continue;
    await mkdir(dirname(path), { recursive: true });
    await download(url, path);
  }
  console.log(
    native
      ? "Shiba models and textures are available locally in mac/Assets."
      : "All three models, portraits, UI sheets and audio are available locally.",
  );
} finally {
  await rm(temp, { recursive: true, force: true });
}
