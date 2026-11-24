// تقطيع تسجيل إلى آيات: يشغّل Tilawa (تسميع حر) على ملف ويحفظ زمن كل كلمة مقفولة
// node tools/segment.mjs <audio> <out.json> [--from S] [--dur S]
// المخرج: {file, from, words: [[ms, s, a, w], ...], ayahs: {"s:a": [startMs, endMs]}}
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { createTilawa } from "@tilawa/core/node";

const [file, out] = process.argv.slice(2);
const opt = (k, d) => { const i = process.argv.indexOf(k); return i >= 0 ? process.argv[i + 1] : d; };
const from = +opt("--from", "0"), dur = opt("--dur", null);

const tilawa = await createTilawa();
const session = tilawa.startFreeRecitation();
const words = [];
let last = "";
session.subscribe((e) => {
  if (e.type !== "position" || e.state !== "locked" || !e.observed[0]) return;
  const w = e.observed[0].word;
  const k = `${w.surah}:${w.ayah}:${w.word}`;
  if (k === last) return;
  last = k;
  words.push([e.timeMs, w.surah, w.ayah, w.word]);
});
const args = ["-v", "error", "-ss", String(from)];
if (dur) args.push("-t", dur);
args.push("-i", file, "-ac", "1", "-ar", "16000", "-f", "f32le", "-");
const ff = spawn("ffmpeg", args);
let pending = Buffer.alloc(0);
for await (const chunk of ff.stdout) {
  pending = Buffer.concat([pending, chunk]);
  const n = Math.floor(pending.length / 4) * 4;
  const f = new Float32Array(pending.buffer.slice(pending.byteOffset, pending.byteOffset + n));
  pending = pending.subarray(n);
  session.pushAudio(f, 16000);
}
await session.end();
// بداية الآية = زمن أول كلمة منها (word 1) أو أول ظهور لها؛ النهاية = بداية الآية التالية
const ayahs = {};
for (const [ms, s, a, w] of words) {
  const k = `${s}:${a}`;
  if (!ayahs[k]) ayahs[k] = [ms, ms];
  ayahs[k][1] = ms;
}
writeFileSync(out, JSON.stringify({ file, from, words, ayahs }));
console.log(`ok ${words.length} words, ${Object.keys(ayahs).length} ayahs, audio ${(session.now() / 1000).toFixed(0)}s`);
await tilawa.dispose();
