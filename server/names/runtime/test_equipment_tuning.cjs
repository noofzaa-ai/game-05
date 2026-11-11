// Focused bridge regression: preserves authoritative armor/weight config in public replies.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(process.env.ZORX_RUNTIME_TEST_PATH || path.resolve(__dirname, '../../../build/names-runtime/index.js'), 'utf8'), context);
const tuning = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../../data/items/equipment_tuning.json'), 'utf8'));
const ctx = {env: {ZORX_NAMES_URL: 'http://authority:8051', ZORX_NAMES_TOKEN: 'fixture-token'}};
let response = {code: 200, body: JSON.stringify({...tuning, v: 1, ok: true})};
const nk = {httpRequest(url, method, headers) {
  assert.equal(url, 'http://authority:8051/equipment-config');
  assert.equal(method, 'post');
  assert.equal(headers.Authorization, 'Bearer fixture-token');
  return response;
}};
const result = JSON.parse(JSON.stringify(context.equipmentTuning(ctx, nk)));
assert.deepEqual(result, {version: 1, refine: tuning.refine, upgrade: tuning.upgrade, mobility: tuning.mobility, armor: tuning.armor});
response = {code: 503, body: '{}'};
assert.throws(() => context.equipmentTuning(ctx, nk), /unavailable/);
response = {code: 200, body: 'x'.repeat(65537)};
assert.throws(() => context.equipmentTuning(ctx, nk), /unavailable/);
response = {code: 200, body: JSON.stringify({v: 1, ok: false})};
assert.throws(() => context.equipmentTuning(ctx, nk), /invalid/);
console.log('PASS equipment tuning bridge: exact public fields, transport failure, oversized response, invalid response (4 checks)');

// Login reads persist one trusted migration with CAS; repeat reads must not write/grant again.
response = {code: 200, body: JSON.stringify({...tuning, v: 1, ok: true})};
let stored = {version: 'before', value: {v: 1, revision: 7, receipts: [], rng_state: '123', profile: {
  beta_kit_version: 2, starter_weapon_kit_version: 1, starter_armor_kit_version: 1,
  marker: 'owned gear stays', armor_migration_version: 0, diamonds: 9999, mall_owned: [], stash: {items: []}, vault: {items: []}, loadout: {equipped: {}}
}}};
let migrations = 0, writes = 0;
context.profileWorker = (_ctx, _nk, current) => {
  migrations++;
  return {ok: true, profile: {...current.profile, armor_migration_version: 2}, rng_state: current.rng_state};
};
nk.storageRead = ids => ids[0].collection === context.PROFILE_COLLECTION ? [JSON.parse(JSON.stringify(stored))] : [];
nk.multiUpdate = (_accounts, updates) => {
  writes++;
  assert.equal(updates[0].version, stored.version);
  assert.equal(updates[0].permissionRead, 0);
  assert.equal(updates[0].permissionWrite, 0);
  stored = {version: 'after', value: JSON.parse(JSON.stringify(updates[0].value))};
};
const first = JSON.parse(context.profileGet({...ctx, userId: 'fixture-only'}, {}, nk, '{"v":1}'));
assert.equal(first.ok, true);
assert.equal(first.profile.armor_migration_version, 2);
assert.equal(first.profile.marker, 'owned gear stays');
assert.equal(first.revision, 8);
const second = JSON.parse(context.profileGet({...ctx, userId: 'fixture-only'}, {}, nk, '{"v":1}'));
assert.equal(second.revision, 8);
assert.equal(migrations, 1);
assert.equal(writes, 1);
console.log('PASS login migration persistence: trusted one-time CAS write, revision advanced once, ownership preserved, repeated read unchanged');

// Legacy wave chest collisions trigger exactly one trusted CAS repair on read.
stored.value.profile.stash.items = [{id: 'treasure-123-1'}, {id: 'treasure-123-1'}];
context.profileWorker = (_ctx, _nk, current) => {
 migrations++;
 const profile = JSON.parse(JSON.stringify(current.profile));
 profile.stash.items[1].id += '-recovered-1';
 return {ok: true, profile, rng_state: current.rng_state};
};
const repaired = JSON.parse(context.profileGet({...ctx, userId: 'fixture-only'}, {}, nk, '{"v":1}'));
assert.equal(repaired.ok, true);
assert.equal(repaired.profile.stash.items.length, 2);
assert.notEqual(repaired.profile.stash.items[0].id, repaired.profile.stash.items[1].id);
assert.equal(repaired.revision, 9);
const again = JSON.parse(context.profileGet({...ctx, userId: 'fixture-only'}, {}, nk, '{"v":1}'));
assert.equal(again.revision, 9);
assert.equal(migrations, 2);
assert.equal(writes, 2);
console.log('PASS legacy chest migration trigger, CAS, repeated read idempotency');
