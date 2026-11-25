// فهرسة تسجيلات الحصري (أوفلاين، Tilawa محلي). استئنافية: أعد التشغيل فتكمل من آخر نقطة.
//   nice -n 19 ionice -c3 node tools/index-husary.mjs                  # كل المسارات الناقصة
//   node tools/index-husary.mjs --tracks 1,5-7 [--limit-ms 120000]     # مسارات محددة / تجربة قصيرة
//   node tools/index-husary.mjs --status                               # التغطية مقابل 6236 دون تشغيل
// --library DIR (أو MUSHAFI_REF_AUDIO)   --index DIR (أو MUSHAFI_HUSARY_INDEX)
// الصوت للقراءة فقط. SIGINT/SIGTERM تحفظ نقطة استئناف ثم تخرج.
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { createRequire } from "node:module";
import { scanLibrary, readTrack, indexTrack, certifyClip, coverage, defaultLibrary, defaultIndexDir, TOTAL_AYAHS } from "../husary-index.mjs";

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const lib = opt("--library", defaultLibrary), idx = opt("--index", defaultIndexDir);
const limitMs = opt("--limit-ms", null) != null ? +opt("--limit-ms") : null;
const only = opt("--tracks", null);
const wanted = only ? new Set(only.split(",").flatMap((p) => { const [a, b = a] = p.split("-").map(Number); return Array.from({ length: b - a + 1 }, (_, i) => a + i); })) : null;
const ts = () => new Date().toISOString().slice(11, 19);

const tracks = scanLibrary(lib).filter((t) => !wanted || wanted.has(t.number));
mkdirSync(idx, { recursive: true });

function report() {
  const c = coverage(scanLibrary(lib), idx);
  console.log(`[${ts()}] coverage: ${c.ayahsWithStart}/${TOTAL_AYAHS} ayahs with verified start, ${c.tracksComplete}/${c.tracksTotal} tracks complete, ${c.gaps.length} gap entries`);
  return c;
}
if (argv.includes("--status")) { report(); process.exit(0); }
if (argv.includes("--certify")) {
  const clips = argv.filter((_v,i) => argv[i-1] === "--certify");
  const ref = createRequire(import.meta.url)("@tilawa/core/assets/ref-v2.json");
  const { createTilawa } = await import("@tilawa/core/node");
  const t = await createTilawa({recordEvidence:true});
  try {
    for (const clip of clips) {
      const [number,s,a,from,to] = clip.split(":").map(Number);
      const track = tracks.find(x=>x.number===number);
      if (!track) throw new Error(`unknown track: ${number}`);
      const verified = await certifyClip(track,idx,{s,a,from,to,tilawa:t,reference:ref.ayahs.find(x=>x.s===s && x.a===a)});
      console.log(`#${number} ${s}:${a} certified from ${verified.start}ms, ${verified.words.length} words`);
    }
  } finally { await t.dispose(); }
  report();
  process.exit(0);
}

// قفل: مشغّل واحد فقط على نفس الفهرس
const lock = join(idx, ".lock");
if (existsSync(lock)) {
  const pid = +readFileSync(lock, "utf8");
  let alive = false; try { process.kill(pid, 0); alive = true; } catch {}
  if (alive) { console.error(`another indexer is running (pid ${pid})`); process.exit(2); }
}
writeFileSync(lock, String(process.pid));
const ac = new AbortController();
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => { console.log(`[${ts()}] ${sig}: saving checkpoint…`); ac.abort(); });

const { createTilawa } = await import("@tilawa/core/node");
const tilawa = await createTilawa();
let code = 0;
try {
  for (const t of tracks) {
    const done = readTrack(t, idx);
    if (done?.complete && limitMs == null) { console.log(`[${ts()}] #${t.number} already complete (${done.ayahsVerified} verified, ${done.gaps.length} gaps)`); continue; }
    const t0 = Date.now();
    console.log(`[${ts()}] #${t.number} ${t.from.join(":")}→${t.to.join(":")} start`);
    let lastLog = 0;
    const r = await indexTrack(t, idx, {
      tilawa, signal: ac.signal, limitMs,
      onCheckpoint: (ms) => console.log(`[${ts()}] #${t.number} pass1 ${(ms / 1000).toFixed(0)}s`),
      onProgress: ({ done, total }) => { if (done - lastLog >= 25 || done === total) { lastLog = done; console.log(`[${ts()}] #${t.number} verify ${done}/${total}`); } },
    });
    console.log(`[${ts()}] #${t.number} done in ${((Date.now() - t0) / 1000).toFixed(0)}s: ${r.ayahsVerified} verified starts, ${r.gaps.length} gaps${r.resumed ? " (resumed)" : ""}`);
  }
} catch (e) {
  if (e.name === "AbortError") { console.log(`[${ts()}] aborted; rerun to resume`); code = 130; } else { console.error(e); code = 1; }
} finally {
  await tilawa.dispose();
  try { unlinkSync(lock); } catch {}
}
report();
process.exit(code);
