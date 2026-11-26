// حزمة فهرس الحصري: تصدير الفهرس المؤكَّد ونقله إلى جهاز آخر عليه نفس التسجيلات.
// البصمة المحلية (الحجم + وقت التعديل) تختلف بين الأجهزة، لذلك تحمل الحزمة md5 لكل تسجيل،
// والاستيراد لا يقبل فهرس تسجيل إلا لو تطابق الحجم والـ md5 مع الملف المحلي، ثم يكتب البصمة المحلية.
// لا تحتوي الحزمة على أي صوت.
import { createHash } from "node:crypto";
import { copyFileSync, createReadStream, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, isAbsolute } from "node:path";
import { spawnSync } from "node:child_process";
import { SCHEMA, TOTAL_AYAHS, trackFile, coverage, defaultIndexDir, defaultSupplementFile } from "./husary-index.mjs";

export const SUPPLEMENT_ITEM = "rabieaaa2474257457457485243572457247";
export const md5File = (file) => new Promise((ok, fail) => {
  const h = createHash("md5"); createReadStream(file).on("data", d => h.update(d)).on("end", () => ok(h.digest("hex"))).on("error", fail);
});
const readJson = (f) => JSON.parse(readFileSync(f, "utf8"));
const writeJson = (f, o) => { writeFileSync(`${f}.tmp`, JSON.stringify(o)); renameSync(`${f}.tmp`, f); };

export async function exportBundle(tracks, outDir, { indexDir = defaultIndexDir, supplementFile = defaultSupplementFile } = {}) {
  const c = coverage(tracks, indexDir, supplementFile);
  mkdirSync(outDir, { recursive: true });
  const manifest = { schema: SCHEMA, kind: "mushafi-husary-index", createdAt: new Date().toISOString(),
    coverage: { totalAyahs: TOTAL_AYAHS, verifiedLocal: c.ayahsWithStart, fromSupplement: c.ayahsSupplemented, playable: c.ayahsPlayable },
    tracks: [], supplement: null };
  for (const t of tracks) {
    const files = ["", ".certified"].map(k => trackFile(t, indexDir, k)).filter(existsSync);
    if (!files.length) continue;
    for (const f of files) copyFileSync(f, join(outDir, f.split("/").pop()));
    manifest.tracks.push({ number: t.number, title: t.title, size: t.size, md5: await md5File(t.file), from: t.from, to: t.to });
  }
  if (existsSync(supplementFile)) {
    const sup = readJson(supplementFile), base = dirname(supplementFile), pages = new Map();
    for (const z of sup.zones) for (const g of z.segments) {
      const abs = isAbsolute(g.file) ? g.file : join(base, g.file);
      g.file = relative(base, abs);
      if (!pages.has(g.file)) pages.set(g.file, { file: g.file, size: statSync(abs).size, md5: await md5File(abs) });
    }
    writeJson(join(outDir, "supplement.json"), sup);
    manifest.supplement = { source: `https://archive.org/details/${SUPPLEMENT_ITEM}`, pages: [...pages.values()] };
  }
  writeJson(join(outDir, "manifest.json"), manifest);
  return manifest;
}

function fetchPage(name, dst) {
  mkdirSync(dirname(dst), { recursive: true });
  const r = spawnSync("curl", ["-sSL", "--fail", "--max-time", "300", "-o", `${dst}.part`, `https://archive.org/download/${SUPPLEMENT_ITEM}/${name.split("/").pop()}`], { stdio: "inherit" });
  if (r.status === 0) renameSync(`${dst}.part`, dst);
}

// Returns {imported, skipped:[{number, why}], supplementPages:{ok, missing}}.
export async function importBundle(tracks, bundleDir, { indexDir = defaultIndexDir, supplementFile = defaultSupplementFile, fetch = false } = {}) {
  const m = readJson(join(bundleDir, "manifest.json"));
  if (m.schema !== SCHEMA || m.kind !== "mushafi-husary-index") throw new Error("not a mushafi husary index bundle");
  mkdirSync(indexDir, { recursive: true });
  const byNumber = new Map(tracks.map(t => [t.number, t])), skipped = [], fp = {};
  let imported = 0;
  for (const e of m.tracks) {
    const t = byNumber.get(e.number);
    if (!t) { skipped.push({ number: e.number, why: "no local recording" }); continue; }
    if (t.size !== e.size || await md5File(t.file) !== e.md5) { skipped.push({ number: e.number, why: "different recording (size/md5)" }); continue; }
    fp[e.number] = { size: t.size, mtimeMs: t.mtimeMs };
    for (const kind of ["", ".certified"]) {
      const src = join(bundleDir, trackFile(t, "", kind).replace(/^\//, ""));
      if (!existsSync(src)) continue;
      const d = readJson(src); d.fingerprint = fp[e.number];
      writeJson(trackFile(t, indexDir, kind), d);
    }
    imported++;
  }
  const supplementPages = { ok: 0, missing: 0 };
  if (m.supplement && existsSync(join(bundleDir, "supplement.json"))) {
    const base = dirname(supplementFile), sup = readJson(join(bundleDir, "supplement.json"));
    for (const p of m.supplement.pages) {
      const abs = join(base, p.file);
      const good = async () => existsSync(abs) && statSync(abs).size === p.size && await md5File(abs) === p.md5;
      if (!(await good()) && fetch) fetchPage(p.file, abs);
      if (await good()) supplementPages.ok++; else supplementPages.missing++;
    }
    sup.zones = sup.zones.filter(z => fp[z.track]).map(z => ({ ...z, fingerprint: fp[z.track] }));
    mkdirSync(base, { recursive: true });
    writeJson(supplementFile, sup);
  }
  return { imported, skipped, supplementPages };
}
