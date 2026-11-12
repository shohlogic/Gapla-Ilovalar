#!/usr/bin/env node
// Gapla G51: ilova faqat o'zbekcha - foydalanuvchi ko'radigan inglizcha matn qolmaganini tekshiradi.
// Oddiy Node >= 18, tashqi paket yo'q. Ishga tushirish (kod papkasidan):
//   node scripts/gapla-til-tekshir.mjs                 - hamma fayl; inglizcha topilsa chiqish kodi 1
//   node scripts/gapla-til-tekshir.mjs --fayl src/screens/onboarding   - faqat shu yo'l bilan boshlangan fayllar
//   node scripts/gapla-til-tekshir.mjs --jami          - faqat har fayldagi soni
// Inglizcha so'zlar: gapla-inglizcha-sozlar.txt. Istisnolar: gapla-til-istisno.txt
//   (fayl:bo'lak # sabab; fayl:* - butun fayl; papka/:* - butun papka; har qatorda sabab SHART).
// Matn tekshiriladi: JSX matni, matnga o'xshash string literal (bo'sh joyli yoki Bosh harfli so'z), plist <string>.
// Tekshirilmaydi: izoh, kod nomi, log va dastur ichidagi xato (console.*, new Error ...), obyekt kaliti, import.
// Matnni ajratish (tokenizer, fayllar ro'yxati) gapla-matn.mjs da - iz tekshiruvi (G44) bilan umumiy.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT, readList, stripExpr, lex, lineOfIndex, jsxTexts, collectFiles } from './gapla-matn.mjs';

// Log va dastur ichidagi xato chaqiruvlari: ularning matni ekranga chiqmaydi.
const JS_LOG_CALL =
  /(^|\.)(console\.\w+|log|logs|logger\.\w+|logInfo|logWarn|logError|logDebug|debugLog|warn|trace|captureException|captureMessage|addBreadcrumb|setTag|setContext|require|import|Error|TypeError|RangeError|SyntaxError|AccountRequiredError|AbortError)$|^new \w*Error$|^Sentry\.\w+$/;
const SWIFT_LOG_CALL =
  /(^|\.)(print|debugPrint|NSLog|os_log|log|logger\.\w+|Logger|fatalError|assertionFailure|precondition|preconditionFailure|assert|NSError)$|\.(debug|info|notice|error|warning|fault|critical|trace)$/;

// Uslub va belgi qiymatlari: className, Tailwind yordamchilari (cn, clsx, cva), ikonka nomi - ekranda matn emas.
const JS_STYLE_CALL = /(^|\.)(cn|clsx|twMerge|cva|tv)$/;
const NON_TEXT_NAME =
  /^(className|\w+ClassName|style|\w+Style|mdName|\w+MdName|mdIcon|icon|\w+Icon|iconName|\w+IconName|transform|lucideIcon|sf|sfName|sfSymbol|systemImage|systemName|systemIcon|testID|nativeID|fontFamily|\w+FontFamily|accessibilityRole|keyboardType|autoComplete|autoCapitalize|textContentType|returnKeyType|variant|size|color|\w+Color|tint)$/;

// Literaldan oldingi atribut (attr="…", attr={'…'}) yoki obyekt kaliti (key: '…') nomi; bo'lmasa ''.
function nameBefore(code, start) {
  let k = start - 1;
  while (k >= 0 && /\s/.test(code[k])) k--;
  if (code[k] === '{') { k--; while (k >= 0 && /\s/.test(code[k])) k--; }
  if (code[k] !== '=' && code[k] !== ':') return '';
  if (code[k] === '=' && /[=!<>]/.test(code[k - 1] || '')) return '';
  k--;
  while (k >= 0 && /\s/.test(code[k])) k--;
  const e = k + 1;
  while (k >= 0 && /[\w$]/.test(code[k])) k--;
  return code.slice(k + 1, e);
}

function stripSwiftInterpolation(s) {
  let out = '';
  for (let k = 0; k < s.length; k++) {
    if (s[k] === '\\' && s[k + 1] === '(') {
      let depth = 0;
      for (k++; k < s.length; k++) {
        if (s[k] === '(') depth++;
        else if (s[k] === ')' && --depth === 0) break;
      }
      continue;
    }
    out += s[k];
  }
  return out;
}

// TypeScript tur birlashmasi: 'CircleCheck' | 'Circle' (bitta |, ikkita || emas) - kod, matn emas.
function isTypeUnion(src, code, start, end) {
  let b = start - 1;
  while (b >= 0 && /\s/.test(code[b])) b--;
  if (code[b] === '|' && code[b - 1] !== '|') return true;
  let a = end + 1;
  while (a < src.length && /\s/.test(src[a])) a++;
  return src[a] === '|' && src[a + 1] !== '|';
}

// Tailwind sinf ro'yxati: hamma bo'lak kichik harfli, yarmidan ko'pida '-', ':' yoki '['.
function isClassList(s) {
  const tokens = s.trim().split(/\s+/);
  if (!tokens.every((t) => /^[!a-z0-9-][a-zA-Z0-9:\-[\]/.%#()_,]*$/.test(t))) return false;
  return tokens.filter((t) => /[-:[]/.test(t)).length * 2 >= tokens.length;
}

// Matnga o'xshaydimi: harfli, identifikator yoki manzil emas; bo'sh joyi bor yoki Bosh harf bilan boshlanadi.
export function looksText(value) {
  const s = value.trim();
  if (!/[A-Za-z]{2,}/.test(s)) return false;
  if (/^(https?:|mailto:|tel:|file:|data:|sms:|itms|app-settings:|prefs:|\/|\.\/|\.\.\/|@|#[0-9a-f]{3,8}$)/i.test(s)) return false;
  if (/^[a-z0-9_.:\-/@*]+$/.test(s)) return false; // identifikator: snake_case, kebab-case, kalit
  if (/^[A-Z0-9_.\-]+$/.test(s)) return false; // KONSTANTA, ABBR
  if (!/\s/.test(s) && /^[A-Za-z]+[A-Z][a-z0-9]+\w*$/.test(s)) return false; // camelCase, PascalCase
  if (!/\s/.test(s) && /[_/.]/.test(s)) return false; // fayl nomi, shrift nomi
  return /\s/.test(s) || /^[A-Z][a-z]/.test(s);
}

// Literalni o'rab turgan eng yaqin ochiq qavs: '(' bo'lsa undan oldingi chaqiruv nomi, aks holda '{' yoki '['.
function enclosingCall(code, pos, withOpener = false) {
  let depth = 0;
  for (let k = pos - 1; k >= 0 && pos - k < 2000; k--) {
    const c = code[k];
    if (c === ')' || c === ']' || c === '}') depth++;
    else if (c === '(' || c === '[' || c === '{') {
      if (depth > 0) { depth--; continue; }
      if (c !== '(') return withOpener ? { name: c, at: k } : c;
      let j = k - 1;
      while (j >= 0 && /\s/.test(code[j])) j--;
      const e = j + 1;
      while (j >= 0 && /[\w$.?]/.test(code[j])) j--;
      const name = code.slice(j + 1, e).replace(/\?/g, '');
      const full = /\bnew\s+$/.test(code.slice(Math.max(0, j - 6), j + 1)) ? 'new ' + name : name || '(';
      return withOpener ? { name: full, at: k } : full;
    }
  }
  return withOpener ? { name: '', at: -1 } : '';
}

// Literal obyekt yoki massiv ichida bo'lsa, tashqaridagi chaqiruvlar ham olinadi:
// Sentry.addBreadcrumb({ message: '…' }) - matn log chaqiruvining obyektida.
function enclosingCalls(code, pos, levels = 4) {
  const names = [];
  let at = pos;
  for (let n = 0; n < levels; n++) {
    const r = enclosingCall(code, at, true);
    if (r.at < 0) break;
    names.push(r.name);
    if (r.name !== '{' && r.name !== '[') break;
    at = r.at;
  }
  return names;
}

// Literal obyekt kaliti, `case` qiymati yoki solishtirish qiymati bo'lsa - ekranga chiqmaydi.
function isKeyOrCompare(src, code, start, end, swift) {
  let a = end + 1;
  while (a < src.length && /[ \t]/.test(src[a])) a++;
  let b = start - 1;
  while (b >= 0 && /\s/.test(code[b])) b--;
  const prev = code[b];
  const prevWord = code.slice(Math.max(0, b - 4), b + 1);
  if (src[a] === ':' && !swift && (prev === '{' || prev === ',' || /case$/.test(prevWord))) return true;
  if (swift && src[a] === ':' && /case$/.test(prevWord)) return true;
  if (/(===|!==|==|!=)$/.test(code.slice(Math.max(0, b - 2), b + 1))) return true;
  if (/^\s*(===|!==|==|!=)/.test(src.slice(end + 1, end + 6))) return true;
  return false;
}

// jsxTexts() '>' va '<' orasidagi hamma narsani beradi; kod bo'lagi (useState<T>(), a > b && ...) JSX matni emas.
function jsxTextIsCode(code, index, text) {
  if (/[;=]|=>|&&|\|\||\b(return|const|let|export|function|import|typeof|await|async)\b/.test(text)) return true;
  // }: Pick<…>, ) : x ? (, LONG_CONSTANT ? ( - tur izohi, uchlik shart, konstanta
  if (/^\s*[:)?.,]/.test(text) || /[?:]\s*\(?\s*$/.test(text) || /\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b/.test(text)) return true;
  if (code[index - 1] === '>') {
    const lt = code.lastIndexOf('<', index - 2);
    if (lt > 0 && code[lt + 1] !== '/' && /[\w$)\]]/.test(code[lt - 1])) return true; // useState<T>(...)
  }
  return false;
}

const WORD = /[A-Za-z]+(?:'[A-Za-z]+)*/g;
export function englishWords(text, en) {
  const found = [];
  for (const w of text.replace(/\\[nrt]/g, ' ').match(WORD) || []) {
    const low = w.toLowerCase();
    if (en.has(low) && !found.includes(low)) found.push(low);
  }
  return found;
}

function loadAllow() {
  const allow = readList(path.join(ROOT, 'gapla-til-istisno.txt')).map((line) => {
    const hashAt = line.indexOf(' #');
    const body = (hashAt >= 0 ? line.slice(0, hashAt) : line).trim();
    const reason = hashAt >= 0 ? line.slice(hashAt + 2).trim() : '';
    const colon = body.indexOf(':');
    return { file: body.slice(0, colon).trim(), part: body.slice(colon + 1).trim(), reason, bad: colon < 1 || !reason };
  });
  const bad = allow.filter((a) => a.bad);
  if (bad.length) {
    console.error("Xato: gapla-til-istisno.txt da 'fayl:bo'lak # sabab' shakli buzilgan (sabab shart):");
    for (const a of bad) console.error('  ' + a.file + ':' + a.part);
    process.exit(2);
  }
  return allow;
}

const fileMatches = (rel, file) => (file.endsWith('/') ? rel.startsWith(file) : rel === file || rel.endsWith('/' + file));

// Hamma fayldan inglizcha matnni yig'adi. en - inglizcha so'zlar to'plami (kichik harf).
export function scan(en, { allow = [], only = [] } = {}) {
  const findings = [];
  const fileAllowed = (rel) => allow.some((a) => a.part === '*' && fileMatches(rel, a.file));
  const partAllowed = (rel, text) => allow.some((a) => a.part !== '*' && fileMatches(rel, a.file) && text.includes(a.part));
  const add = (rel, line, text, raw = text) => {
    const shown = text.replace(/\s+/g, ' ').trim();
    if (partAllowed(rel, shown) || partAllowed(rel, text) || partAllowed(rel, raw)) return;
    if (shown.split(' ').every((t) => /^[\w.]+=/.test(t))) return; // kalit=qiymat log qatori
    const words = englishWords(shown, en);
    if (!words.length) return;
    findings.push({ rel, line, text: shown, words });
  };
  const { files, plists } = collectFiles();
  for (const [file, kind] of files) {
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    if (only.length && !only.some((p) => rel.startsWith(p))) continue;
    if (fileAllowed(rel)) continue;
    const swift = kind === 'swift';
    const src = fs.readFileSync(file, 'utf8');
    const { lits, code } = lex(src, swift);
    for (const l of lits) {
      // JS shablonidagi ${…} va Swift satridagi \(…) - kod nomlari, matn emas.
      const value = l.tpl ? stripExpr(l.value) : swift ? stripSwiftInterpolation(l.value) : l.value;
      if (!looksText(value)) continue;
      if (!swift && /(\bfrom\s*|\bimport\s*\(?\s*|\brequire\s*\(\s*)$/.test(l.before)) continue;
      if (isKeyOrCompare(src, code, l.start, l.end, swift)) continue;
      if (l.tpl && /[\w$]\s*$/.test(l.before)) continue; // sql`…`, gql`…` - teglangan shablon
      if (!swift && isTypeUnion(src, code, l.start, l.end)) continue;
      const attrInBraces = !swift && /\b(\w+)\s*=\s*\{[^{}]*$/.exec(l.before);
      if (attrInBraces && NON_TEXT_NAME.test(attrInBraces[1])) continue; // mdName={a ? 'Check' : 'Copy'}
      const calls = enclosingCalls(code, l.start);
      if (calls.some((c) => (swift ? SWIFT_LOG_CALL : JS_LOG_CALL).test(c))) continue;
      if (!swift && (calls.some((c) => JS_STYLE_CALL.test(c)) || NON_TEXT_NAME.test(nameBefore(code, l.start)) || isClassList(value))) continue;
      add(rel, l.line, value, l.value);
    }
    if (!swift && /\.tsx$/.test(file)) {
      for (const { text, index } of jsxTexts(code)) {
        if (!/[A-Za-z]{2,}/.test(text) || jsxTextIsCode(code, index, text)) continue;
        add(rel, lineOfIndex(code, index + (text.length - text.trimStart().length)), text);
      }
    }
  }
  for (const file of plists) {
    const rel = path.relative(ROOT, file).replace(/\\/g, '/');
    if (only.length && !only.some((p) => rel.startsWith(p))) continue;
    if (fileAllowed(rel)) continue;
    const src = fs.readFileSync(file, 'utf8');
    const re = /<string>([\s\S]*?)<\/string>/g;
    let m;
    while ((m = re.exec(src))) if (looksText(m[1])) add(rel, lineOfIndex(src, m.index), m[1]);
  }
  findings.sort((a, b) => (a.rel === b.rel ? a.line - b.line : a.rel.localeCompare(b.rel)));
  return findings;
}

function main() {
  const args = process.argv.slice(2);
  const only = [];
  for (let k = 0; k < args.length; k++) if (args[k] === '--fayl' && args[k + 1]) only.push(args[++k].replace(/\\/g, '/'));
  const en = new Set(readList(path.join(ROOT, 'gapla-inglizcha-sozlar.txt')).map((w) => w.toLowerCase()));
  if (en.size === 0) {
    console.error("Xato: gapla-inglizcha-sozlar.txt bo'sh yoki topilmadi.");
    process.exit(2);
  }
  const findings = scan(en, { allow: loadAllow(), only });
  if (findings.length === 0) {
    console.log("Gapla til tekshiruvi: toza - ekranda inglizcha matn topilmadi.");
    process.exit(0);
  }
  if (args.includes('--jami')) {
    const per = new Map();
    for (const f of findings) per.set(f.rel, (per.get(f.rel) || 0) + 1);
    for (const [rel, n] of [...per].sort((a, b) => b[1] - a[1])) console.log(`${String(n).padStart(4)}  ${rel}`);
  } else {
    for (const f of findings) {
      const t = f.text.length > 140 ? f.text.slice(0, 137) + '...' : f.text;
      console.log(`${f.rel}:${f.line}: «${t}»  [${f.words.slice(0, 4).join(', ')}]`);
    }
  }
  const perFile = new Set(findings.map((f) => f.rel)).size;
  console.log(`\nGapla til tekshiruvi: ${findings.length} ta inglizcha matn (${perFile} faylda). Ekranda chiqadigan matnni o'zbekchaga o'giring;`);
  console.log("faqat ekranga chiqmaydigan matn bo'lsa, gapla-til-istisno.txt ga 'fayl:bo'lak # sabab' qo'shing.");
  process.exit(1);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) main();
