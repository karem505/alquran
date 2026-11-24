// تجربة سريعة: ملف صوتي → Tilawa → طباعة الأحداث مختصرة
// node tools/probe.mjs <audio> [--from S] [--dur S] [--mem s:a-b]
import { spawn } from "node:child_process";
import { createTilawa } from "@tilawa/core/node";

const args = process.argv.slice(2);
const file = args[0];
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const from = opt("--from", "0"), dur = opt("--dur", "60"), mem = opt("--mem", null);

const t0 = Date.now();
const tilawa = await createTilawa({
  onProgress: (p) => process.stderr.write(`\rload ${p.stage} ${(p.fraction * 100).toFixed(0)}% ${p.fromCache ? "cache" : ""}   `),
});
process.stderr.write(`\nloaded in ${Date.now() - t0}ms model=${JSON.stringify(tilawa.model)}\n`);

let session;
if (mem) {
  const [s, r] = mem.split(":"); const [a, b] = r.split("-");
  session = tilawa.startMemorization({ surah: +s, fromAyah: +a, toAyah: +b }, { confirm: { after: "next-word" } });
} else session = tilawa.startFreeRecitation();

let lastKey = "";
session.subscribe((e) => {
  if (e.type === "position") {
    const o = e.observed[0];
    const k = `${e.state} ${o ? `${o.word.surah}:${o.word.ayah}:${o.word.word}` : "-"} ${e.expected ? `exp ${e.expected.surah}:${e.expected.ayah}:${e.expected.word}` : ""}${e.relocated ? ` RELOC ${JSON.stringify(e.relocated)}` : ""}${e.spanHold ? " spanHold" : ""}${e.hold ? " hold" : ""}`;
    if (k !== lastKey) { console.log(`${(e.timeMs / 1000).toFixed(1)}s POS ${k} conf=${o ? o.confidence.toFixed(2) : "-"} n=${e.observed.length}`); lastKey = k; }
  } else if (e.type === "checker") {
    console.log(`${(e.timeMs / 1000).toFixed(1)}s CHK ${e.state} ${e.errorClass} ${e.location.surah}:${e.location.ayah}:${e.location.word} exp=${e.expected ?? ""} obs=${e.observed ?? ""} c=${e.confidence.toFixed(2)}`);
  } else console.log("CAP", JSON.stringify(e));
});

const ff = spawn("ffmpeg", ["-v", "error", "-ss", from, "-t", dur, "-i", file, "-ac", "1", "-ar", "16000", "-f", "f32le", "-"]);
const t1 = Date.now();
let pending = Buffer.alloc(0);
for await (const chunk of ff.stdout) {
  pending = Buffer.concat([pending, chunk]);
  const n = Math.floor(pending.length / 4) * 4;
  const buf = pending.subarray(0, n); pending = pending.subarray(n);
  const f = new Float32Array(buf.buffer.slice(buf.byteOffset, buf.byteOffset + n));
  session.pushAudio(f, 16000);
}
await session.end();
const el = (Date.now() - t1) / 1000;
console.log(`DONE audio=${(session.now() / 1000).toFixed(1)}s wall=${el.toFixed(1)}s RTF=${(el / (session.now() / 1000)).toFixed(2)}`);
console.log("MISTAKES", JSON.stringify(session.mistakes().map((m) => [m.errorClass, m.location])));
await tilawa.dispose();
