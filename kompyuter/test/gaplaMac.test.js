// Gapla Mac (G61): oldindagi ilovani tanish (lsappinfo chiqishi) va Lokal rejimni yashirish.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const { parseFrontAsn, parseAppInfo, isRestorableMacTarget } = require("../src/helpers/gaplaMacFront");
const { gaplaModesForThisComputer } = require("../src/helpers/gaplaLocalMode");
const GAPLA = require("../src/constants/gapla.json");

test("lsappinfo front: ilova belgisi (ASN) olinadi", () => {
  assert.equal(parseFrontAsn("ASN:0x0-0x1d01d:\n"), "ASN:0x0-0x1d01d:");
  assert.equal(parseFrontAsn(""), null);
  assert.equal(parseFrontAsn("[ NULL ]"), null);
});

test("lsappinfo info: pid va bundle id — to'liq va -only shakli", () => {
  const toliq = [
    '"TextEdit" ASN:0x0-0x1d01d: ',
    '    bundleID="com.apple.TextEdit"',
    '    bundle path="/System/Applications/TextEdit.app"',
    '    pid = 1234 type="Foreground" flavor=3 Version="1.19" fileType="APPL" creator="ttxt" Arch=ARM64',
  ].join("\n");
  assert.deepEqual(parseAppInfo(toliq), { pid: 1234, bundleId: "com.apple.TextEdit" });
  const only = '"CFBundleIdentifier"="com.tinyspeck.slackmacgap"\n"pid"=987\n';
  assert.deepEqual(parseAppInfo(only), { pid: 987, bundleId: "com.tinyspeck.slackmacgap" });
  assert.deepEqual(parseAppInfo(""), { pid: null, bundleId: null });
});

test("Joylash nishoni: Gapla'ning o'zi yoki chala ma'lumot — yo'q", () => {
  const t = { kind: "mac-app", asn: "ASN:0x0-0x1:", pid: 50, bundleId: "com.apple.TextEdit" };
  assert.equal(isRestorableMacTarget(t, 10), true);
  assert.equal(isRestorableMacTarget(t, 50), false);
  assert.equal(isRestorableMacTarget({ ...t, bundleId: null }, 10), false);
  assert.equal(isRestorableMacTarget({ ...t, kind: "win-hwnd" }, 10), false);
  assert.equal(isRestorableMacTarget(null, 10), false);
});

test("Lokal rejim: model bo'lmasa menyuda yo'q, bo'lsa bor", () => {
  const hammasi = gaplaModesForThisComputer(GAPLA.modes, true).map((m) => m.id);
  const lokalsiz = gaplaModesForThisComputer(GAPLA.modes, false).map((m) => m.id);
  assert.deepEqual(hammasi, ["tez", "orta", "sekin", "lokal"]);
  assert.deepEqual(lokalsiz, ["tez", "orta", "sekin"]);
});
