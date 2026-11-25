// محرك التسميع لمصحفي — عملية جانبية يشغّلها التطبيق (Quickshell Process)
//
// الإدخال (stdin، سطر JSON لكل أمر):
//   {"cmd":"init","history":"/path/history.json"}
//   {"cmd":"start","mode":"free"|"passage","passage":[{"surah":2,"fromAyah":1,"toAyah":5}, ...],
//    "src":"mic" | {"file":"/x.mp3","from":0,"dur":60,"realtime":true,"cut":[[a,b],...],"segments":[{"file","from","dur"}]},
//    "label":"الصفحة ٤٢"}
//   {"cmd":"stop"}            إنهاء الجلسة الحالية (يحسم الأخطاء المفتوحة ويرسل الملخص)
//   {"cmd":"similar","s":2,"a":35}   متشابهات آية معيّنة (للوحة الجانبية)
//   {"cmd":"listenStart","s":2,"a":35,"repeat":false}  تشغيل تسجيل الحصري المحلي
//   {"cmd":"listenStop"}
//   {"cmd":"quit"}
// الإخراج (stdout، سطر JSON لكل حدث): load / ready / started / pos / chk / sim / near / level / ended / error
// كل النصوص الموجهة للمستخدم عربية فصحى. الصوت لا يغادر الجهاز.

import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { createTilawa } from "@tilawa/core/node";
import { ayahsRecited } from "@tilawa/core";
import { HusaryPlayback } from "./husary-playback.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
// مجلد التطبيق (data/): بجانب المحرك في المستودع، أو يمرّره التطبيق لو المحرك منسوخ لمجلد المستخدم
const APP = process.env.MUSHAF_APP_DIR || dirname(HERE);
const require = createRequire(import.meta.url);

// ---------------------------------------------------------------- إخراج
function emit(o) { process.stdout.write(JSON.stringify(o) + "\n"); }
function fail(code, msg, extra) { emit({ ev: "error", code, msg, ...(extra || {}) }); }

// ---------------------------------------------------------------- البيانات
const REF = require("@tilawa/core/assets/ref-v2.json");
const WORDS = new Map();              // "s:a" → [نص الكلمة...] (نص Tanzil حرفيًا)
const AYAH_COUNT = new Map();         // s → عدد الآيات
for (const a of REF.ayahs) {
  WORDS.set(`${a.s}:${a.a}`, a.w);
  AYAH_COUNT.set(a.s, Math.max(AYAH_COUNT.get(a.s) || 0, a.a));
}
const LAYOUT = JSON.parse(readFileSync(join(APP, "data/tasmee/layout.json"), "utf8"));
const SIMILAR = JSON.parse(readFileSync(join(APP, "data/tasmee/similar.json"), "utf8"));
const SURA_NAMES = JSON.parse(readFileSync(join(APP, "data/quran.json"), "utf8")).surahs.map((s) => s.name);

// رموز QPC لكل آية: [[glyph, page, t0, t1], ...] (t0 = 0 ⇒ علامة نهاية الآية) + صفحة كل كلمة Tilawa
const AYAH_GLYPHS = new Map();
const WORD_PAGE = new Map();          // "s:a:w" → page
LAYOUT.pages.forEach((pg, i) => {
  for (const ln of pg.l) {
    if (!ln || ln.t !== "w") continue;
    for (const [g, s, a, t0, t1] of ln.w) {
      const k = `${s}:${a}`;
      if (!AYAH_GLYPHS.has(k)) AYAH_GLYPHS.set(k, []);
      AYAH_GLYPHS.get(k).push([g, i + 1, t0, t1]);
      for (let t = t0; t <= t1 && t0 > 0; t++) WORD_PAGE.set(`${k}:${t}`, i + 1);
    }
  }
});
const pageOf = (s, a, w) => WORD_PAGE.get(`${s}:${a}:${w || 1}`) || WORD_PAGE.get(`${s}:${a}:1`) || 0;
const wordText = (s, a, w) => (WORDS.get(`${s}:${a}`) || [])[w - 1] || "";

// تطبيع للمقارنة (نفس منطق أدوات البناء)
const norm = (w) => w
  .replace(/[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u0640\u200E\u200F\uFEFF]/g, "")
  .replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/ؤ/g, "و").replace(/ئ/g, "ي").replace(/ء/g, "");

// محاذاة كلمات آيتين (LCS) → علامة اختلاف لكل كلمة في كل منهما
function diffWords(A, B) {
  const a = A.map(norm), b = B.map(norm);
  const n = a.length, m = b.length;
  const L = Array.from({ length: n + 1 }, () => new Int16Array(m + 1));
  for (let i = n - 1; i >= 0; i--)
    for (let j = m - 1; j >= 0; j--)
      L[i][j] = a[i] === b[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
  const da = new Array(n).fill(1), db = new Array(m).fill(1);
  let i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) { da[i] = 0; db[j] = 0; i++; j++; }
    else if (L[i + 1][j] >= L[i][j + 1]) i++;
    else j++;
  }
  return [da, db, L[0][0]];
}

// وصف آية للعرض: رموزها (للرسم بخط الصفحة) + نصها + علامات الاختلاف
function ayahView(s, a, diffFlags) {
  const glyphs = AYAH_GLYPHS.get(`${s}:${a}`) || [];
  const words = WORDS.get(`${s}:${a}`) || [];
  return {
    s, a, sura: SURA_NAMES[s - 1] || "", page: glyphs.length ? glyphs[0][1] : 0,
    g: glyphs.map(([g, p, t0, t1]) => {
      let d = 0;
      if (t0 > 0 && diffFlags) for (let t = t0; t <= t1; t++) d = Math.max(d, diffFlags[t - 1] || 0);
      return [g, p, t0, d];
    }),
    text: words.join(" "),
  };
}

function pairView(s1, a1, s2, a2) {
  const [d1, d2, common] = diffWords(WORDS.get(`${s1}:${a1}`) || [], WORDS.get(`${s2}:${a2}`) || []);
  return { a: ayahView(s1, a1, d1), b: ayahView(s2, a2, d2), common };
}

function similarOf(s, a) { return (SIMILAR[`${s}:${a}`] || []).map(([k, score, run]) => ({ k, score, run })); }

// ---------------------------------------------------------------- المحرك
let tilawa = null;
let historyPath = null;
let run = null;             // الجلسة الجارية
const husary = new HusaryPlayback({ emit, tilawa: () => tilawa });

async function init(cmd) {
  historyPath = cmd.history || null;
  if (tilawa) { emit({ ev: "ready", cached: true, model: tilawa.model }); return; }
  let lastPct = -1, lastStage = "";
  try {
    tilawa = await createTilawa({
      onProgress: (p) => {
        const pct = Math.floor(p.fraction * 100);
        if (pct === lastPct && p.stage === lastStage) return;
        lastPct = pct; lastStage = p.stage;
        emit({ ev: "load", stage: p.stage, fraction: p.fraction, loaded: p.loaded, total: p.total, fromCache: p.fromCache });
      },
    });
  } catch (e) {
    const offline = /fetch|ENOTFOUND|EAI_AGAIN|network/i.test(String(e && (e.cause || e.message || e)));
    fail("load", offline ? "تعذّر تنزيل نموذج التسميع — تأكد من اتصال الإنترنت (مرة واحدة فقط) ثم أعد المحاولة"
                         : "تعذّر تحميل نموذج التسميع", { detail: String(e && e.message || e) });
    return;
  }
  emit({ ev: "ready", model: tilawa.model, capabilities: tilawa.capabilities.supported });
}

// مصفوفات تصل من QML أحيانًا ككائن مفاتيحه أرقام ({"0":...}) — نوحّدها
// وأحيانًا مصفوفة من عنصر واحد تصل كالعنصر نفسه
const toArr = (x) => {
  if (Array.isArray(x)) return x;
  if (!x || typeof x !== "object") return [];
  const ks = Object.keys(x);
  if (ks.length && ks.every((k) => /^\d+$/.test(k))) return ks.sort((a, b) => a - b).map((k) => x[k]);
  return [x];
};

// ---------------------------------------------------------------- مصادر الصوت
function micSource(onSamples, onLevel, onEnd) {
  // PipeWire مباشرة: s16 أحادي 16 كيلوهرتز
  const tryCmds = [
    ["pw-record", ["--rate", "16000", "--channels", "1", "--format", "s16", "-"]],
    ["parecord", ["--rate=16000", "--channels=1", "--format=s16le", "--raw"]],
    ["arecord", ["-q", "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw"]],
  ];
  let proc = null, stopped = false, gotData = false;
  const start = (i) => {
    if (i >= tryCmds.length) { onEnd("nomic"); return; }
    const [bin, args] = tryCmds[i];
    proc = spawn(bin, args, { stdio: ["ignore", "pipe", "ignore"] });
    proc.on("error", () => { if (!stopped) start(i + 1); });
    let pending = Buffer.alloc(0);
    proc.stdout.on("data", (chunk) => {
      gotData = true;
      pending = Buffer.concat([pending, chunk]);
      const n = Math.floor(pending.length / 2) * 2;
      const f = new Float32Array(n / 2);
      let peak = 0, sq = 0;
      for (let k = 0; k < n / 2; k++) { const v = pending.readInt16LE(k * 2) / 32768; f[k] = v; sq += v * v; }
      pending = pending.subarray(n);
      if (f.length) { onLevel(10 * Math.log10(sq / f.length + 1e-12)); onSamples(f); }
    });
    proc.on("exit", () => { if (!stopped) onEnd(gotData ? "ended" : "nomic"); });
  };
  start(0);
  const watchdog = setTimeout(() => { if (!gotData && !stopped) onEnd("nomic"); }, 4000);
  return { stop() { stopped = true; clearTimeout(watchdog); try { proc && proc.kill("SIGTERM"); } catch {} } };
}

// ملف صوتي (للاختبار والعرض): مقاطع متتالية، اختياريًا بسرعة الزمن الحقيقي
function fileSource(src, onSamples, onLevel, onEnd) {
  const segs = src.segments ? toArr(src.segments) : (src.cut
    ? toArr(src.cut).map(([a, b]) => ({ file: src.file, from: a, dur: b - a }))
    : [{ file: src.file, from: src.from || 0, dur: src.dur }]);
  let stopped = false, proc = null;
  const rt = src.realtime !== false;
  const t0 = Date.now();
  let pushedMs = 0;
  (async () => {
    for (const sg of segs) {
      if (stopped) break;
      const args = ["-v", "error", "-ss", String(sg.from || 0)];
      if (sg.dur) args.push("-t", String(sg.dur));
      args.push("-i", sg.file, "-ac", "1", "-ar", "16000", "-f", "f32le", "-");
      proc = spawn("ffmpeg", args, { stdio: ["ignore", "pipe", "pipe"] });
      let errText = "";
      proc.stderr.on("data", (d) => { errText += d; });
      proc.on("exit", (code) => { if (code && !stopped) process.stderr.write(`ffmpeg ${code}: ${errText.slice(0, 300)} args=${JSON.stringify(args)}\n`); });
      let pending = Buffer.alloc(0);
      for await (const chunk of proc.stdout) {
        if (stopped) break;
        pending = Buffer.concat([pending, chunk]);
        const step = 1600 * 4;           // ١٠٠ مللي ثانية
        while (pending.length >= step) {
          const f = new Float32Array(pending.buffer.slice(pending.byteOffset, pending.byteOffset + step));
          pending = pending.subarray(step);
          let sq = 0; for (const v of f) sq += v * v;
          onLevel(10 * Math.log10(sq / f.length + 1e-12));
          onSamples(f);
          pushedMs += 100;
          if (rt) { const wait = t0 + pushedMs - Date.now(); if (wait > 0) await new Promise((r) => setTimeout(r, wait)); }
        }
      }
    }
    if (!stopped) onEnd("eof");
  })().catch((e) => { if (!stopped) onEnd("error:" + e.message); });
  return { stop() { stopped = true; try { proc && proc.kill("SIGTERM"); } catch {} } };
}

// ---------------------------------------------------------------- الجلسة
const POLICY = { confirm: { after: "next-word" } };

function cmpRef(x, y) { return x.surah - y.surah || x.ayah - y.ayah || x.word - y.word; }
function inPassage(segs, w) {
  return segs.some((p) => w.surah === p.surah && w.ayah >= p.fromAyah && w.ayah <= p.toAyah);
}

function startRun(cmd) {
  if (!tilawa) { fail("notready", "نموذج التسميع لم يُحمَّل بعد"); return; }
  if (run) finishRun("restart");
  const mode = cmd.mode === "passage" ? "passage" : "free";
  const segs = mode === "passage" ? toArr(cmd.passage).filter((p) => p && p.surah) : [];
  if (mode === "passage" && segs.length === 0) { fail("passage", "المقطع المطلوب غير صالح"); return; }

  const r = {
    id: Date.now().toString(36), mode, segs, segIdx: 0, label: cmd.label || "",
    startedAt: new Date().toISOString(), wall0: Date.now(),
    events: [], mistakes: new Map(), sims: [], audioMs: 0,
    session: null, shadow: null, src: null, lastLocked: null, lastAyahKey: "", ended: false,
    lastPosKey: "", nearSent: new Set(), simSent: new Set(), shadowLock: null,
    switching: false, pendingAudio: [],
  };
  run = r;

  const openSession = () => {
    const sg = mode === "passage" ? segs[r.segIdx] : null;
    const s = sg ? tilawa.startMemorization({ surah: sg.surah, fromAyah: sg.fromAyah, toAyah: sg.toAyah }, POLICY)
                 : tilawa.startFreeRecitation(POLICY);
    s.subscribe((e) => onEvent(r, e, false));
    r.session = s;
  };
  openSession();
  if (mode === "passage") {
    // جلسة ظل حرّة على نفس الصوت: تكشف لو القارئ دخل في موضع متشابه خارج المقطع
    r.shadow = tilawa.startFreeRecitation(POLICY);
    r.shadow.subscribe((e) => onEvent(r, e, true));
  }
  r.openNext = () => {
    // الانتقال للمقطع التالي (مقطع يمتد عبر أكثر من سورة)
    if (r.segIdx + 1 >= segs.length || r.switching) return;
    r.switching = true;
    const old = r.session;
    r.segIdx++;
    openSession();
    old.end().then(() => { r.switching = false; }).catch(() => { r.switching = false; });
  };

  const onSamples = (f) => {
    // Don’t let audio leaking from the speakers into the mic count as the learner.
    if (r.ended || husary.blocksMic) return;
    r.audioMs += (f.length / 16000) * 1000;
    r.session.pushAudio(f, 16000).catch(() => {});
    if (r.shadow) r.shadow.pushAudio(f, 16000).catch(() => {});
  };
  let lastLevel = 0;
  const onLevel = (db) => { if (husary.blocksMic) return; const now = Date.now(); if (now - lastLevel > 120) { lastLevel = now; emit({ ev: "level", db: Math.round(db) }); } };
  const onEnd = (why) => {
    if (why === "nomic") { fail("mic", "لم يُعثر على ميكروفون يعمل — تأكد من توصيله والسماح له ثم أعد المحاولة"); finishRun("nomic"); return; }
    if (why.startsWith("error")) { fail("audio", "تعذّر قراءة الصوت", { detail: why }); }
    finishRun(why);
  };
  r.src = cmd.src && typeof cmd.src === "object" ? fileSource(cmd.src, onSamples, onLevel, onEnd) : micSource(onSamples, onLevel, onEnd);
  emit({ ev: "started", id: r.id, mode, passage: segs, label: r.label, src: typeof cmd.src === "object" ? "file" : "mic" });
}

function onEvent(r, e, shadow) {
  if (e.type === "capabilities") return;
  if (shadow) { onShadow(r, e); return; }
  r.events.push(e);
  if (e.type === "position") {
    const o = e.observed[0];
    const w = o ? o.word : null;
    const key = `${e.state}|${w ? `${w.surah}:${w.ayah}:${w.word}` : "-"}|${e.expected ? `${e.expected.surah}:${e.expected.ayah}:${e.expected.word}` : ""}|${e.relocated ? 1 : 0}`;
    if (key !== r.lastPosKey) {
      r.lastPosKey = key;
      emit({
        ev: "pos", st: e.state, t: e.timeMs,
        w: w ? [w.surah, w.ayah, w.word] : null,
        exp: e.expected ? [e.expected.surah, e.expected.ayah, e.expected.word] : null,
        conf: o ? +o.confidence.toFixed(2) : 0,
        page: w ? pageOf(w.surah, w.ayah, w.word) : (e.expected ? pageOf(e.expected.surah, e.expected.ayah, e.expected.word) : 0),
        cand: e.observed.slice(0, 3).map((c) => [c.word.surah, c.word.ayah, c.word.word, +c.confidence.toFixed(2)]),
        hold: !!(e.hold || e.spanHold),
      });
    }
    if (e.expected) r.lastExpected = [e.expected.surah, e.expected.ayah, e.expected.word];
    if (e.relocated) onRelocated(r, e);
    if (e.state === "locked" && w) onLocked(r, e, w);
    // نهاية مقطع (في المقاطع متعددة السور): لما يصل المتوقع لآخر كلمة ننتقل للمقطع التالي
    if (r.mode === "passage" && e.expected && r.segIdx + 1 < r.segs.length) {
      const sg = r.segs[r.segIdx];
      const words = (WORDS.get(`${sg.surah}:${sg.toAyah}`) || []).length;
      if (e.expected.surah === sg.surah && e.expected.ayah === sg.toAyah && e.expected.word >= words) setTimeout(() => r.openNext(), 1200);
    }
  } else if (e.type === "checker") {
    if (r.cleared && r.cleared.has(e.id)) return;   // خطأ مسحه المستخدم: لا يعود بتحديثات حالته
    const L = e.location;
    const rec = {
      ev: "chk", id: e.id, st: e.state, cls: e.errorClass, t: e.timeMs,
      loc: [L.surah, L.ayah, L.word], conf: +e.confidence.toFixed(2),
      text: wordText(L.surah, L.ayah, L.word), page: pageOf(L.surah, L.ayah, L.word),
      sura: SURA_NAMES[L.surah - 1] || "",
    };
    r.mistakes.set(e.id, rec);
    emit(rec);
    checkConfusion(r, L.surah, L.ayah, e.timeMs);
  }
}

// «خلط بين متشابهين»: أخطاء آية تقع بالضبط على الكلمات التي تميّزها عن آية متشابهة معها
// (الحالة الأشهر: المحرك يبقى في الآية المطلوبة ويعدّ كلمات الآية الأخرى أخطاء)
function checkConfusion(r, s, a, t) {
  // التخطّي والزيادة ليسا خلطًا: نعتمد كلمات خطأ/ناقصة فقط
  const errs = [...r.mistakes.values()].filter((m) => m.loc[0] === s && m.loc[1] === a
    && (m.cls === "wrong_word" || m.cls === "omitted_word") && (m.st === "confirmed" || m.st === "suspected"));
  if (!errs.length) return;
  const nConfirmed = errs.filter((m) => m.st === "confirmed").length;
  let best = null;
  for (const x of similarOf(s, a)) {
    const [s2, a2] = x.k.split(":").map(Number);
    const [da] = diffWords(WORDS.get(`${s}:${a}`) || [], WORDS.get(`${s2}:${a2}`) || []);
    // خطأ «يصيب» الفرق لو وقع على كلمة مختلفة أو بجوارها مباشرة (الحذف/الاستبدال قد يُنسب للكلمة المجاورة)
    const onDiff = (w) => da[w - 1] === 1 || (w >= 2 && da[w - 2] === 1 && da[w - 1] === 1) || false;
    const hitsC = errs.filter((m) => m.st === "confirmed" && onDiff(m.loc[2])).length;
    const hits = errs.filter((m) => onDiff(m.loc[2])).length;
    const ok = (hitsC >= 1 || hits >= 2) && hits / errs.length >= 0.6;
    if (ok && (!best || hits > best.hits || (hits === best.hits && x.score > best.score))) best = { s2, a2, hits, score: x.score };
  }
  if (best) reportSimilar(r, "confusion", s, a, best.s2, best.a2, t, { hits: best.hits, errors: errs.length, confirmed: nConfirmed });
}

// القارئ دخل آية جديدة: أرسل متشابهاتها (مرة لكل آية في الجلسة) + كشف القفز لموضع متشابه
function onLocked(r, e, w) {
  const k = `${w.surah}:${w.ayah}`;
  const prev = r.lastLocked;
  if (k !== r.lastAyahKey) {
    r.lastAyahKey = k;
    if (!r.nearSent.has(k)) {
      r.nearSent.add(k);
      const list = similarOf(w.surah, w.ayah).slice(0, 3).map((x) => {
        const [s2, a2] = x.k.split(":").map(Number);
        return { score: x.score, run: x.run, ...pairView(w.surah, w.ayah, s2, a2) };
      });
      if (list.length) emit({ ev: "near", s: w.surah, a: w.ayah, sura: SURA_NAMES[w.surah - 1], list });
    }
    // قفزة غير متتابعة في التسميع الحر: هل الموضع الجديد متشابه مع ما كان المتوقع بعد الموضع السابق؟
    if (prev && r.mode === "free") {
      const contiguous = (prev.surah === w.surah && (w.ayah === prev.ayah || w.ayah === prev.ayah + 1))
        || (w.surah === prev.surah + 1 && w.ayah <= 2 && prev.ayah >= (AYAH_COUNT.get(prev.surah) || 0) - 1);
      if (!contiguous) {
        const wordsPrev = (WORDS.get(`${prev.surah}:${prev.ayah}`) || []).length;
        // المتوقع: بقية الآية السابقة أو الآية التالية لها
        const expA = prev.word >= wordsPrev - 1 ? [prev.surah, prev.ayah + 1] : [prev.surah, prev.ayah];
        if (expA[1] > (AYAH_COUNT.get(expA[0]) || 0)) { expA[0]++; expA[1] = 1; }
        reportSimilar(r, "jump", expA[0], expA[1], w.surah, w.ayah, e.timeMs);
      }
    }
  }
  r.lastLocked = w;
}

function onRelocated(r, e) {
  const { from, to } = e.relocated;
  if (from.surah === to.surah && from.ayah === to.ayah) return;   // تأكيد نفس النسخة
  reportSimilar(r, "reloc", from.surah, from.ayah, to.surah, to.ayah, e.timeMs);
}

// جلسة الظل (وضع المقطع): لو قفلت على آية خارج المقطع ومتشابهة مع المتوقع → تنبيه متشابه
function onShadow(r, e) {
  if (e.type !== "position" || e.state !== "locked" || !e.observed[0]) return;
  const w = e.observed[0].word;
  if (e.observed[0].confidence < 0.6) return;
  if (inPassage(r.segs, w)) { r.shadowLock = null; return; }
  const exp = r.lastExpected;
  const k = `${w.surah}:${w.ayah}`;
  if (r.shadowLock !== k) { r.shadowLock = k; r.shadowSince = e.timeMs; return; }
  if (e.timeMs - r.shadowSince < 1200 || !exp) return;     // ثبات ١٫٢ ثانية على الموضع الخارجي
  reportSimilar(r, "passage", exp[0], exp[1], w.surah, w.ayah, e.timeMs);
}

function reportSimilar(r, kind, s1, a1, s2, a2, t, extra) {
  if (!s1 || !s2 || (s1 === s2 && a1 === a2)) return;
  const key = `${s1}:${a1}|${s2}:${a2}`;
  if (r.simSent.has(key)) return;
  const pv = pairView(s1, a1, s2, a2);
  const len = Math.max(1, Math.min(pv.a.g.length, pv.b.g.length));
  const known = similarOf(s1, a1).some((x) => x.k === `${s2}:${a2}`);
  // نعرضها فقط لو التشابه حقيقي: من جدول المتشابهات أو كلمات مشتركة كثيرة
  if (!known && pv.common < Math.max(3, len * 0.4)) return;
  r.simSent.add(key);
  const rec = { ev: "sim", kind, t, known, ...(extra || {}), ...pv };
  r.sims.push({ kind, t, a: [s1, a1], b: [s2, a2] });
  emit(rec);
}

function finishRun(why) {
  const r = run;
  if (!r || r.ended) return;
  r.ended = true;
  try { r.src && r.src.stop(); } catch {}
  const finish = async () => {
    try { await r.session.end(); } catch {}
    try { r.shadow && (await r.shadow.end()); } catch {}
    const confirmed = [...r.mistakes.values()].filter((m) => m.st === "confirmed");
    const byClass = {};
    for (const m of confirmed) byClass[m.cls] = (byClass[m.cls] || 0) + 1;
    const byAyah = {};
    for (const m of confirmed) { const k = `${m.loc[0]}:${m.loc[1]}`; byAyah[k] = (byAyah[k] || 0) + 1; }
    const hot = Object.entries(byAyah).sort((a, b) => b[1] - a[1]).slice(0, 5)
      .map(([k, n]) => { const [s, a] = k.split(":").map(Number); return { s, a, n, sura: SURA_NAMES[s - 1], page: pageOf(s, a, 1) }; });
    const ayahs = ayahsRecited(r.events).map((x) => [x.surah, x.ayah]);
    const uniq = [...new Set(ayahs.map(([s, a]) => `${s}:${a}`))];
    const summary = {
      id: r.id, mode: r.mode, label: r.label, startedAt: r.startedAt,
      durMs: Math.round(r.audioMs), wallMs: Date.now() - r.wall0,
      ayahs: uniq.length, first: ayahs[0] || null, last: ayahs[ayahs.length - 1] || null,
      mistakes: confirmed.length, cleared: r.clearedCount || 0, byClass, hot, sims: r.sims.length, why,
      list: confirmed.map((m) => ({ cls: m.cls, loc: m.loc, text: m.text, sura: m.sura, page: m.page })),
    };
    emit({ ev: "ended", summary });
    if (historyPath && summary.durMs > 3000) {
      try {
        mkdirSync(dirname(historyPath), { recursive: true });
        let h = [];
        if (existsSync(historyPath)) { try { h = JSON.parse(readFileSync(historyPath, "utf8")); } catch { h = []; } }
        h.unshift(summary);
        writeFileSync(historyPath, JSON.stringify(h.slice(0, 200)));
      } catch (e) { fail("history", "تعذّر حفظ سجل الجلسات", { detail: e.message }); }
    }
    try { r.session.dispose(); r.shadow && r.shadow.dispose(); } catch {}
    if (run === r) run = null;
  };
  finish();
}

// ---------------------------------------------------------------- حلقة الأوامر
let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let cmd;
    try { cmd = JSON.parse(line); } catch { fail("bad", "أمر غير مفهوم"); continue; }
    handle(cmd).catch((e) => fail("internal", "خطأ داخلي في محرك التسميع", { detail: String(e && e.stack || e) }));
  }
});
process.stdin.on("end", () => shutdown());
process.on("SIGTERM", () => shutdown());

async function handle(cmd) {
  switch (cmd.cmd) {
    case "init": return init(cmd);
    case "start": return startRun(cmd);
    case "stop": return finishRun("stop");
    case "listenStart": return husary.start(cmd.s, cmd.a, { repeat: cmd.repeat === true, speed:cmd.speed });
    case "listenStop": return husary.stop();
    // «مسح الأخطاء» من اللوحة: الجلسة تستمر، والأخطاء السابقة لا تُحتسب في الملخص ولا تعود
    case "clearMistakes": {
      if (!run) return;
      if (!run.cleared) run.cleared = new Set();
      let n = 0;
      for (const [id, m] of run.mistakes) { run.cleared.add(id); if (m.st === "confirmed") n++; }
      run.mistakes.clear();
      run.clearedCount = (run.clearedCount || 0) + n;
      emit({ ev: "cleared", n });
      return;
    }
    case "similar": {
      const list = similarOf(cmd.s, cmd.a).map((x) => {
        const [s2, a2] = x.k.split(":").map(Number);
        return { score: x.score, run: x.run, ...pairView(cmd.s, cmd.a, s2, a2) };
      });
      emit({ ev: "near", s: cmd.s, a: cmd.a, sura: SURA_NAMES[cmd.s - 1], list, asked: true });
      return;
    }
    case "pair": {
      emit({ ev: "pair", ...pairView(cmd.a[0], cmd.a[1], cmd.b[0], cmd.b[1]) });
      return;
    }
    case "quit": return shutdown();
    default: fail("bad", "أمر غير معروف");
  }
}

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  if (husary.active) husary.stop();
  try { if (run) { finishRun("quit"); await new Promise((r) => setTimeout(r, 600)); } } catch {}
  try { tilawa && (await tilawa.dispose()); } catch {}
  process.exit(0);
}

emit({ ev: "hello", v: 1 });
