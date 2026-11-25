// اختبارات فهرس الحصري — تسجيلات حقيقية، Tilawa محلي، بلا شبكة
// node --test engine/test/husary-index.test.mjs   (الاختبارات الحقيقية تأخذ دقائق؛ HUSARY_FAST=1 لتخطيها)
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readdirSync, rmSync, utimesSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, isAbsolute } from "node:path";
import { createTilawa } from "@tilawa/core/node";
import { scanLibrary, readTrack, findAyah, indexTrack, defaultLibrary, defaultIndexDir, trackFile } from "../husary-index.mjs";

const SCRATCH = process.env.TMPDIR || tmpdir();
const mk = () => mkdtempSync(join(SCRATCH, "husary-test-"));
const FAST = !!process.env.HUSARY_FAST;
const AYAHS = [7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6];
const ord = (s, a) => AYAHS.slice(0, s - 1).reduce((x, y) => x + y, 0) + a;

test("defaults are strings", () => {
  assert.equal(typeof defaultLibrary, "string");
  assert.equal(typeof defaultIndexDir, "string");
  assert.ok(isAbsolute(defaultLibrary) && isAbsolute(defaultIndexDir));
});

test("scanLibrary: real library → 44 ordered tracks, full contiguous cover of 1:1..114:6", () => {
  const t = scanLibrary(defaultLibrary);
  assert.equal(t.length, 44);
  assert.deepEqual(t.map((x) => x.number), Array.from({ length: 44 }, (_, i) => i + 1));
  for (const x of t) assert.ok(isAbsolute(x.file) && existsSyncSafe(x.file), x.file);
  assert.deepEqual([t[0].from, t[0].to], [[1, 1], [2, 112]]);
  assert.deepEqual([t[21].from, t[21].to], [[18, 75], [20, 44]]);
  assert.deepEqual([t[22].from, t[22].to], [[20, 44], [21, 50]]);   // تداخل طه:44
  assert.deepEqual([t[43].from, t[43].to], [[84, 1], [114, 6]]);    // الإنشقاق → الناس
  assert.ok(t[0].size > 1e6 && t[0].mtimeMs > 0);
  // التغطية: كل آية تقع في مسار واحد على الأقل، والنهاية تلاقي البداية أو تتداخل
  let covered = 0;
  const seen = new Set();
  for (const x of t) for (let o = ord(...x.from); o <= ord(...x.to); o++) seen.add(o);
  covered = seen.size;
  assert.equal(covered, 6236);
});

test("scanLibrary: alternate orthographies and numeric-only noise", () => {
  const d = mk();
  const names = [
    "01 - سورة الفاتحة من الآية (1) حتى سورة البقرة الآية (112).mp3",
    "02 - سورة إبراهيم من الآية (1) حتى الآية (52).mp3",
    "03 - سورة الانشقاق من الآية (1) حتى سورة الناس.mp3",
    "04 - سورة الإنشقاق من الآية (١) حتى سورة الناس.mp3",
    "notes.txt", "manifest.json",
  ];
  for (const n of names) writeFileSync(join(d, n), "x");
  const t = scanLibrary(d);
  assert.deepEqual(t.map((x) => x.number), [1, 2, 3, 4]);
  assert.deepEqual([t[1].from, t[1].to], [[14, 1], [14, 52]]);
  assert.deepEqual([t[2].from, t[2].to], [[84, 1], [114, 6]]);
  assert.deepEqual(t[3].from, [84, 1]);
  rmSync(d, { recursive: true });
});

test("readTrack/findAyah: missing → null; fingerprint mismatch → null; gaps reported", async () => {
  const lib = mk(), idx = mk();
  const f = join(lib, "01 - سورة الفاتحة من الآية (1) حتى الآية (7).mp3");
  writeFileSync(f, "abc");
  const [tr] = scanLibrary(lib);
  assert.equal(readTrack(tr, idx), null);
  const { writeTrackIndex } = await import("../husary-index.mjs");
  writeTrackIndex(tr, idx, {
    words: [[1000, 1, 3, 1], [2500, 1, 3, 2], [4000, 1, 4, 1]],
    starts: { "1:3": 900, "1:4": 3900 },
    gaps: [{ s: 1, a: 1, reason: "word1-not-observed" }],
    durationMs: 10000, complete: true,
  });
  const ix = readTrack(tr, idx);
  assert.ok(ix && ix.complete && ix.durationMs === 10000);
  assert.equal(findAyah(ix, 1, 3), 900);
  assert.equal(findAyah(ix, 1, 4), 3900);
  assert.equal(findAyah(ix, 1, 1), null);
  assert.equal(findAyah(ix, 1, 7), null);
  assert.equal(findAyah(null, 1, 3), null);
  assert.equal(ix.gaps.length, 1);
  // تغيّر الملف → فهرس قديم مرفوض
  writeFileSync(f, "abcdef");
  assert.equal(readTrack(scanLibrary(lib)[0], idx), null);
  const old = new Date(Date.now() - 86400e3);
  writeFileSync(f, "abc"); utimesSync(f, old, old);
  assert.equal(readTrack(scanLibrary(lib)[0], idx), null);
  // لا ملفات مؤقتة متروكة
  assert.ok(!readdirSyncAll(idx).some((n) => n.endsWith(".tmp")));
  rmSync(lib, { recursive: true }); rmSync(idx, { recursive: true });
});

test("readTrack overlays a certified clip without losing the rest of the track", async () => {
  const lib = mk(), idx = mk();
  try {
    writeFileSync(join(lib, "01 - سورة الفاتحة من الآية (1) حتى الآية (7).mp3"), "abc");
    const [t] = scanLibrary(lib);
    const {writeTrackIndex} = await import("../husary-index.mjs");
    writeTrackIndex(t, idx, {words:[[1000,1,2,2],[2000,1,3,1]], starts:{"1:3":2000},
      gaps:[{s:1,a:2}], complete:true, durationMs:9000});
    writeFileSync(trackFile(t,idx,".certified"),JSON.stringify({schema:1, fingerprint:{size:t.size,mtimeMs:t.mtimeMs},
      clips:{"1:2":{from:600,to:1800,start:720,words:[[720,1,2,1],[1150,1,2,2]]}}}));
    const d=readTrack(t,idx);
    assert.equal(findAyah(d,1,2),720);
    assert.deepEqual(d.words,[[720,1,2,1],[1150,1,2,2],[2000,1,3,1]]);
    assert.equal(d.gaps.length,0);
  } finally { rmSync(lib,{recursive:true}); rmSync(idx,{recursive:true}); }
});

const real = FAST ? { skip: "HUSARY_FAST" } : { timeout: 600000 };
// حدود بداية الآيات المقاسة بكشف الصمت (ffmpeg silencedetect) على المسار 1، بالثواني
const SILENCE_ONSET = { "1:3": 11.07, "1:4": 13.67, "1:5": 16.33, "1:6": 20.86, "1:7": 24.22, "2:2": 46.48 };

test("indexTrack: real track 1 first 100s → verified onsets near measured speech onsets; resumes after abort", real, async () => {
  const [tr] = scanLibrary(defaultLibrary);
  const tilawa = await createTilawa();
  try {
    const A = mk(), B = mk();
    // تشغيل مستمر
    const t0 = Date.now();
    const full = await indexTrack(tr, A, { tilawa, limitMs: 100000, checkpointMs: 20000 });
    console.log(`straight run ${((Date.now() - t0) / 1000).toFixed(1)}s`);
    assert.ok(full.complete === false && full.analyzedMs >= 99000);
    for (const [k, sec] of Object.entries(SILENCE_ONSET)) {
      const [s, a] = k.split(":").map(Number);
      const ms = findAyah(full, s, a);
      assert.ok(ms !== null, `no start for ${k}; gaps=${JSON.stringify(full.gaps)}`);
      // التقدير متحفظ: قبل الكلام بقليل ولا يتأخر عنه
      assert.ok(ms / 1000 <= sec + 0.05 && ms / 1000 >= sec - 0.9, `${k}: ${ms / 1000} vs ${sec}`);
    }
    assert.equal(findAyah(full, 1, 1), null);              // البسملة/أول الفاتحة: لا يُختلق
    assert.ok(full.gaps.some((g) => g.s === 1 && g.a === 2));
    assert.ok(readTrack(tr, A)?.words.length > 20);
    // إيقاف ثم استئناف
    const ac = new AbortController();
    let aborted = false;
    await assert.rejects(indexTrack(tr, B, { tilawa, limitMs: 100000, checkpointMs: 20000, signal: ac.signal, onCheckpoint: () => { if (!aborted) { aborted = true; ac.abort(); } } }), (e) => e.name === "AbortError");
    assert.ok(readdirSyncAll(B).some((n) => n.includes("partial")), "no partial checkpoint");
    assert.equal(readTrack(tr, B)?.complete ?? null, null);   // غير مكتمل → لا فهرس نهائي
    const t1 = Date.now();
    const res = await indexTrack(tr, B, { tilawa, limitMs: 100000, checkpointMs: 20000 });
    console.log(`resumed run ${((Date.now() - t1) / 1000).toFixed(1)}s`);
    assert.ok(res.resumed);
    for (const k of Object.keys(SILENCE_ONSET)) {
      const [s, a] = k.split(":").map(Number);
      assert.equal(findAyah(res, s, a), findAyah(full, s, a), k);
    }
    rmSync(A, { recursive: true }); rmSync(B, { recursive: true });
  } finally { await tilawa.dispose(); }
});

function existsSyncSafe(p) { return existsSync(p); }
function readdirSyncAll(d) { const out = []; for (const e of readdirSync(d, { withFileTypes: true })) { if (e.isDirectory()) for (const n of readdirSync(join(d, e.name))) out.push(n); else out.push(e.name); } return out; }
