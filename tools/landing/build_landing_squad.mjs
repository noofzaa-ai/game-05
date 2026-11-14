// Technical Artist, zorx (2026-11-14). Builds the four campfire characters of the landing site
// (zorx.daiyooo.com, server/landing/dashboard/trail.js) from the game's own Studio files, offline.
//
// One small GLB per race (Human, Viking, Elf, Runeborn), assembled the way the game does it in
// client/characters/studio05_character_model.gd:
//   body_<class>.glb (Base_Body + Head_Anime + the 102-joint Studio rig + clips)
//   + the starter hair of the class (logic/card_deck.gd STARTERS: S&S a, GS c, LB e, MG f)
//   + the race head from v1111/race/race_heads.glb (data/races/<id>.json "look"; Head_Anime is removed when a
//     race head is shown, set_race_look; Human keeps Head_Anime)
//   + the race wardrobe (art/armor/race_shared/<race>_{shirt,pants,shoes,armband}.glb) worn over Base_Body,
//     whose covered triangles are left out like _mask_body()/masked_body() (BODY_COVER, dominant bone per vertex)
//   + the race weapon for the class (art/weapons/race_<race>/<class>.glb, + shield.glb for Sword & Shield) and the
//     class gear's other weapon kit that the race file does not replace (_wear_race_weapon: the archer's quiver)
//   + ONE idle clip (the class's states.idle), every other clip removed.
//
// The rig is not changed: every merged mesh is re-pointed at the body's own skin after checking that its joint
// names, order and inverse bind matrices are identical (the Studio delivery guarantees this; we fail loudly if not).
// Vertex positions are NOT quantized (the toon face/hair shader reads bind-pose positions in GLB units, like the
// Studio's anime-face.js, and quantizing positions would also rewrite the inverse binds). Normals, UVs, joints,
// weights and colours are quantized and everything is meshopt-compressed (EXT_meshopt_compression, decoded by
// three.js r165 with meshopt_decoder.module.js). Textures: base colour only (the toon look ignores PBR maps),
// at most 512 px, WebP (EXT_texture_webp).
//
// Run (from the repo root):  cd tools/landing && npm install && node build_landing_squad.mjs
// Output: server/landing/dashboard/assets/squad_<race>.glb; tools/landing/squad_manifest.json (sizes, triangles, checks).
import { NodeIO, Document } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, dedup, resample, textureCompress, meshopt, quantize, reorder, weld, unpartition, joinPrimitives } from '@gltf-transform/functions';
import { MeshoptEncoder, MeshoptDecoder } from 'meshoptimizer';
import sharp from 'sharp';
import { createHash } from 'node:crypto';
import { writeFileSync, statSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const R = p => path.join(ROOT, p);
const OUT = R('server/landing/dashboard/assets');
const IDLE_FPS = 30; // the idle clips are keyed at 60 fps; 30 fps is invisible on an idle and halves the keys
const TEX = 512;

// One card per race, the class the hub target image gives each race (H sword & shield, V great sword,
// E longbow, R magic). Hair = the class starter hair; skin / eyes = the game defaults (natural, turquoise).
const SQUAD = [
  { race: 'human', cls: 'sword_shield', hair: 'art/characters/studio05/split/hair_a.glb', idle: 'idle', extra: ['art/weapons/race_human/shield.glb'] },
  { race: 'viking', cls: 'greatsword', hair: 'art/characters/studio05/split/hair_c.glb', idle: 'gs_idle' },
  { race: 'elf', cls: 'longbow', hair: 'art/characters/studio05/split/hair_e.glb', idle: 'lb_idle_01' },
  { race: 'runeborn', cls: 'magic', hair: 'art/characters/studio05/split/hair_f_magic.glb', idle: 'mg_loco_idle' },
];
const GEAR = { sword_shield: 'armor_sword_shield', greatsword: 'armor_greatsword', longbow: 'armor_longbow', magic: 'armor_magic' };
const WEAPON = /\| (Sword|Shield|Bow|Quiver|Staff|Spellbook)\b/;
// studio05_character_model.gd BODY_COVER (all four wardrobe slots are worn, so "shirt+armband" applies too).
const BODY_COVER = ['Spine', 'Spine1', 'Spine2', 'LeftShoulder', 'RightShoulder', 'LeftArm', 'RightArm',
  'LeftForeArm', 'RightForeArm', 'LeftHand', 'RightHand', 'HandIndex', 'HandMiddle', 'HandPinky', 'HandRing', 'HandThumb',
  'Hips', 'LeftUpLeg', 'RightUpLeg', 'LeftLeg', 'RightLeg', 'LeftFoot', 'RightFoot', 'LeftToeBase', 'RightToeBase', 'LeftToe_End', 'RightToe_End'];
const covered = name => { const b = name.replace('mixamorig:', '').replace('mixamorig_', ''); return BODY_COVER.some(n => b === n || (n.startsWith('Hand') && b.includes(n))); };
const raceLook = race => JSON.parse(readFileSync(R(`data/races/${race}.json`), 'utf8')).look;

await MeshoptEncoder.ready; await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.encoder': MeshoptEncoder, 'meshopt.decoder': MeshoptDecoder });

const skinKey = skin => {
  const h = createHash('sha1');
  for (const j of skin.listJoints()) h.update(j.getName() + '|');
  h.update(Buffer.from(skin.getInverseBindMatrices().getArray().buffer.slice(0)));
  return h.digest('hex');
};

// Moves the skinned mesh nodes of `file` that `keep(name)` accepts onto `doc`'s skeleton (body skin).
async function mergeOnto(doc, bodySkin, file, keep) {
  const src = await io.read(R(file));
  const srcSkins = src.getRoot().listSkins();
  for (const s of srcSkins) if (skinKey(s) !== skinKey(bodySkin)) throw new Error(`${file}: rig differs from the body (joints or inverse binds)`);
  const keepNodes = src.getRoot().listNodes().filter(n => n.getMesh() && n.getSkin() && keep(n.getName()));
  // Copy only the meshes (with their materials/textures/accessors) into doc.
  const { copyToDocument } = await import('@gltf-transform/functions');
  const map = copyToDocument(doc, src, keepNodes.map(n => n.getMesh()));
  const added = [];
  for (const n of keepNodes) {
    const node = doc.createNode(n.getName()).setMesh(map.get(n.getMesh())).setSkin(bodySkin);
    added.push(node);
  }
  return added;
}

const report = { built: new Date().toISOString(), budget_bytes: 2.5 * 1024 * 1024, characters: [] };
for (const c of SQUAD) {
  const bodyFile = `art/characters/studio05/split/body_${c.cls}.glb`;
  const doc = await io.read(R(bodyFile));
  const root = doc.getRoot();
  const bodySkin = root.listSkins()[0];
  const rigBefore = skinKey(bodySkin);
  const scene = root.listScenes()[0];
  const meshParent = root.listNodes().find(n => n.getMesh() && n.getSkin()).getParentNode() || null;
  const attach = nodes => nodes.forEach(n => (meshParent ? meshParent.addChild(n) : scene.addChild(n)));

  // Hair (replaceCharacterHair) and race head (set_race_look).
  attach(await mergeOnto(doc, bodySkin, c.hair, n => n.startsWith('Hair_')));
  const look = raceLook(c.race);
  if (look.head) {
    const names = [look.head, look.overlay].filter(Boolean);
    attach(await mergeOnto(doc, bodySkin, look.head_file.replace('res://', ''), n => names.includes(n)));
    for (const n of root.listNodes()) if (n.getName() === 'Head_Anime') { n.getMesh().dispose(); n.dispose(); }
  }
  // Race wardrobe over the masked base body (_wear_studio_armor + _mask_body).
  for (const slot of ['shirt', 'pants', 'shoes', 'armband']) attach(await mergeOnto(doc, bodySkin, `art/armor/race_shared/${c.race}_${slot}.glb`, () => true));
  const body = root.listNodes().find(n => n.getName() === 'Base_Body');
  const jointNames = bodySkin.listJoints().map(j => j.getName());
  let removed = 0;
  for (const prim of body.getMesh().listPrimitives()) {
    const J = prim.getAttribute('JOINTS_0'), W = prim.getAttribute('WEIGHTS_0'), I = prim.getIndices();
    const hide = new Uint8Array(J.getCount()); const j = [], w = [];
    for (let v = 0; v < hide.length; v++) { J.getElement(v, j); W.getElement(v, w); let best = 0; for (let k = 1; k < 4; k++) if (w[k] > w[best]) best = k; hide[v] = covered(jointNames[j[best]]) ? 1 : 0; }
    const src = I.getArray(), kept = [];
    for (let t = 0; t < src.length; t += 3) { if (hide[src[t]] && hide[src[t + 1]] && hide[src[t + 2]]) { removed++; continue; } kept.push(src[t], src[t + 1], src[t + 2]); }
    I.setArray(new Uint32Array(kept));
  }
  // Weapons: the race file for the class (+ the race shield for S&S); the class gear keeps the kinds the race
  // files do not bring (_wear_race_weapon). The class suit itself steps aside (a worn wardrobe is on).
  const raceWeapons = [`art/weapons/race_${c.race}/${c.cls}.glb`, ...(c.extra || [])];
  const replaced = new Set();
  for (const f of raceWeapons) {
    const nodes = await mergeOnto(doc, bodySkin, f, () => true);
    nodes.forEach(n => { const k = (n.getName().match(WEAPON) || [])[1]; if (k) replaced.add(k); });
    attach(nodes);
  }
  attach(await mergeOnto(doc, bodySkin, `art/characters/studio05/v1111/outfits/${GEAR[c.cls]}.glb`, n => {
    const k = (n.match(WEAPON) || [])[1];
    return k && !replaced.has(k) && !(k === 'Bow' && replaced.has('Bow'));
  }));

  // One idle clip, renamed "idle".
  for (const a of root.listAnimations()) {
    if (a.getName() === c.idle) { a.setName('idle'); continue; }
    a.listChannels().forEach(ch => ch.dispose()); a.listSamplers().forEach(sm => sm.dispose()); a.dispose();
  }
  if (root.listAnimations().length !== 1) throw new Error(`${c.cls}: idle clip ${c.idle} missing`);
  // 60 fps -> 30 fps keys (exact keyframes kept, no interpolation change).
  const anim = root.listAnimations()[0];
  for (const s of anim.listSamplers()) {
    const input = s.getInput(), output = s.getOutput(); const n = input.getCount(); if (n < 3) continue;
    const size = output.getElementSize(), ti = input.getArray(), to = output.getArray();
    const keepIdx = []; let next = -1;
    for (let i = 0; i < n; i++) { if (i === 0 || i === n - 1 || ti[i] >= next - 1e-4) { keepIdx.push(i); next = ti[i] + 1 / IDLE_FPS; } }
    const ni = new Float32Array(keepIdx.length), no = new Float32Array(keepIdx.length * size);
    keepIdx.forEach((i, k) => { ni[k] = ti[i]; for (let e = 0; e < size; e++) no[k * size + e] = to[i * size + e]; });
    s.setInput(input.clone().setArray(ni)); s.setOutput(output.clone().setArray(no));
  }
  // A channel whose every key equals the joint's rest value moves nothing: drop it (same pose, smaller file).
  let still = 0;
  for (const ch of anim.listChannels()) {
    const node = ch.getTargetNode(), pathName = ch.getTargetPath(); if (!node || pathName === 'weights') continue;
    const rest = pathName === 'rotation' ? node.getRotation() : pathName === 'translation' ? node.getTranslation() : node.getScale();
    const out = ch.getSampler().getOutput().getArray(), size = rest.length;
    let same = true; for (let i = 0; i < out.length && same; i++) same = Math.abs(out[i] - rest[i % size]) < 1e-5;
    if (same) { const sm = ch.getSampler(); ch.dispose(); sm.dispose(); still++; }
  }
  // Toon look uses base colour only: drop normal / metal-rough / occlusion maps.
  for (const m of root.listMaterials()) { m.setNormalTexture(null).setMetallicRoughnessTexture(null).setOcclusionTexture(null); }
  for (const e of root.listExtensionsUsed()) if (['KHR_materials_specular'].includes(e.extensionName)) e.dispose();
  // Drop the TANGENT attributes (no normal maps here).
  for (const m of root.listMeshes()) for (const p of m.listPrimitives()) if (p.getAttribute('TANGENT')) p.setAttribute('TANGENT', null);

  if (skinKey(bodySkin) !== rigBefore) throw new Error('rig changed');
  await doc.transform(unpartition(), prune({ keepLeaves: true }), dedup());
  // Fewer draw calls (each piece is drawn twice on the web: toon + ink outline): body, wardrobe and weapon
  // pieces that share a material and skin are joined into one primitive. The face (Head_Anime*), its rune
  // overlay and the hair stay separate meshes (the page draws the face and hair ink from their names).
  const own = n => /^(Head_Anime|Hair_|Runeborn_Face)/.test(n);
  const groups = new Map();
  for (const n of root.listNodes()) {
    if (!n.getMesh() || own(n.getName())) continue;
    for (const p of n.getMesh().listPrimitives()) {
      const key = p.getMaterial()?.getName() + '|' + p.listSemantics().sort().join(',');
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push({ n, p });
    }
  }
  let joined = 0;
  for (const [key, list] of groups) {
    if (list.length < 2) continue;
    const prim = joinPrimitives(list.map(x => x.p));
    const name = 'Gear_' + (list[0].p.getMaterial()?.getName() || 'mat').replace(/[^A-Za-z0-9]+/g, '_');
    const node = doc.createNode(name).setMesh(doc.createMesh(name).addPrimitive(prim)).setSkin(bodySkin);
    attach([node]);
    for (const { n, p } of list) { n.getMesh()?.removePrimitive(p); p.dispose(); if (n.getMesh() && n.getMesh().listPrimitives().length === 0) { n.getMesh().dispose(); n.dispose(); } }
    joined += list.length;
  }
  await doc.transform(
    prune({ keepLeaves: true }), resample(),
    textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [TEX, TEX], quality: 76 }),
    reorder({ encoder: MeshoptEncoder, target: 'size' }),
    quantize({ pattern: /^(NORMAL|TEXCOORD|JOINTS|WEIGHTS|COLOR)(_\d+)?$/, quantizeNormal: 8, quantizeTexcoord: 12, quantizeColor: 8 }),
  );
  doc.createExtension((await import('@gltf-transform/extensions')).EXTMeshoptCompression).setRequired(true)
    .setEncoderOptions({ method: 'filter' });
  const out = path.join(OUT, `squad_${c.race}.glb`);
  await io.write(out, doc);

  // Re-read and check: same joints / inverse binds as the source body, one clip, triangle count.
  const check = await io.read(out);
  const cs = check.getRoot().listSkins();
  if (cs.length !== 1 || skinKey(cs[0]) !== rigBefore) throw new Error(`${c.race}: rig check failed after write`);
  let tris = 0; const meshes = [];
  for (const n of check.getRoot().listNodes()) if (n.getMesh()) { let t = 0; for (const p of n.getMesh().listPrimitives()) t += (p.getIndices()?.getCount() ?? 0) / 3; tris += t; meshes.push(`${n.getName()} (${t})`); }
  const textures = check.getRoot().listTextures().map(t => `${t.getName() || 'tex'} ${t.getSize()?.join('x')} ${t.getMimeType()} ${t.getImage().byteLength}B`);
  report.characters.push({ race: c.race, class: c.cls, file: path.relative(ROOT, out).replaceAll('\\', '/'), bytes: statSync(out).size, triangles: tris,
    body_triangles_hidden_under_wardrobe: removed, clips: check.getRoot().listAnimations().map(a => a.getName()), idle_channels: check.getRoot().listAnimations()[0].listChannels().length, rest_only_channels_dropped: still, pieces_joined: joined, joints: cs[0].listJoints().length, rig_sha1: rigBefore, meshes, textures });
  console.log(c.race, statSync(out).size, 'bytes', tris, 'tris', meshes.length, 'meshes');
}
report.total_bytes = report.characters.reduce((a, c) => a + c.bytes, 0);
writeFileSync(path.join(ROOT, 'tools/landing/squad_manifest.json'), JSON.stringify(report, null, 1) + '\n');
console.log('total', report.total_bytes, 'bytes (budget', report.budget_bytes, ')');
if (report.total_bytes > report.budget_bytes) { console.error('OVER BUDGET'); process.exit(1); }
