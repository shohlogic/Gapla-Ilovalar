#!/usr/bin/env node
// Gapla: asl loyihaning (OpenWhispr) foydalanuvchi ko'radigan izlari qolmaganini tekshiradi.
// Oddiy Node >= 18, tashqi paket yo'q. Ishga tushirish: node scripts/gapla-iz-tekshir.mjs (kod papkasidan).
// Taqiqlangan so'zlar: gapla-taqiqlangan.txt. Istisnolar: gapla-iz-istisno.txt (fayl:bo'lak # sabab).
// Matn ichidagi (string literal, JSX matni, plist <string>) so'zlar tekshiriladi; izoh va kod nomlariga tegilmaydi.
// Matnni ajratish (tokenizer, fayllar ro'yxati) gapla-matn.mjs da - til tekshiruvi (G51) bilan umumiy.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, readList, stripExpr, lex, lineOfIndex, jsxTexts, collectFiles, walk } from './gapla-matn.mjs';

// Ichki qiymatlar (xotira kalitlari, bundle id, o'zgaruvchi nomlari, sarlavha nomlari) - foydalanuvchi ko'rmaydi.
const INTERNAL = /^(@openwhispr:|openwhispr[_.-]|com\.openwhispr|group\.com\.gizmolabs|com\.gizmolabs|OPENWHISPR_|x-openwhispr|----OpenWhispr)/i;
const TARGET_NAMES = new Set(['OpenWhisprKeyboard', 'OpenWhisprActivity']);
const SWIFT_INFO_KEYS = /^OpenWhispr(AppScheme|ContainingAppBundleIdentifier)$/;
// Ichki identifikatorlar: kichik harfli 'openwhispr' (provayder id), 'openwhispr://' sxemasi, yashirin fayl nomi,
// OpenWhispr bilan boshlanuvchi bitta so'zli nom (OpenWhisprMeetingFinish, OpenWhisprActivity.swift) va [OpenWhisprX] log belgisi.
const INTERNAL_TOKEN = /^(openwhispr|openwhispr:\/\/.*|\.openwhispr[\w.-]*|OpenWhispr[A-Za-z0-9_.-]+)$/;

const banned = readList(path.join(ROOT, 'gapla-taqiqlangan.txt')).map((t) => t.toLowerCase());
if (banned.length === 0) {
  console.error("Xato: gapla-taqiqlangan.txt bo'sh yoki topilmadi.");
  process.exit(2);
}

const allow = readList(path.join(ROOT, 'gapla-iz-istisno.txt')).map((line) => {
  const hashAt = line.indexOf('#');
  const body = (hashAt >= 0 ? line.slice(0, hashAt) : line).trim();
  const reason = hashAt >= 0 ? line.slice(hashAt + 1).trim() : '';
  const colon = body.indexOf(':');
  return { file: body.slice(0, colon).trim(), part: body.slice(colon + 1).trim(), reason, bad: colon < 1 || !reason };
});
const badAllow = allow.filter((a) => a.bad);
if (badAllow.length) {
  console.error("Xato: gapla-iz-istisno.txt da 'fayl:bo'lak # sabab' shakli buzilgan (sabab shart):");
  for (const a of badAllow) console.error('  ' + a.file + ':' + a.part);
  process.exit(2);
}

function hasBanned(s) {
  const low = s.toLowerCase();
  return banned.find((t) => low.includes(t));
}

function isInternal(value, beforeText, fileLang) {
  const v = value.trim();
  if (INTERNAL.test(v)) return true;
  if (INTERNAL_TOKEN.test(v) && !/\s/.test(v)) return true;
  if (/^\[OpenWhispr\w*\]/.test(v)) return true; // log belgisi
  if (TARGET_NAMES.has(v)) return true;
  if (fileLang === 'swift' && SWIFT_INFO_KEYS.test(v)) return true;
  if (fileLang === 'js' && /(\bfrom\s*|\bimport\s*\(?\s*|\brequire\s*\(\s*)$/.test(beforeText)) return true;
  return false;
}

function allowed(rel, value) {
  return allow.some((a) => (rel === a.file || rel.endsWith('/' + a.file)) && value.includes(a.part));
}

const findings = [];
function report(rel, line, value, term) {
  if (allowed(rel, value)) return;
  const shown = value.replace(/\s+/g, ' ').trim();
  findings.push({ rel, line, shown: shown.length > 140 ? shown.slice(0, 137) + '...' : shown, term });
}

function scanScript(file, swift) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const src = fs.readFileSync(file, 'utf8');
  if (!banned.some((t) => src.toLowerCase().includes(t))) return;
  const { lits, code } = lex(src, swift);
  for (const l of lits) {
    if (l.tpl) l.value = stripExpr(l.value);
    const term = hasBanned(l.value);
    if (!term) continue;
    if (isInternal(l.value, l.before, swift ? 'swift' : 'js')) continue;
    const off = l.value.toLowerCase().indexOf(term);
    const extra = (l.value.slice(0, off).match(/\n/g) || []).length;
    report(rel, l.line + extra, l.value, term);
  }
  if (!swift && /\.(tsx|jsx)$/.test(file)) {
    for (const { text, index } of jsxTexts(code)) {
      const term = hasBanned(text);
      if (!term) continue;
      report(rel, lineOfIndex(code, index + text.toLowerCase().indexOf(term)), text, term);
    }
  }
}

function scanPlist(file) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const src = fs.readFileSync(file, 'utf8');
  const re = /<string>([\s\S]*?)<\/string>/g;
  let m;
  while ((m = re.exec(src))) {
    const term = hasBanned(m[1]);
    if (!term || isInternal(m[1], '', 'plist')) continue;
    report(rel, lineOfIndex(src, m.index), m[1], term);
  }
}

// ---- Rasm, video va animatsiya fayllari (G44, 2026-11-12) ----
// Rasm ichidagi yozuvni skript o'qiy olmaydi: shuning uchun har media fayl egasi yoki Claude ko'rib chiqqan
// ro'yxatda (gapla-media-royxat.txt) SHA-256 bilan turadi. Yangi yoki o'zgargan fayl ro'yxatga qo'shilmaguncha
// tekshiruv to'xtaydi. Qo'shimcha: fayl baytlarida taqiqlangan so'z (metadata, Lottie/SVG matni) qidiriladi.
const MEDIA = /\.(png|jpe?g|gif|webp|heic|bmp|tiff?|ico|mp4|mov|m4v|webm|lottie|riv|svg|pdf)$/i;
const mediaList = new Map(
  readList(path.join(ROOT, 'gapla-media-royxat.txt')).map((line) => {
    const [hash, rel] = line.split(/\s+/);
    return [rel, hash];
  }),
);
const mediaFindings = [];
const isAnimationJson = (f) => /\.json$/i.test(f) && /[\\/]assets[\\/]/.test(f);
function scanMedia() {
  const found = [];
  for (const dir of ['assets', 'modules', 'plugins']) {
    found.push(...walk(path.join(ROOT, dir), /./).filter((f) => MEDIA.test(f) || isAnimationJson(f)));
  }
  for (const file of found) {
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    const bytes = fs.readFileSync(file);
    const hash = crypto.createHash('sha256').update(bytes).digest('hex');
    const ascii = bytes.toString('latin1').toLowerCase();
    const utf16 = bytes.toString('utf16le').toLowerCase();
    const term = banned.find((t) => ascii.includes(t) || utf16.includes(t));
    if (term) mediaFindings.push(`${rel}: fayl ichida «${term}» bor (metadata yoki animatsiya matni)`);
    const known = mediaList.get(rel);
    if (!known) mediaFindings.push(`${rel}: ro'yxatda yo'q media fayl — ko'rib chiqing va gapla-media-royxat.txt ga qo'shing (sha256 ${hash})`);
    else if (known !== hash) mediaFindings.push(`${rel}: ro'yxatdagidan farq qiladi — qayta ko'rib chiqing va sha256 ni yangilang (${hash})`);
  }
  for (const rel of mediaList.keys()) {
    if (!fs.existsSync(path.join(ROOT, rel))) mediaFindings.push(`${rel}: ro'yxatda bor, lekin fayl yo'q — qatorni o'chiring`);
  }
  return found.length;
}

// ---- Eski ranglar (G54) ----
// Eski brendning ko'k-binafsha ranglari kod, izoh va sozlamaning istalgan joyida taqiq: ro'yxat gapla-eski-ranglar.txt,
// katta-kichik harf va bo'sh joy farqsiz. Istisno — gapla-iz-istisno.txt ('fayl:bo'lak # sabab').
// Izoh qatori '# ' (panjara va bo'sh joy) bilan boshlanadi: '#007aff' kabi rang qiymati izoh emas.
const colorListFile = path.join(ROOT, 'gapla-eski-ranglar.txt');
const oldColors = (fs.existsSync(colorListFile) ? fs.readFileSync(colorListFile, 'utf8').split(/\r?\n/) : [])
  .map((l) => l.trim())
  .filter((l) => l && !/^#(\s|$)/.test(l))
  .map((t) => t.toLowerCase().replace(/\s+/g, ''));
if (oldColors.length === 0) {
  console.error("Xato: gapla-eski-ranglar.txt bo'sh yoki topilmadi.");
  process.exit(2);
}
function scanColors(file) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((text, i) => {
    const flat = text.toLowerCase().replace(/\s+/g, '');
    const term = oldColors.find((c) => flat.includes(c));
    if (term) report(rel, i + 1, text, term);
  });
}

// ---- Fayllarni yig'ish ----
const { files, plists } = collectFiles();

for (const [f, kind] of files) scanScript(f, kind === 'swift');
for (const f of plists) scanPlist(f);
const colorFiles = [...files.map(([f]) => f), ...plists];
for (const name of ['tailwind.config.js', 'global.css']) {
  const f = path.join(ROOT, name);
  if (fs.existsSync(f)) colorFiles.push(f);
}
for (const f of colorFiles) scanColors(f);
const mediaCount = scanMedia();

findings.sort((a, b) => (a.rel === b.rel ? a.line - b.line : a.rel.localeCompare(b.rel)));
if (findings.length === 0 && mediaFindings.length === 0) {
  console.log(`Gapla iz tekshiruvi: toza (${files.length + plists.length} fayl, ${mediaCount} ta rasm/video tekshirildi)`);
  process.exit(0);
}
for (const f of findings) console.log(`${f.rel}:${f.line}: «${f.shown}»`);
for (const m of mediaFindings) console.log(m);
if (findings.length) {
  const perFile = new Set(findings.map((f) => f.rel)).size;
  console.log(`\nGapla iz tekshiruvi: ${findings.length} ta eski iz topildi (${perFile} faylda). Foydalanuvchi ko'radigan matnni Gapla'ga almashtiring;`);
  console.log("faqat ichki qiymat bo'lsa, gapla-iz-istisno.txt ga 'fayl:bo'lak # sabab' qo'shing.");
}
if (mediaFindings.length) {
  console.log(`\nGapla iz tekshiruvi: ${mediaFindings.length} ta rasm/video muammosi. Faylni ochib ko'ring: eski brend yo'qligiga ishonch hosil qilgach,`);
  console.log("gapla-media-royxat.txt ga '<sha256>  <fayl yo'li>  # nima ko'rsatadi, kim ko'rdi, sana' qatorini yozing.");
}
process.exit(1);
