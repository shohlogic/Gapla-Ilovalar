// Gapla (G44, 2026-11-12): eski brend rasmlari tekshiruvi — rasm nomi o'zgarsa ham, SVG ichiga yashirilsa ham ushlanadi.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const iz = require("../scripts/gapla-iz-tekshir.js");

const xesh = (b) => crypto.createHash("sha256").update(b).digest("hex").slice(0, 16);
const ESKI = Buffer.from("eski-brend-rasmi");
const YANGI = Buffer.from("gapla-rasmi");

function kod({ yon = true } = {}) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "gapla-iz-"));
  fs.mkdirSync(path.join(d, "src", "assets"), { recursive: true });
  fs.mkdirSync(path.join(d, "resources", "nsis"), { recursive: true });
  fs.writeFileSync(path.join(d, "resources", "nsis", "yon.bmp"), YANGI);
  fs.writeFileSync(
    path.join(d, "gapla-taqiqlangan.json"),
    JSON.stringify({ manzillar: [], nomlar: [], istisnolar: [], eski_rasmlar: { [xesh(ESKI)]: "eski logo" } })
  );
  fs.writeFileSync(
    path.join(d, "electron-builder.json"),
    JSON.stringify({
      win: { icon: "src/assets/icon.ico" },
      nsis: yon ? { installerSidebar: "resources/nsis/yon.bmp", uninstallerSidebar: "resources/nsis/yon.bmp" } : {},
    })
  );
  fs.writeFileSync(path.join(d, "gapla-rasmlar.json"), JSON.stringify({ korilgan: { [xesh(YANGI)]: "yon.bmp" } }));
  return d;
}

test("eski brend rasmi boshqa nom bilan qaytsa ushlanadi", () => {
  const d = kod();
  fs.writeFileSync(path.join(d, "src", "assets", "yangi-nom.webp"), ESKI);
  const t = iz.rasmlarniTekshir(d);
  assert.equal(t.length, 1);
  assert.match(t[0], /yangi-nom\.webp {2}eski brend rasmi/);
});

test("SVG ichiga base64 bilan joylangan eski rasm ham ushlanadi", () => {
  const d = kod();
  const svg = `<svg><image href="data:image/png;base64,${ESKI.toString("base64")}"/></svg>`;
  fs.writeFileSync(path.join(d, "src", "assets", "fon.svg"), svg);
  const t = iz.rasmlarniTekshir(d);
  assert.ok(t.some((s) => /fon\.svg#ichki-1 {2}eski brend rasmi/.test(s)), t.join("\n"));
});

test("ko'rilmagan yangi rasm yig'ishni to'xtatadi, --korildi dan keyin o'tadi", () => {
  const d = kod();
  fs.writeFileSync(path.join(d, "src", "assets", "animatsiya.json"), '{"layers":[]}');
  assert.match(iz.rasmlarniTekshir(d).join("\n"), /animatsiya\.json {2}ko'rilmagan rasm/);
  assert.deepEqual(iz.korildi(["src/assets/animatsiya.json"], d), ["src/assets/animatsiya.json"]);
  assert.deepEqual(iz.rasmlarniTekshir(d), []);
});

test("--korildi eski brend rasmini ro'yxatga qo'shmaydi", () => {
  const d = kod();
  fs.writeFileSync(path.join(d, "src", "assets", "logo.png"), ESKI);
  assert.throws(() => iz.korildi(["src/assets/logo.png"], d), /eski brend rasmi/);
});

test("o'rnatuvchi yon rasmi berilmasa (NSIS logosi chiqadi) ushlanadi", () => {
  const d = kod({ yon: false });
  const t = iz.rasmlarniTekshir(d).join("\n");
  assert.match(t, /nsis\.installerSidebar yo'q/);
  assert.match(t, /nsis\.uninstallerSidebar yo'q/);
});

test("haqiqiy kodda eski brend rasmi va ko'rilmagan rasm yo'q", () => {
  assert.deepEqual(iz.rasmlarniTekshir(), []);
});

test("eski brend rangi (ko'k-binafsha) kodga qaytsa ushlanadi, istisno faqat o'z faylida", () => {
  const d = kod();
  const t = JSON.parse(fs.readFileSync(path.join(d, "gapla-taqiqlangan.json"), "utf8"));
  t.eski_ranglar = { qiymatlar: ["#4577e9", "oklch(0.65 0.2 260", "rgba(37,99,235"] };
  t.istisnolar = [{ fayl: "src/icon.svg", matn: "4577E9", sabab: "boshqa xizmat belgisi" }];
  fs.writeFileSync(path.join(d, "gapla-taqiqlangan.json"), JSON.stringify(t));
  fs.writeFileSync(path.join(d, "src", "a.css"), ":root { --x: #4577E9; }\n.b { color: oklch(0.65  0.2 260 / 0.5); }\n");
  fs.writeFileSync(path.join(d, "src", "c.tsx"), 'const s = "drop-shadow-[0_2px_8px_rgba(37, 99, 235,0.18)]";\n');
  fs.writeFileSync(path.join(d, "src", "icon.svg"), '<svg><path fill="#4577E9"/></svg>\n');
  fs.writeFileSync(path.join(d, "src", "ok.css"), ".d { color: #bc4b1c; background: oklch(0.65 0.22 60); }\n");
  const r = iz.ranglarniTekshir(d);
  assert.equal(r.length, 3, r.join("\n"));
  assert.ok(r.some((s) => /a\.css:1 {2}eski brend rangi «#4577e9»/.test(s)));
  assert.ok(r.some((s) => /a\.css:2 .*oklch/.test(s)));
  assert.ok(r.some((s) => /c\.tsx:1 .*rgba\(37,99,235/.test(s)));
});

// src/dist (qurilgan oyna) yig'ishdan oldin beforePack da tekshiriladi; bu yerda faqat manba kodi.
test("haqiqiy manba kodida eski brend rangi yo'q", () => {
  assert.deepEqual(iz.ranglarniTekshir().filter((s) => !s.startsWith("src/dist/")), []);
});
