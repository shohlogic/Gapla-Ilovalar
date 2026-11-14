// Gapla: yangi o'zbek alifbosi (o' g' sh ch → ö ğ ş ç) — ko'prikdagi qoidaning aynan nusxasi
// (loyihalar/loyiha-gapla-server-koprik/koprik.py: yangi_alifboga va yordamchilari; sinovlari — sinov.py,
// test_yangi_alifbo_* → test/gaplaAlphabet.test.js). Egasi tanlovi (2026-11-11, «Diktovka ham»).
// Lokal rejim ko'prikka bormaydi, shuning uchun RubaiSTT matni shu yerda o'giriladi. Qoida o'zgarsa — avval
// ko'prikda, keyin shu yerda bir xil qilib. `gapla.json` → `alphabet`: «yangi» bo'lmasa (masalan «eski») — o'chiq
// (ko'prikdagi `GAPLA_ALIFBO` bilan bir xil).
// Farq faqat tilda: Python `\d`, `\b`, `\S` Unicode bo'yicha, JS da `\d`, `\b` faqat ASCII — oddiy matnda farq yo'q.
import GAPLA_DEFAULTS from "../constants/gapla.json";

const APOSTROF = "'ʻ’‘`ʼ";
const HARF = "A-Za-zÇçŞşĞğÖöÜüİı";
const SOZ = new RegExp(`[${HARF}]+(?:[${APOSTROF}][${HARF}]*)*`, "gu");
// Havola, pochta, @nom, #teg, fayl yo'li, «mp3» kabi bo'lak — butunicha tegilmaydi
const BOLAK_HIMOYA =
  /:\/\/|@|www\.|[/\\_#]|[A-Za-z]\d|\d[A-Za-z]|\.(?:com|uz|ru|org|net|io|ai|dev|app)\b/i;
// O'zbek lotinida bo'lmaydigan harf birikmasi yoki turk harfi — so'z chet tilniki, tegilmaydi
const CHET_BELGI = /w|c(?!h)|th|ph|ck|gh|ee|oo|ea|ou|oa/; // kichik harfli so'zda
const TURK_HARF = /[çşğöüıÇŞĞÖÜİ]/u; // katta-kichik farqlanadi: aks holda «İ» oddiy «i» ga ham mos keladi
const KATTA_ICHIDA = /[a-zçşğöüı][A-ZÇŞĞÖÜİ]/u; // ChatGPT, OpenRouter
// Ko'rsatmada «asl ingliz imlosida» yoziladigan, belgisi bilan ajralmaydigan so'zlar (qo'shimchasi bilan ham)
const INGLIZ = [
  "dashboard", "flash", "push", "branch", "match", "patch", "fetch", "chat", "chrome", "shell", "shift", "share",
  "shop", "short", "cash", "crash", "refresh", "fresh", "sherlock", "chatgpt", "tech", "exotech",
];
const QOSHIMCHA = new RegExp(
  `^(?:[${APOSTROF}-]?(?:larning|larni|larda|larga|lardan|lari|lar|ning|dagi|gacha|dan|ga|ka` +
    `|da|ni|mi|dek|day|imiz|ingiz|im|ing|si|i))*$`,
  "u"
);
const YANGI_HARF = [
  [new RegExp(`([Oo])[${APOSTROF}]`, "gu"), { O: "Ö", o: "ö" }],
  [new RegExp(`([Gg])[${APOSTROF}]`, "gu"), { G: "Ğ", g: "ğ" }],
  [/([Ss])[Hh]/g, { S: "Ş", s: "ş" }],
  [/([Cc])[Hh]/g, { C: "Ç", c: "ç" }],
];

function isForeignWord(soz) {
  const kichik = soz.toLowerCase();
  if (KATTA_ICHIDA.test(soz) || TURK_HARF.test(soz) || CHET_BELGI.test(kichik)) return true;
  return INGLIZ.some((e) => kichik.startsWith(e) && QOSHIMCHA.test(kichik.slice(e.length)));
}

function convertWord(soz) {
  if (isForeignWord(soz)) return soz;
  let natija = soz;
  for (const [naqsh, harf] of YANGI_HARF) {
    natija = natija.replace(naqsh, (_, birinchi) => harf[birinchi]);
  }
  return natija;
}

function convertChunk(bolak) {
  return BOLAK_HIMOYA.test(bolak) ? bolak : bolak.replace(SOZ, convertWord);
}

// O'zbekcha so'zlarda o' g' sh ch → ö ğ ş ç. Tutuq belgisi (ma'no) qoladi; ruscha, turkcha, inglizcha so'z,
// havola va nomlar (ChatGPT) o'zgarmaydi. `alphabet` «yangi» bo'lmasa — matn o'zi.
export function toNewAlphabet(matn, alphabet = GAPLA_DEFAULTS.alphabet) {
  if (alphabet !== "yangi" || !matn) return matn;
  return matn.replace(/\S+/g, convertChunk);
}
