// فهرس تسجيلات الحصري: يقرأ مكتبة mp3 مرقّمة بأسماء نطاقات عربية، ويشغّل Tilawa محليًا (بلا شبكة)
// لاستخراج زمن أول كلمة من كل آية، ثم يتحقق من كل بداية بمقطع قصير قبل أن يعتمدها.
//
// scanLibrary(dir)                → [{number,file,from:[s,a],to:[s,a],size,mtimeMs,title}]
// readTrack(track, indexDir)      → null | {words,starts,gaps,durationMs,complete,...}
// findAyah(index, s, a)           → ms (بداية موثّقة) | null
// indexTrack(track, indexDir, {tilawa, signal, limitMs, checkpointMs, onCheckpoint})
//
// المبدأ: لا اختلاق. بداية الآية تُعتمد فقط إذا (1) رُصدت الكلمة 1 منها فعلًا، (2) فتح مقطع قصير يبدأ عند التقدير
// أقفل Tilawa على الكلمة 1 كأول شيء (لا كلمات سابقة ولا قصّ). الباقي يُسجَّل في gaps بسببه.
// زمن حدث Tilawa للكلمة 1 قريب من بداية الصوت الفعلية (قِيس: 0..+120ms على المسار 1 مقابل ffmpeg silencedetect)،
// والتقدير = زمن الحدث − LEAD_MS ليبقى قبل بداية الكلام.
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, writeFileSync, unlinkSync, openSync, fsyncSync, closeSync } from "node:fs";
import { homedir } from "node:os";
import { setTimeout as delay } from "node:timers/promises";
import { basename, join, resolve } from "node:path";

export const defaultLibrary = process.env.MUSHAFI_REF_AUDIO ? resolve(process.env.MUSHAFI_REF_AUDIO) : join(homedir(), "side projects", "قرآن");
export const defaultIndexDir = process.env.MUSHAFI_HUSARY_INDEX ? resolve(process.env.MUSHAFI_HUSARY_INDEX) : join(homedir(), ".local", "share", "alquran", "husary-index");

export const SCHEMA = 1;
const LEAD_MS = 300;          // التقدير = حدث الكلمة 1 − LEAD
const VERIFY_MS = 4500;       // طول مقطع التحقق
const WARM_MS = 30000;        // تسخين عند الاستئناف
const SR = 16000;

const NAMES = ["الفاتحة","البقرة","آل عمران","النساء","المائدة","الأنعام","الأعراف","الأنفال","التوبة","يونس","هود","يوسف","الرعد","ابراهيم","الحجر","النحل","الإسراء","الكهف","مريم","طه","الأنبياء","الحج","المؤمنون","النور","الفرقان","الشعراء","النمل","القصص","العنكبوت","الروم","لقمان","السجدة","الأحزاب","سبإ","فاطر","يس","الصافات","ص","الزمر","غافر","فصلت","الشورى","الزخرف","الدخان","الجاثية","الأحقاف","محمد","الفتح","الحجرات","ق","الذاريات","الطور","النجم","القمر","الرحمن","الواقعة","الحديد","المجادلة","الحشر","الممتحنة","الصف","الجمعة","المنافقون","التغابن","الطلاق","التحريم","الملك","القلم","الحاقة","المعارج","نوح","الجن","المزمل","المدثر","القيامة","الانسان","المرسلات","النبإ","النازعات","عبس","التكوير","الإنفطار","المطففين","الإنشقاق","البروج","الطارق","الأعلى","الغاشية","الفجر","البلد","الشمس","الليل","الضحى","الشرح","التين","العلق","القدر","البينة","الزلزلة","العاديات","القارعة","التكاثر","العصر","الهمزة","الفيل","قريش","الماعون","الكوثر","الكافرون","النصر","المسد","الإخلاص","الفلق","الناس"];
export const AYAH_COUNTS = [7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6];
export const TOTAL_AYAHS = 6236;

// تطبيع الاسم: تشكيل/تطويل، الألفات، ى→ي، ة→ه، همزة على واو/ياء، مسافات
function norm(s) {
  return s.normalize("NFKC").replace(/[\u064B-\u065F\u0670\u0640]/g, "")
    .replace(/[أإآٱ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/[ؤئ]/g, "ء")
    .replace(/\s+/g, " ").trim();
}
const NAME_MAP = new Map();
NAMES.forEach((n, i) => NAME_MAP.set(norm(n), i + 1));
for (const [alt, i] of [["ال عمران", 3], ["سباء", 34], ["سبا", 34], ["النبا", 78], ["ابراهيم", 14], ["الانفطار", 82], ["الانشقاق", 84], ["الانسان", 76], ["الدهر", 76], ["غافر", 40], ["المومن", 40], ["المومنون", 23], ["الاسراء", 17], ["بني اسراييل", 17], ["السجده", 32], ["فصلت", 41]]) NAME_MAP.set(norm(alt), i);
const surahNo = (name) => NAME_MAP.get(norm(name)) ?? null;
const digits = (s) => +s.replace(/[٠-٩]/g, (d) => "٠١٢٣٤٥٦٧٨٩".indexOf(d));
export const ordinal = (s, a) => { let o = a; for (let i = 0; i < s - 1; i++) o += AYAH_COUNTS[i]; return o; };

const RE = /^\s*(\d+)\s*[-–]\s*سورة\s+(.+?)\s+من\s+الآية\s*\(?\s*([\d٠-٩]+)\s*\)?\s+حتى\s+(?:سورة\s+(.+?)\s*)?(?:الآية\s*\(?\s*([\d٠-٩]+)\s*\)?)?\s*$/;

export function scanLibrary(dir = defaultLibrary) {
  const out = [];
  for (const name of readdirSync(dir)) {
    if (!/\.mp3$/i.test(name)) continue;
    const m = RE.exec(name.replace(/\.mp3$/i, ""));
    if (!m) continue;
    const s1 = surahNo(m[2]);
    const s2 = m[4] ? surahNo(m[4]) : s1;
    if (!s1 || !s2) continue;
    const a1 = digits(m[3]);
    const a2 = m[5] ? digits(m[5]) : AYAH_COUNTS[s2 - 1];   // «حتى سورة الناس» = آخر السورة
    if (a1 < 1 || a1 > AYAH_COUNTS[s1 - 1] || a2 < 1 || a2 > AYAH_COUNTS[s2 - 1]) continue;
    if (ordinal(s2, a2) < ordinal(s1, a1)) continue;
    const file = resolve(dir, name);
    const st = statSync(file);
    out.push({ number: +m[1], file, from: [s1, a1], to: [s2, a2], size: st.size, mtimeMs: Math.round(st.mtimeMs), title: basename(name, ".mp3") });
  }
  return out.sort((x, y) => x.number - y.number);
}

// ───── ملفات الفهرس (ذرّية: كتابة مؤقت ثم rename) ─────
const pad = (n) => String(n).padStart(2, "0");
export const trackFile = (track, dir, kind = "") => join(dir, `track-${pad(track.number)}${kind}.json`);
const fp = (t) => ({ size: t.size, mtimeMs: t.mtimeMs });
const fpOk = (t, f) => f && f.size === t.size && f.mtimeMs === t.mtimeMs;

function atomicWrite(path, obj) {
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, JSON.stringify(obj));
  const fd = openSync(tmp, "r"); fsyncSync(fd); closeSync(fd);
  renameSync(tmp, path);
}
function load(path) { try { return JSON.parse(readFileSync(path, "utf8")); } catch { return null; } }

export function writeTrackIndex(track, indexDir, data) {
  mkdirSync(indexDir, { recursive: true });
  atomicWrite(trackFile(track, indexDir), { schema: SCHEMA, number: track.number, from: track.from, to: track.to, fingerprint: fp(track), leadMs: LEAD_MS, ...data });
}

export function readTrack(track, indexDir = defaultIndexDir) {
  const d = load(trackFile(track, indexDir));
  if (!d || d.schema !== SCHEMA || !fpOk(track, d.fingerprint) || !Array.isArray(d.words)) return null;
  const extra = load(trackFile(track, indexDir, ".certified"));
  if (extra?.schema === SCHEMA && fpOk(track, extra.fingerprint)) {
    for (const [key, clip] of Object.entries(extra.clips || {})) {
      if (!Array.isArray(clip.words) || !Number.isFinite(clip.start)) continue;
      d.starts[key] = clip.start;
      d.words = d.words.filter(([ms]) => ms < clip.from || ms > clip.to).concat(clip.words);
      d.gaps = d.gaps.filter(({s, a}) => `${s}:${a}` !== key);
    }
    d.words.sort((a,b) => a[0] - b[0]);
    d.ayahsVerified = Object.keys(d.starts).length;
  }
  return d;
}

// For a missed lock (e.g. basmala or disjointed letters): certify an isolated clip
// from the original recording against the complete reference phoneme sequence.
export async function certifyClip(track, indexDir, {s, a, from, to, reference, tilawa}) {
  if (!reference || !(from >= 0 && to > from && to - from <= 30000) ||
      reference.s !== s || reference.a !== a || ordinal(s,a) < ordinal(...track.from) || ordinal(s,a) > ordinal(...track.to))
    throw new Error('invalid ayah or clip (milliseconds, maximum 30s)');
  const session = tilawa.startMemorization({surah:s,fromAyah:a,toAyah:a});
  try {
    await feed(track.file, session, from, to - from);
    await session.end();
    const observed = session.evidence().flatMap(e => e.phonemes).sort((x,y) => x.start-y.start);
    // Quranic long vowels can be held for different lengths. Preserve all
    // other symbols and reject the entire correction on a single mismatch.
    const long = new Set(['ا','ۦ','ۥ']);
    function keep(tokens) { return tokens.filter((p,i) => !i || !long.has(p.p) || p.p !== tokens[i-1].p); }
    const expected = keep(Array.from(reference.p, (p,i) => ({p,i})));
    const actual = keep(observed);
    if (!expected.length || expected.map(x => x.p).join('') !== actual.map(x => x.p).join(''))
      throw new Error(`phoneme mismatch (${s}:${a}): ${actual.map(x=>x.p).join('')}`);
    const words = reference.o.map((offset,i) => {
      const j = expected.findIndex(p => p.i >= offset);
      if (j < 0) throw new Error('unmatched reference word');
      return [Math.max(from, from + actual[j].start * 40 - (i === 0 ? 180 : 0)), s, a, i+1];
    });
    mkdirSync(indexDir,{recursive:true});
    const path = trackFile(track,indexDir,'.certified'), prior = load(path);
    const clips = prior?.schema === SCHEMA && fpOk(track,prior.fingerprint) ? prior.clips : {};
    const clip = {from,to,start:words[0][0],words};
    clips[`${s}:${a}`] = clip;
    atomicWrite(path,{schema:SCHEMA,fingerprint:fp(track),clips});
    return clip;
  } finally { session.dispose(); }
}

export function findAyah(index, s, a) {
  const v = index?.starts?.[`${s}:${a}`];
  return typeof v === "number" ? v : null;
}

// ───── الصوت: ffmpeg للقراءة فقط ─────
function probeDurationMs(file) {
  const r = spawnSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file], { encoding: "utf8" });
  const v = parseFloat(r.stdout);
  if (!(v > 0)) throw new Error(`ffprobe failed for ${file}: ${r.stderr}`);
  return Math.round(v * 1000);
}
const abortErr = () => Object.assign(new Error("aborted"), { name: "AbortError" });

// يغذّي جلسة بصوت [fromMs, fromMs+durMs) ويستدعي onChunk(absMs) بعد كل دفعة
async function feed(file, session, fromMs, durMs, signal, onChunk) {
  const args = ["-nostdin", "-v", "error", "-ss", (fromMs / 1000).toFixed(3)];
  if (durMs != null) args.push("-t", (durMs / 1000).toFixed(3));
  args.push("-i", file, "-vn", "-ac", "1", "-ar", String(SR), "-f", "f32le", "-");
  const ff = spawn("ffmpeg", args, { stdio: ["ignore", "pipe", "pipe"] });
  let err = ""; ff.stderr.on("data", (d) => (err += d));
  const exited = new Promise((res) => ff.on("close", res));
  ff.on("error", () => {});
  let pending = Buffer.alloc(0), samples = 0;
  try {
    for await (const chunk of ff.stdout) {
      if (signal?.aborted) throw abortErr();
      pending = Buffer.concat([pending, chunk]);
      const n = Math.floor(pending.length / 4) * 4;
      const f = new Float32Array(pending.buffer.slice(pending.byteOffset, pending.byteOffset + n));
      pending = pending.subarray(n);
      await session.pushAudio(f, SR);
      samples += f.length;
      await onChunk?.(fromMs + (samples / SR) * 1000);
    }
    if (signal?.aborted) throw abortErr();
    const code = await exited;
    if (code !== 0 && samples === 0) throw new Error(`ffmpeg exit ${code}: ${err.trim()}`);
  } finally { if (ff.exitCode === null) ff.kill("SIGKILL"); }
  return fromMs + (samples / SR) * 1000;
}

// ───── المرحلة 1: كلمات مقفولة على كامل المسار (استئنافية) ─────
async function pass1(track, indexDir, tilawa, { limitMs, checkpointMs, signal, onCheckpoint }) {
  const pf = trackFile(track, indexDir, ".pass1.partial");
  let st = load(pf);
  if (!st || st.schema !== SCHEMA || !fpOk(track, st.fingerprint) || st.limitMs !== (limitMs ?? null)) st = null;
  if (st?.done) return { ...st, resumed: true };
  const resumed = !!st && st.audioMs > 0;
  const audioMs = st ? st.audioMs : 0;
  const offset = resumed ? Math.max(0, Math.floor((audioMs - WARM_MS) / 40) * 40) : 0;
  // The decoder buffers audio; the last reported word can lag behind the last
  // submitted sample. Replace the tail from the warm-up rather than leaving a hole.
  const mergeAt = offset > 0 ? Math.max(offset, audioMs - 8000) : 0;
  const words = st ? st.words.filter(w => w[0] < mergeAt) : [];
  let last = words.length ? words[words.length - 1].slice(1).join(":") : "";
  const session = tilawa.startFreeRecitation();
  session.subscribe((e) => {
    if (e.type !== "position" || e.state !== "locked" || !e.observed[0]) return;
    const w = e.observed[0].word;
    const k = `${w.surah}:${w.ayah}:${w.word}`;
    if (k === last) return;
    const ms = Math.round(offset + e.timeMs);
    if (ms < mergeAt) return;                          // قبل الوصلة تُستخدم الكلمات المحفوظة
    last = k;
    words.push([ms, w.surah, w.ayah, w.word]);
  });
  const save = (ms, done = false) => atomicWrite(pf, { schema: SCHEMA, fingerprint: fp(track), limitMs: limitMs ?? null, audioMs: ms, words, done });
  let nextCk = (Math.floor(audioMs / checkpointMs) + 1) * checkpointMs;
  let pos = audioMs;
  try {
    pos = await feed(track.file, session, offset, limitMs != null ? Math.max(0, limitMs - offset) : null, signal, async (ms) => {
      pos = ms;
      if (ms >= nextCk) { nextCk = (Math.floor(ms / checkpointMs) + 1) * checkpointMs; save(ms); await onCheckpoint?.(ms); }
    });
    await session.end();
  } catch (e) { if (e.name === "AbortError" && pos > audioMs) save(pos); throw e; }
  finally { try { session.dispose(); } catch {} }
  save(pos, true);
  return { words, audioMs: pos, done: true, resumed };
}

// ───── المرحلة 2: تحقق من كل بداية مرشّحة بمقطع قصير ─────
function candidatesFrom(words, track, analyzedMs, limited) {
  const lo = ordinal(...track.from), hi = ordinal(...track.to);
  const first = new Map();   // "s:a" → أول حدث كلمة 1، وأول رصد لأي كلمة
  const seenAny = new Map();
  for (const [ms, s, a, w] of words) {
    const o = ordinal(s, a);
    if (o < lo || o > hi) continue;
    const k = `${s}:${a}`;
    if (!seenAny.has(k)) seenAny.set(k, { ms, w });
    if (w === 1 && !first.has(k)) first.set(k, ms);
  }
  const cands = [], gaps = [];
  let lastOrd = 0, lastMs = -1;
  const keys = [...first.entries()].map(([k, ms]) => { const [s, a] = k.split(":").map(Number); return { s, a, ms, o: ordinal(s, a) }; }).sort((x, y) => x.ms - y.ms);
  const accepted = new Set();
  for (const c of keys) {
    if (c.o > lastOrd && c.ms > lastMs) { cands.push(c); lastOrd = c.o; lastMs = c.ms; accepted.add(c.o); }
    else gaps.push({ s: c.s, a: c.a, reason: "out-of-order-lock" });
  }
  const maxSeen = limited ? Math.max(0, ...[...seenAny.keys()].map((k) => ordinal(...k.split(":").map(Number)))) : hi;
  const gapped = new Set(gaps.map((g) => ordinal(g.s, g.a)));
  for (let o = lo; o <= maxSeen; o++) {
    if (accepted.has(o) || gapped.has(o)) continue;
    let s = 1, r = o; while (r > AYAH_COUNTS[s - 1]) { r -= AYAH_COUNTS[s - 1]; s++; }
    gaps.push({ s, a: r, reason: seenAny.has(`${s}:${r}`) ? "word1-not-observed" : "not-observed" });
  }
  return { cands, gaps };
}

async function verifyOne(track, tilawa, c, startMs, durationMs, signal) {
  const dur = Math.min(VERIFY_MS, durationMs - startMs);
  if (dur < 1500) return { ok: false, reason: "too-close-to-end" };
  const session = tilawa.startFreeRecitation();
  const locked = [];
  session.subscribe((e) => { if (e.type === "position" && e.state === "locked" && e.observed[0]) locked.push(e.observed[0]); });
  try {
    await feed(track.file, session, startMs, dur, signal);
    await session.end();
  } finally { try { session.dispose(); } catch {} }
  if (!locked.length) return { ok: false, reason: "verify-no-lock" };
  const target = ordinal(c.s, c.a);
  const f = locked[0];
  const st = f.span.start;
  if (st.surah !== c.s || st.ayah !== c.a || st.word !== 1) return { ok: false, reason: `verify-first-lock-${st.surah}:${st.ayah}:${st.word}` };
  for (const o of locked) if (ordinal(o.word.surah, o.word.ayah) < target) return { ok: false, reason: "verify-earlier-ayah-audible" };
  return { ok: true };
}

export async function indexTrack(track, indexDir = defaultIndexDir, options = {}) {
  mkdirSync(indexDir, { recursive: true });
  const { signal, limitMs, target } = options;
  const lock = trackFile(track, indexDir, ".lock");
  while (true) {
    signal?.throwIfAborted();
    const previous = readTrack(track, indexDir);
    if (limitMs == null && (previous?.complete || (target && findAyah(previous, ...target) != null))) return previous;
    try { writeFileSync(lock, String(process.pid), { flag: "wx", mode: 0o600 }); break; }
    catch (error) {
      if (error.code !== "EEXIST") throw error;
      const pid = Number(load(lock));
      if (pid > 0) {
        try { process.kill(pid, 0); }
        catch (e) { if (e.code === "ESRCH") { try { unlinkSync(lock); } catch {} continue; } }
      }
      await delay(750, null, { signal });
    }
  }
  try { return await indexTrackLocked(track, indexDir, options); }
  finally { try { unlinkSync(lock); } catch {} }
}

async function indexTrackLocked(track, indexDir, { tilawa, signal, limitMs = null, checkpointMs = 60000, onCheckpoint, onProgress } = {}) {
  mkdirSync(indexDir, { recursive: true });
  const prev = readTrack(track, indexDir);
  if (prev?.complete && limitMs == null) return { ...prev, skipped: true };
  if (signal?.aborted) throw abortErr();
  const own = !tilawa;
  if (own) { const { createTilawa } = await import("@tilawa/core/node"); tilawa = await createTilawa(); }
  const t0 = Date.now();
  try {
    const durationMs = probeDurationMs(track.file);
    const lim = limitMs != null && limitMs < durationMs ? limitMs : null;
    const p1 = await pass1(track, indexDir, tilawa, { limitMs: lim, checkpointMs, signal, onCheckpoint });
    const { cands, gaps } = candidatesFrom(p1.words, track, p1.audioMs, lim != null);
    // المرحلة 2 استئنافية: نتائج التحقق تُحفظ كل دفعة
    const vf = trackFile(track, indexDir, ".verify.partial");
    let vr = load(vf);
    if (!vr || vr.schema !== SCHEMA || !fpOk(track, vr.fingerprint) || vr.leadMs !== LEAD_MS || vr.limitMs !== lim) vr = { schema: SCHEMA, fingerprint: fp(track), leadMs: LEAD_MS, limitMs: lim, results: {} };
    const starts = {};
    let n = 0;
    for (const c of cands) {
      const k = `${c.s}:${c.a}`;
      const est = Math.max(0, c.ms - LEAD_MS);
      let r = vr.results[k];
      if (!r || r.eventMs !== c.ms) {
        r = { eventMs: c.ms, startMs: est, ...(await verifyOne(track, tilawa, c, est, durationMs, signal)) };
        vr.results[k] = r;
        if (++n % 10 === 0) atomicWrite(vf, vr);
      }
      if (r.ok) starts[k] = r.startMs; else gaps.push({ s: c.s, a: c.a, reason: r.reason, eventMs: c.ms });
      onProgress?.({ k, ok: r.ok, done: Object.keys(vr.results).length, total: cands.length });
    }
    atomicWrite(vf, vr);
    gaps.sort((x, y) => ordinal(x.s, x.a) - ordinal(y.s, y.a));
    const words = p1.words.map(([ms, s, a, w]) => (w === 1 && starts[`${s}:${a}`] != null && ms === vr.results[`${s}:${a}`]?.eventMs ? [starts[`${s}:${a}`], s, a, w] : [ms, s, a, w]));
    const complete = lim == null;
    const data = { words, starts, gaps, durationMs, analyzedMs: Math.round(p1.audioMs), complete, resumed: !!p1.resumed, ayahsVerified: Object.keys(starts).length, elapsedMs: Date.now() - t0 };
    writeTrackIndex(track, indexDir, data);
    if (complete) for (const kind of [".pass1.partial", ".verify.partial"]) { try { unlinkSync(trackFile(track, indexDir, kind)); } catch {} }
    return readTrack(track, indexDir);
  } finally { if (own) await tilawa.dispose(); }
}

export function coverage(tracks, indexDir = defaultIndexDir) {
  const have = new Set(), gaps = [];
  let done = 0;
  for (const t of tracks) {
    const ix = readTrack(t, indexDir);
    if (!ix) continue;
    if (ix.complete) done++;
    for (const k of Object.keys(ix.starts)) have.add(k);
    for (const g of ix.gaps) gaps.push({ track: t.number, ...g });
  }
  return { tracksTotal: tracks.length, tracksComplete: done, ayahsWithStart: have.size, totalAyahs: TOTAL_AYAHS, gaps };
}
