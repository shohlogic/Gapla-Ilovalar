// Gapla: ilova matnlarini kod ichidan ajratib olish - iz (G44) va til (G51) tekshiruvlari uchun umumiy qism.
// Oddiy Node >= 18, tashqi paket yo'q. Bu fayl o'zi ishga tushirilmaydi: gapla-iz-tekshir.mjs va gapla-til-tekshir.mjs ishlatadi.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SKIP_DIRS = new Set(['node_modules', 'Pods', 'build', 'dist', '.git', '__tests__', '__mocks__']);

export function readList(file) {
  if (!fs.existsSync(file)) return [];
  return fs
    .readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
}

// Shablon matnidagi ${...} ifodalari kod hisoblanadi, matn emas.
export function stripExpr(s) {
  let out = '';
  let depth = 0;
  for (let k = 0; k < s.length; k++) {
    if (depth === 0 && s[k] === '$' && s[k + 1] === '{') { depth = 1; k++; continue; }
    if (depth > 0) {
      if (s[k] === '{') depth++;
      else if (s[k] === '}') depth--;
      continue;
    }
    out += s[k];
  }
  return out;
}

export function walk(dir, accept, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name)) continue;
      walk(full, accept, out);
    } else if (accept.test(full.replace(/\\/g, '/'))) out.push(full);
  }
  return out;
}


// ---- Tokenizer: JS/TS/JSX va Swift uchun matn bo'laklarini (literal) ajratadi ----
export function lex(src, swift) {
  const n = src.length;
  const lits = []; // {line, value, before}
  const code = new Array(n); // izoh va matnlar bo'shatilgan nusxa (JSX matnini topish uchun)
  for (let k = 0; k < n; k++) code[k] = src[k] === '\n' ? '\n' : ' ';
  let i = 0;
  let line = 1;
  let lastSig = '';
  let lastWord = '';

  const countNl = (a, b) => {
    let c = 0;
    for (let k = a; k < b; k++) if (src[k] === '\n') c++;
    return c;
  };
  const before = (pos) => src.slice(Math.max(0, pos - 40), pos);

  function readTemplate(j) {
    while (j < n) {
      const ch = src[j];
      if (ch === '\\') { j += 2; continue; }
      if (ch === '`') return j;
      if (ch === '$' && src[j + 1] === '{') {
        j += 2;
        let depth = 1;
        while (j < n && depth > 0) {
          const e = src[j];
          if (e === '`') { j = readTemplate(j + 1) + 1; continue; }
          if (e === '"' || e === "'") {
            let k = j + 1;
            while (k < n && src[k] !== e && src[k] !== '\n') { if (src[k] === '\\') k++; k++; }
            j = k + 1;
            continue;
          }
          if (e === '{') depth++;
          else if (e === '}') depth--;
          j++;
        }
        continue;
      }
      j++;
    }
    return n;
  }

  // Literalni yozadi; line - literal boshlangan qator, keyin qator hisobini yangilaydi.
  const push = (start, end, value, tpl = false) => {
    lits.push({ line, value, tpl, before: before(start), start, end });
    line += countNl(start, end);
  };

  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === '\n') { line++; i++; continue; }
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && d === '*') {
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        if (src[j] === '*' && src[j + 1] === '/') { depth--; j += 2; continue; }
        if (swift && src[j] === '/' && src[j + 1] === '*') { depth++; j += 2; continue; }
        j++;
      }
      line += countNl(i, j);
      i = j;
      continue;
    }
    if (swift && c === '"' && d === '"' && src[i + 2] === '"') {
      let j = src.indexOf('"""', i + 3);
      if (j < 0) j = n;
      push(i, j, src.slice(i + 3, j));
      i = j + 3;
      lastSig = '"';
      continue;
    }
    // Harfdan keyin turgan ' satr boshi emas: JSX matnidagi o'zbekcha tutuq (so'z, Gapla'ni) -
    // JS kodida satr hech qachon harfga yopishib boshlanmaydi.
    if (c === '"' || (!swift && c === "'" && !/[A-Za-z0-9]/.test(src[i - 1] || ''))) {
      let j = i + 1;
      while (j < n && src[j] !== c && src[j] !== '\n') {
        if (src[j] === '\\') {
          if (swift && src[j + 1] === '(') {
            let depth = 0;
            j++;
            while (j < n && src[j] !== '\n') {
              if (src[j] === '(') depth++;
              else if (src[j] === ')') { depth--; if (depth === 0) break; }
              j++;
            }
          } else j++;
        }
        j++;
      }
      push(i, j, src.slice(i + 1, j));
      i = src[j] === c ? j + 1 : j;
      lastSig = '"';
      lastWord = '';
      continue;
    }
    if (!swift && c === '`') {
      const j = readTemplate(i + 1);
      push(i, j, src.slice(i + 1, j), true);
      i = j + 1;
      lastSig = '"';
      lastWord = '';
      continue;
    }
    if (!swift && c === '/') {
      const regexOk =
        lastSig === '' || '(,=:[!&|?{};+-*%~^'.includes(lastSig) || /^(return|typeof|case|in|of|void|delete)$/.test(lastWord);
      if (regexOk) {
        let j = i + 1;
        let cls = false;
        let closed = false;
        while (j < n && src[j] !== '\n') {
          if (src[j] === '\\') { j += 2; continue; }
          if (src[j] === '[') cls = true;
          else if (src[j] === ']') cls = false;
          else if (src[j] === '/' && !cls) { closed = true; break; }
          j++;
        }
        if (closed) {
          j++;
          while (j < n && /[a-z]/i.test(src[j])) j++;
          i = j;
          lastSig = '"';
          lastWord = '';
          continue;
        }
      }
    }
    // oddiy kod belgisi
    code[i] = c;
    if (!/\s/.test(c)) {
      lastSig = c;
      if (/[A-Za-z_$]/.test(c)) {
        let j = i;
        while (j < n && /[\w$]/.test(src[j])) { code[j] = src[j]; j++; }
        lastWord = src.slice(i, j);
        lastSig = 'a';
        i = j;
        continue;
      }
      lastWord = '';
    }
    i++;
  }
  return { lits, code: code.join('') };
}

export function lineOfIndex(text, idx) {
  let l = 1;
  for (let k = 0; k < idx; k++) if (text[k] === '\n') l++;
  return l;
}

// JSX matni: '>' va '<' (yoki '{') orasidagi matn. code - lex() bergan izohsiz nusxa.
// Har topilma: { text, index } - index matn boshlangan joy (code ichida).
export function jsxTexts(code) {
  const out = [];
  const re = /(^|[^=\-])([>}])([^<>{}]*)([<{])/g;
  let m;
  while ((m = re.exec(code))) {
    re.lastIndex = m.index + m[0].length - 1;
    if (m[2] === '}' && m[4] === '{') continue;
    out.push({ text: m[3], index: m.index + m[1].length + 1 });
  }
  return out;
}

// Tekshiriladigan fayllar: [fayl, 'js' | 'swift'] ro'yxati va plist fayllari.
export function collectFiles() {
  const files = [];
  const isTest = (f) => /\.(test|spec)\.(ts|tsx|js)$/.test(f);
  for (const f of walk(path.join(ROOT, 'src'), /\.(ts|tsx)$/)) if (!isTest(f)) files.push([f, 'js']);
  for (const f of walk(path.join(ROOT, 'app'), /\.(ts|tsx)$/)) if (!isTest(f)) files.push([f, 'js']);
  for (const dir of ['plugins', 'modules']) {
    for (const f of walk(path.join(ROOT, dir), /\.swift$/)) if (f.replace(/\\/g, '/').includes('/ios/')) files.push([f, 'swift']);
  }
  for (const f of walk(path.join(ROOT, 'modules'), /\.(ts|tsx|js)$/)) if (!isTest(f)) files.push([f, 'js']);
  // Expo plaginlari iOS ruxsat matnlarini (Info.plist) yozadi.
  for (const f of walk(path.join(ROOT, 'plugins'), /\.(ts|js)$/)) if (!isTest(f)) files.push([f, 'js']);
  for (const name of ['app.base.json', 'app.config.js']) {
    const f = path.join(ROOT, name);
    if (fs.existsSync(f)) files.push([f, 'js']);
  }
  const plists = walk(path.join(ROOT, 'plugins'), /\.plist$/);
  return { files, plists };
}
