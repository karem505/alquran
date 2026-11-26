// فهرسة تسجيلات الحصري (أوفلاين، Tilawa محلي). استئنافية: أعد التشغيل فتكمل من آخر نقطة.
//   nice -n 19 ionice -c3 node tools/index-husary.mjs [--jobs 2]       # كل المسارات الناقصة
//   node tools/index-husary.mjs --tracks 1,5-7 [--limit-ms 120000]     # مسارات محددة / تجربة قصيرة
//   node tools/index-husary.mjs --status                               # التغطية مقابل 6236 دون تشغيل
// --library DIR (أو MUSHAFI_REF_AUDIO)   --index DIR (أو MUSHAFI_HUSARY_INDEX)
// الصوت للقراءة فقط. SIGINT/SIGTERM تحفظ نقطة استئناف ثم تخرج.
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { fork } from "node:child_process";
import { join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { scanLibrary, readTrack, indexTrack, certifyClip, coverage, defaultLibrary, defaultIndexDir, TOTAL_AYAHS } from "../husary-index.mjs";

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const lib = opt("--library", defaultLibrary), idx = opt("--index", defaultIndexDir);
const limitMs = opt("--limit-ms", null) != null ? +opt("--limit-ms") : null;
const jobs = +opt("--jobs", 1), verifyJobs = +opt("--verify-jobs", 1);
if (![1, 2].includes(jobs) || ![1, 2].includes(verifyJobs) || jobs * verifyJobs > 2) {
  console.error("--jobs / --verify-jobs: choose 1 or 2; only one may be 2");
  process.exit(2);
}
const only = opt("--tracks", null);
const wanted = only ? new Set(only.split(",").flatMap((p) => { const [a, b = a] = p.split("-").map(Number); return Array.from({ length: b - a + 1 }, (_, i) => a + i); })) : null;
const ts = () => new Date().toISOString().slice(11, 19);

const tracks = scanLibrary(lib).filter((t) => !wanted || wanted.has(t.number));
const worker = process.connected && argv.includes("--index-worker");
const pending = tracks.filter(t => limitMs != null || !readTrack(t, idx)?.complete);
const groups = Array.from({ length: Math.min(jobs, pending.length) }, () => []);
pending.forEach((t, i) => groups[i % groups.length].push(t.number));

function report() {
  const c = coverage(scanLibrary(lib), idx);
  console.log(`[${ts()}] coverage: ${c.ayahsWithStart}/${TOTAL_AYAHS} ayahs with verified start, ${c.ayahsSupplemented} from the supplement (${c.ayahsPlayable}/${TOTAL_AYAHS} playable), ${c.tracksComplete}/${c.tracksTotal} tracks complete, ${c.gaps.length} gap entries`);
  return c;
}
if (argv.includes("--status")) { report(); process.exit(0); }
// --export DIR: الفهرس المؤكد + المكمّل + md5 لكل تسجيل (بلا صوت)
// --import DIR [--fetch-supplement]: يقبل فهرس كل تسجيل مطابق بالحجم والـ md5، ويكتب البصمة المحلية
if (argv.includes("--export") || argv.includes("--import")) {
  const { exportBundle, importBundle } = await import("../husary-bundle.mjs");
  const all = scanLibrary(lib);
  if (argv.includes("--export")) {
    const m = await exportBundle(all, opt("--export"), { indexDir: idx });
    console.log(`exported ${m.tracks.length} recordings, ${m.supplement?.pages.length ?? 0} supplement pages listed, playable ${m.coverage.playable}/${TOTAL_AYAHS}`);
  } else {
    const r = await importBundle(all, opt("--import"), { indexDir: idx, fetch: argv.includes("--fetch-supplement") });
    console.log(`imported ${r.imported} recordings; skipped ${r.skipped.length}${r.skipped.length ? " (" + r.skipped.map(s => `${s.number}: ${s.why}`).join("; ") + ")" : ""}; supplement pages ok ${r.supplementPages.ok}, missing ${r.supplementPages.missing}`);
    report();
  }
  process.exit(0);
}
if (argv.includes("--dry-run")) {
  groups.forEach((group, i) => console.log(`process ${i+1}: ${group.join(",")}`));
  process.exit(0);
}
mkdirSync(idx, { recursive: true });
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
if (!worker && existsSync(lock)) {
  const pid = +readFileSync(lock, "utf8");
  let alive = false; try { process.kill(pid, 0); alive = true; } catch {}
  if (alive) { console.error(`another indexer is running (pid ${pid})`); process.exit(2); }
  unlinkSync(lock);
}
if (!worker) writeFileSync(lock, String(process.pid), { flag: "wx", mode: 0o600 });
const ac = new AbortController();
function stop(sig) {
  if (ac.signal.aborted) return;
  console.log(`[${ts()}] ${sig}: saving checkpoint…`);
  ac.abort();
}
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => stop(sig));
if (worker) process.on("disconnect", () => stop("parent disconnected"));

function runWorker(group) {
  return new Promise((resolve, reject) => {
    const args = ["--index-worker", "--library", lib, "--index", idx, "--tracks", group.join(",")];
    if (limitMs != null) args.push("--limit-ms", String(limitMs));
    const child = fork(fileURLToPath(import.meta.url), args, { stdio: ["inherit", "inherit", "inherit", "ipc"] });
    const cancel = () => child.kill("SIGTERM");
    ac.signal.addEventListener("abort", cancel, { once: true });
    if (ac.signal.aborted) cancel();
    child.once("error", error => { ac.signal.removeEventListener("abort", cancel); reject(error); });
    child.once("exit", (code, signal) => {
      ac.signal.removeEventListener("abort", cancel);
      if (code === 0) resolve();
      else reject(ac.signal.aborted ? ac.signal.reason : new Error(`index worker exited (${code ?? signal})`));
    });
  });
}

let tilawa, code = 0;
try {
  if (!worker && groups.length > 1) {
    console.log(`[${ts()}] parallel track processes=${groups.length}`);
    const results = await Promise.allSettled(groups.map(runWorker));
    ac.signal.throwIfAborted();
    const failed = results.find(r => r.status === "rejected");
    if (failed) throw failed.reason;
  } else if (pending.length) {
    const { createTilawa } = await import("@tilawa/core/node");
    tilawa = await createTilawa({ threads: 1, signal: ac.signal });
    console.log(`[${ts()}] verification workers per track=${verifyJobs}`);
    for (const t of pending) {
      ac.signal.throwIfAborted();
      const t0 = Date.now();
      console.log(`[${ts()}] #${t.number} ${t.from.join(":")}→${t.to.join(":")} start`);
      let lastLog = 0;
      const r = await indexTrack(t, idx, {
        tilawa, signal: ac.signal, limitMs, verifyJobs,
        onCheckpoint: (ms) => console.log(`[${ts()}] #${t.number} pass1 ${(ms / 1000).toFixed(0)}s`),
        onProgress: ({ done, total }) => { if (done - lastLog >= 25 || done === total) { lastLog = done; console.log(`[${ts()}] #${t.number} verify ${done}/${total}`); } },
      });
      console.log(`[${ts()}] #${t.number} done in ${((Date.now() - t0) / 1000).toFixed(0)}s: ${r.ayahsVerified} verified starts, ${r.gaps.length} gaps${r.resumed ? " (resumed)" : ""}`);
    }
  }
} catch (e) {
  if (e.name === "AbortError") { console.log(`[${ts()}] aborted; rerun to resume`); code = 130; } else { console.error(e); code = 1; }
} finally {
  try { await tilawa?.dispose(); } finally { if (!worker) try { unlinkSync(lock); } catch {} }
}
if (!worker) report();
process.exit(code);
