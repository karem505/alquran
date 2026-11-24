// اختبارات محرك التسميع بتسجيلات حقيقية (الحصري/المنشاوي) — بلا مايك
// node test/run-tests.mjs [اسم-سيناريو ...]
// يعتمد على تقطيع مسبق للتسجيلات (tools/segment.mjs) في tmp/tasmee/seg/*.json
// كل سيناريو: يبني مصدر صوت من مقاطع (مع حذف/تركيب صناعي)، يشغّل المحرك الحقيقي (tasmee-engine.mjs)
// ويتحقق من الأحداث. النتائج تُكتب في tmp/tasmee/test-results.json
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ENGINE = join(HERE, "..", "tasmee-engine.mjs");
const APP = join(HERE, "..", "..");
const SEG = join(APP, "tmp", "tasmee", "seg");
const Q = join(process.env.HOME, "side projects", "قرآن");
const F01 = join(Q, "01 - سورة الفاتحة من الآية (1) حتى سورة البقرة الآية (112).mp3");
const F11 = join(Q, "11 - سورة الأعراف من الآية (1) حتى الآية (126).mp3");
const MIN = join(Q, "minshawi-new");

const seg = (name) => JSON.parse(readFileSync(join(SEG, name + ".json"), "utf8"));
const LEAD = 0.7;   // ثوانٍ قبل أول حدث كلمة (تأخر التعرف)
// حدود آية بالثواني من ملف التقطيع: [بداية, بداية الآية التالية]
function span(sg, s, a, b = a) {
  const st = sg.ayahs[`${s}:${a}`];
  const nx = sg.ayahs[`${s}:${b + 1}`];
  if (!st) throw new Error(`لا تقطيع للآية ${s}:${a}`);
  const from = sg.from + st[0] / 1000 - LEAD;
  const to = nx ? sg.from + nx[0] / 1000 - LEAD : sg.from + sg.ayahs[`${s}:${b}`][1] / 1000 + 2.5;
  return [Math.max(0, from), to];
}
const piece = (file, [a, b]) => ({ file, from: +a.toFixed(2), dur: +(b - a).toFixed(2) });

function runEngine(start, timeoutMs = 240000) {
  return new Promise((resolve, reject) => {
    const p = spawn("nice", ["-n", "19", "node", ENGINE], { stdio: ["pipe", "pipe", "inherit"] });
    const events = [];
    let buf = "";
    const timer = setTimeout(() => { p.kill(); reject(new Error("timeout")); }, timeoutMs);
    p.stdout.on("data", (d) => {
      buf += d;
      let i;
      while ((i = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 1);
        if (!line.trim()) continue;
        const e = JSON.parse(line);
        events.push(e);
        if (e.ev === "ready") p.stdin.write(JSON.stringify({ cmd: "start", ...start }) + "\n");
        if (e.ev === "error" && e.code === "load") { clearTimeout(timer); p.kill(); reject(new Error(e.msg)); }
        if (e.ev === "ended") { clearTimeout(timer); p.stdin.write('{"cmd":"quit"}\n'); setTimeout(() => resolve(events), 300); }
      }
    });
    p.stdin.write(JSON.stringify({ cmd: "init" }) + "\n");
  });
}

// ---------------------------------------------------------------- أدوات التحقق
const lockedWords = (ev) => {
  const out = []; let last = "";
  for (const e of ev) if (e.ev === "pos" && e.st === "locked" && e.w) {
    const k = e.w.join(":"); if (k !== last) { out.push(e.w); last = k; }
  }
  return out;
};
const confirmed = (ev) => {
  const m = new Map();
  for (const e of ev) if (e.ev === "chk") m.set(e.id, e);
  return [...m.values()].filter((e) => e.st === "confirmed");
};
const sims = (ev) => ev.filter((e) => e.ev === "sim");
const summary = (ev) => (ev.find((e) => e.ev === "ended") || {}).summary;
const fmt = (w) => w.join(":");

// ---------------------------------------------------------------- السيناريوهات
const scenarios = {
  // ١) تسميع حر نظيف: الفاتحة + أول البقرة — المتابعة كلمة كلمة بدون أخطاء
  "free-clean": () => {
    const s = seg("f01");
    return {
      // من أول الملف (البسملة/الفاتحة) حتى نهاية البقرة ٥ — تسجيل متصل كما هو
      start: { mode: "free", src: { segments: [piece(F01, [0, span(s, 2, 6)[0]])], realtime: false } },
      check(ev) {
        const lw = lockedWords(ev);
        const want = [];
        for (const [a, n] of [[1, 4], [2, 4], [3, 2], [4, 3], [5, 4], [6, 3], [7, 9]]) for (let w = 1; w <= n; w++) want.push(`1:${a}:${w}`);
        for (const [a, n] of [[2, 7], [3, 8], [4, 12], [5, 8]]) for (let w = 1; w <= n; w++) want.push(`2:${a}:${w}`);
        const got = new Set(lw.map(fmt));
        const hit = want.filter((k) => got.has(k)).length;
        const c = confirmed(ev);
        // تتابع: كم مرة رجع الموضع للخلف داخل نفس الآية
        let back = 0;
        for (let i = 1; i < lw.length; i++) if (lw[i][0] === lw[i - 1][0] && lw[i][1] === lw[i - 1][1] && lw[i][2] < lw[i - 1][2]) back++;
        return {
          pass: hit / want.length >= 0.9 && c.length === 0 && sims(ev).length === 0,
          detail: `كلمات متابَعة ${hit}/${want.length}، أخطاء مؤكدة ${c.length}، رجوع ${back}، تنبيهات متشابهات خاطئة ${sims(ev).length}، أحداث pos ${ev.filter((e) => e.ev === "pos").length}`,
        };
      },
    };
  },
  // ٢) مقطع محدد نظيف: البقرة ٢–٥ في وضع المقطع
  "passage-clean": () => {
    const s = seg("f01");
    return {
      start: { mode: "passage", passage: [{ surah: 2, fromAyah: 2, toAyah: 5 }], label: "اختبار", src: { segments: [piece(F01, span(s, 2, 2, 5))], realtime: false } },
      check(ev) {
        const c = confirmed(ev);
        const exp = ev.filter((e) => e.ev === "pos" && e.exp).length;
        return { pass: c.length === 0 && exp > 20 && sims(ev).length === 0, detail: `أخطاء مؤكدة ${c.length} ${c.map((x) => x.cls + "@" + fmt(x.loc)).join(" ")}، أحداث بموضع متوقع ${exp}، تنبيهات متشابهات ${sims(ev).length}` };
      },
    };
  },
  // ٣) تخطّي آية: البقرة ٢–٦ مع حذف الآية ٤ من التسجيل
  "passage-skip": () => {
    const s = seg("f01");
    return {
      start: { mode: "passage", passage: [{ surah: 2, fromAyah: 2, toAyah: 6 }], src: { segments: [piece(F01, span(s, 2, 2, 3)), piece(F01, span(s, 2, 5, 6))], realtime: false } },
      check(ev) {
        const c = confirmed(ev);
        const skip = c.find((x) => x.cls === "skipped_passage" && x.loc[0] === 2 && x.loc[1] === 4);
        const om = c.filter((x) => x.loc[0] === 2 && x.loc[1] === 4);
        return { pass: (!!skip || om.length >= 3) && sims(ev).length === 0, detail: `مؤكدة: ${c.map((x) => x.cls + "@" + fmt(x.loc)).join(" ") || "لا شيء"}، تنبيهات متشابهات ${sims(ev).length}` };
      },
    };
  },
  // ٤) متشابه في وضع المقطع: المطلوب البقرة ٣٤–٣٦، والقارئ قرأ الأعراف ١٩ بدل البقرة ٣٥
  "passage-mutashabih": () => {
    const s = seg("f01"), t = seg("f11");
    return {
      start: { mode: "passage", passage: [{ surah: 2, fromAyah: 34, toAyah: 36 }],
        src: { segments: [piece(F01, span(s, 2, 34)), piece(F11, span(t, 7, 19)), piece(F01, span(s, 2, 36))], realtime: false } },
      check(ev) {
        const c = confirmed(ev);
        const in35 = c.filter((x) => x.loc[0] === 2 && x.loc[1] === 35);
        const sm = sims(ev).find((x) => (x.a.s === 2 && x.a.a === 35 && x.b.s === 7 && x.b.a === 19));
        return {
          pass: in35.length >= 1 && !!sm,
          detail: `أخطاء في ٢:٣٥: ${in35.map((x) => x.cls + "@" + x.loc[2] + "(" + x.text + ")").join(" ")} | متشابه: ${sm ? `${sm.kind} ${sm.a.s}:${sm.a.a}↔${sm.b.s}:${sm.b.a} اختلافات ${sm.a.g.filter((g) => g[3]).length}/${sm.b.g.filter((g) => g[3]).length}` : "لم يُكتشف"}`,
        };
      },
    };
  },
  // ٤ب) متشابه آخر: المطلوب البقرة ٣٣–٣٤، والقارئ ختم بآية الأعراف ١١ (ثم قلنا للملائكة... لم يكن من الساجدين)
  "passage-mutashabih-2": () => {
    const s = seg("f01"), t = seg("f11");
    return {
      start: { mode: "passage", passage: [{ surah: 2, fromAyah: 33, toAyah: 34 }],
        src: { segments: [piece(F01, span(s, 2, 33)), piece(F11, span(t, 7, 11))], realtime: false } },
      check(ev) {
        const c = confirmed(ev).filter((x) => x.loc[0] === 2 && x.loc[1] === 34);
        const sm = sims(ev).find((x) => x.a.s === 2 && x.a.a === 34 && x.b.s === 7 && x.b.a === 11);
        return { pass: !!sm, detail: `أخطاء ٢:٣٤: ${c.map((x) => x.cls + "@" + x.loc[2] + "(" + x.text + ")").join(" ") || "لا شيء"} | متشابهات: ${sims(ev).map((x) => `${x.kind} ${x.a.s}:${x.a.a}↔${x.b.s}:${x.b.a}`).join(" ") || "لا شيء"}` };
      },
    };
  },
  // ٥) متشابه في التسميع الحر: البقرة ٣٣–٣٤ ثم يكمل بالأعراف ١٩ (بدل البقرة ٣٥)
  "free-mutashabih": () => {
    const s = seg("f01"), t = seg("f11");
    return {
      start: { mode: "free", src: { segments: [piece(F01, span(s, 2, 33, 34)), piece(F11, span(t, 7, 19))], realtime: false } },
      check(ev) {
        const sm = sims(ev);
        const hit = sm.find((x) => x.b.s === 7 && x.b.a === 19 && x.a.s === 2 && x.a.a === 35);
        const lw = lockedWords(ev);
        const reached = lw.some((w) => w[0] === 7 && w[1] === 19);
        const c = confirmed(ev).filter((x) => x.loc[0] === 2 && x.loc[1] === 35);
        return { pass: !!hit, detail: `المحرك ${reached ? "انتقل إلى ٧:١٩" : "بقي في ٢:٣٥"} وعدّ أخطاء: ${c.map((x) => x.cls + "@" + x.loc[2] + "(" + x.text + ")").join(" ")} | متشابهات: ${sm.map((x) => `${x.kind} ${x.a.s}:${x.a.a}↔${x.b.s}:${x.b.a}`).join(" ") || "لا شيء"}` };
      },
    };
  },
  // ٦) كلمة خطأ مركّبة: البقرة ٥ (أولئك على هدى...) تُستبدل كلمتها بكلمة من موضع آخر — نركّب ٢:٥ من آية لقمان؟
  //    بديل عملي: المقطع ٢:٢٥–٢:٢٥ مع إدخال مقطع زائد من ٢:٢٤ في الوسط (كلمات زائدة)
  "passage-added": () => {
    const s = seg("f01");
    const [a0, a1] = span(s, 2, 21, 22);
    const extra = span(s, 2, 7);
    return {
      start: { mode: "passage", passage: [{ surah: 2, fromAyah: 21, toAyah: 22 }],
        src: { segments: [piece(F01, [a0, s.from + s.ayahs["2:22"][0] / 1000 - LEAD]), piece(F01, extra), piece(F01, [s.from + s.ayahs["2:22"][0] / 1000 - LEAD, a1])], realtime: false } },
      check(ev) {
        const c = confirmed(ev);
        return { pass: c.some((x) => x.cls === "added_word" || x.cls === "wrong_word"), detail: `مؤكدة: ${c.map((x) => x.cls + "@" + fmt(x.loc)).join(" ") || "لا شيء"}` };
      },
    };
  },
  // ٧) قارئ مختلف (المنشاوي): تسميع حر نظيف لأول ملف (الفاتحة)
  "free-minshawi": () => {
    const file = join(MIN, "01 - سورة الفاتحة من الآية 1 إلى الآي.mp3");
    return {
      start: { mode: "free", src: { segments: [{ file, from: 0, dur: 75 }], realtime: false } },
      check(ev) {
        // الفاتحة تبدأ بالبسملة المكررة في كل السور، فأول كلماتها «محتملة في عدة مواضع» (ambiguous) قبل القفل
        const fat = new Set(ev.filter((e) => e.ev === "pos" && e.w && e.w[0] === 1 && (e.st === "locked" || e.st === "ambiguous")).map((e) => fmt(e.w)));
        const c = confirmed(ev);
        return { pass: fat.size >= 26 && c.length <= 1, detail: `كلمات الفاتحة المتابَعة ${fat.size}/29، أخطاء مؤكدة ${c.length} ${c.map((x) => x.cls + "@" + fmt(x.loc)).join(" ")}` };
      },
    };
  },
};

const want = process.argv.slice(2);
const names = want.length ? want : Object.keys(scenarios);
const results = existsSync(join(APP, "tmp/tasmee/test-results.json")) ? JSON.parse(readFileSync(join(APP, "tmp/tasmee/test-results.json"), "utf8")) : {};
let fails = 0;
for (const n of names) {
  const sc = scenarios[n]();
  const t0 = Date.now();
  let res;
  try {
    const ev = await runEngine(sc.start);
    writeFileSync(join(APP, "tmp/tasmee", `events-${n}.json`), JSON.stringify(ev));
    res = sc.check(ev);
    res.summary = summary(ev);
    res.events = ev.length;
  } catch (e) { res = { pass: false, detail: "خطأ: " + e.message }; }
  res.secs = Math.round((Date.now() - t0) / 1000);
  results[n] = res;
  if (!res.pass) fails++;
  console.log(`${res.pass ? "PASS" : "FAIL"} ${n} (${res.secs}s) — ${res.detail}`);
}
writeFileSync(join(APP, "tmp/tasmee/test-results.json"), JSON.stringify(results, null, 1));
process.exit(fails ? 1 : 0);
