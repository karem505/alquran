import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { createConnection } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const order = (s, a) => s * 1000 + a;
export function wordAt(words, ms) {
  let lo = 0, hi = words.length;
  while (lo < hi) {
    const mid = (lo + hi) >>> 1;
    if (words[mid][0] <= ms) lo = mid + 1;
    else hi = mid;
  }
  return lo ? words[lo - 1] : null;
}

export async function playLocal({file, startMs, endMs, stopMs, speed = 1, tick, signal}) {
  signal.throwIfAborted();
  const dir = mkdtempSync(join(process.env.XDG_RUNTIME_DIR || tmpdir(), 'msh-'));
  const path = join(dir, 'mpv.sock');
  const args = ['--no-config', '--no-video', '--no-terminal', '--no-input-default-bindings',
    `--input-ipc-server=${path}`, `--start=${startMs / 1000}`, '--hr-seek=yes', `--speed=${speed}`];
  if (endMs != null) args.push(`--ab-loop-a=${startMs / 1000}`, `--ab-loop-b=${endMs / 1000}`);
  else if (stopMs != null) args.push(`--end=${stopMs / 1000}`);
  if (process.env.MUSHAFI_LISTEN_AUDIO_OUTPUT === 'null') args.push('--ao=null');
  const proc = spawn('mpv', [...args, '--', file], { stdio: ['ignore', 'ignore', 'pipe'] });
  let socket, buffer = '', stderr = '', exit = null;
  proc.stderr.on('data', b => { stderr = (stderr + b).slice(-1000); });
  const closed = new Promise(resolve => {
    proc.once('error', error => { exit = {error}; resolve(exit); });
    proc.once('close', code => { if (!exit) exit = {code}; resolve(exit); });
  });
  const stop = () => { socket?.destroy(); proc.kill(); };
  signal.addEventListener('abort', stop, {once:true});
  try {
    for (let tries = 0; tries < 100 && !exit && !socket; tries++) {
      signal.throwIfAborted();
      socket = await new Promise(resolve => {
        const s = createConnection(path);
        // Leave the error listener in place after connect (mpv might exit before the first command).
        s.on('error', () => { s.destroy(); resolve(null); });
        s.once('connect', () => resolve(s));
      });
      if (!socket) await delay(25, null, {signal});
    }
    if (!socket && !exit) throw new Error('mpv IPC did not start');
    if (socket) {
      socket.setEncoding('utf8');
      socket.on('data', data => {
        buffer += data;
        let i;
        while ((i = buffer.indexOf('\n')) >= 0) {
          const line = buffer.slice(0, i);
          buffer = buffer.slice(i + 1);
          let e;
          try { e = JSON.parse(line); } catch { continue; }
          if (e.event === 'property-change' && e.name === 'time-pos' && typeof e.data === 'number') tick(e.data * 1000);
        }
      });
      socket.write(JSON.stringify({command: ['observe_property', 1, 'time-pos']}) + '\n');
    }
    const result = await closed;
    signal.throwIfAborted();
    if (result.error || result.code !== 0) throw result.error || new Error(`mpv exited ${result.code}: ${stderr}`);
  } finally {
    signal.removeEventListener('abort', stop);
    stop();
    await closed;
    rmSync(dir, {recursive:true, force:true});
  }
}

export class HusaryPlayback {
  constructor({emit, indexApi = () => import('./husary-index.mjs'), player = playLocal, tilawa = () => null}) {
    Object.assign(this, {emit, indexApi, player, tilawa});
    this.active = null;
    this.echoUntil = 0;
  }
  get blocksMic() { return this.active !== null || Date.now() < this.echoUntil; }
  stop(notify = true) {
    const r = this.active;
    if (r) {
      this.active = null;
      if (r.audible) this.echoUntil = Date.now() + 400;
      r.abort.abort();
    }
    if (notify) this.emit({ev:'listen',st:'stopped'});
  }
  async start(s, a, {repeat = false, speed = 1} = {}) {
    if (this.active) this.stop(false);
    const r = {abort: new AbortController(), audible:false};
    const signal = r.abort.signal;
    this.active = r;
    const send = (st, extra = {}) => this.emit({ev:'listen', st, s, a, ...extra});
    try {
      if (!Number.isInteger(s) || !Number.isInteger(a) || s < 1 || s > 114 || a < 1 || a > 286) throw new Error('موضع الآية غير صالح.');
      const lib = await this.indexApi();
      signal.throwIfAborted();
      let tracks;
      try { tracks = lib.scanLibrary(lib.defaultLibrary); }
      catch (e) {
        if (e.code === 'ENOENT' || e.code === 'ENOTDIR') throw new Error('مجلد تسجيلات الحصري المحلية غير موجود.');
        throw e;
      }
      const key = order(s,a);
      const candidates = tracks.filter(t => order(...t.from) <= key && key <= order(...t.to));
      if (!candidates.length) throw new Error('لم يُعثر على تسجيل محلي للحصري يغطي هذه الآية.');
      const indexed = t => lib.readTrack(t, lib.defaultIndexDir);
      // Repair zones: spans of the local recording with an edit cut, replaced at playback
      // time by the same ayat from the complete page-split edition (see husary-index.mjs).
      const zones = (lib.readSupplement?.(tracks)?.zones || []).slice().sort((x, y) => x.track - y.track || x.fromMs - y.fromMs);
      const zoneOf = (n, k) => zones.find(z => z.track === n && z.segments.some(g => g.key === k));
      const zonesIn = n => zones.filter(z => z.track === n);
      speed = typeof speed === 'number' ? Math.max(.65, Math.min(1.35, speed)) : 1;
      const playPiece = async ({file, startMs: from, stopMs, endMs, words, label}) => {
        let last = null, playing = false;
        r.audible = true;
        await this.player({file, startMs: from, stopMs, endMs, speed, signal, tick: ms => {
          if (this.active !== r) return;
          if (!playing) { playing = true; send('playing', {file: label, startMs: from}); }
          const w = ms >= from - 12 ? wordAt(words, Math.max(ms, from)) : null;
          if (!w || w[0] < from || w === last || (last && w[0] === last[0])) return;
          last = w;
          this.emit({ev:'listenWord',w:w.slice(1),ms:Math.round(ms)});
        }});
        signal.throwIfAborted();
      };
      const playZone = async (segments) => {
        for (let i = 0; i < segments.length;) {
          let j = i;
          while (j + 1 < segments.length && segments[j + 1].file === segments[i].file && segments[j + 1].startMs === segments[j].endMs) j++;
          const run = segments.slice(i, j + 1);
          await playPiece({file: run[0].file, startMs: run[0].startMs, stopMs: run.at(-1).endMs,
            words: run.flatMap(g => g.words), label: 'supplement'});
          i = j + 1;
        }
      };
      const sk = `${s}:${a}`, targetZone = zoneOf(candidates.find(t => zoneOf(t.number, sk))?.number, sk);
      if (targetZone && repeat) {
        const seg = targetZone.segments.find(g => g.key === sk);
        await playPiece({file: seg.file, startMs: seg.startMs, endMs: seg.endMs, words: seg.words, label: 'supplement'});
        if (r.audible) this.echoUntil = Date.now() + 400;
        this.active = null;
        send('stopped');
        return;
      }
      const ensure = async (t, loaded, s0, a0) => {
        if (loaded && lib.findAyah(loaded, s0, a0) != null) return loaded;
        send('indexing', {s:s0, a:a0});
        return await lib.indexTrack(t, lib.defaultIndexDir, {tilawa:this.tilawa() || undefined, signal, target:[s0,a0]});
      };
      let track, data, startMs, startKey = null;
      if (targetZone) {
        track = tracks.find(t => t.number === targetZone.track);
        data = indexed(track);
        startMs = targetZone.fromMs; startKey = sk;
      } else {
        const first = candidates.map(t => [t,indexed(t)]).find(([,d]) => d && lib.findAyah(d,s,a) != null) || [candidates[0], null];
        [track, data] = first;
        data = await ensure(track, data, s, a);
        signal.throwIfAborted();
        startMs = data && lib.findAyah(data,s,a);
      }
      if (startMs == null) throw new Error('تعذّر تأكيد بداية الآية في التسجيل. لم يُشغّل موضع تقريبي.');
      for (let i = tracks.indexOf(track); i < tracks.length; i++) {
        if (repeat) {
          const seq = lib.ordinal || order;
          const targetOrd = seq(s,a);
          const next = data.words.find(w => w[0] > startMs && seq(w[1],w[2]) === targetOrd + 1 && w[3] === 1);
          let endMs = next && lib.findAyah(data,next[1],next[2]);
          if (endMs == null && key === order(...track.to) && data.complete) endMs = data.durationMs;
          if (!(endMs > startMs)) throw new Error('لم تتأكد نهاية الآية بعد؛ لا يمكن تكرارها.');
          await playPiece({file: track.file, startMs, endMs, words: data.words, label: track.number});
          break;
        }
        const zs = zonesIn(track.number);
        for (;;) {
          const inside = zs.find(z => z.fromMs <= startMs && startMs < z.toMs);
          if (inside) {
            const k = startKey ? Math.max(0, inside.segments.findIndex(g => g.key === startKey)) : 0;
            startKey = null;
            await playZone(inside.segments.slice(k));
            startMs = inside.toMs;
            if (startMs >= data.durationMs) break;
            continue;
          }
          const ahead = zs.find(z => z.fromMs > startMs);
          await this.#playLocalPiece(r, send, track, () => data, d => { data = d; }, indexed, startMs, ahead?.fromMs, speed, signal);
          if (!ahead) break;
          startMs = ahead.fromMs;
        }
        if (i + 1 === tracks.length) break;
        const nextTrack = tracks[i+1];
        const after = order(...track.to);
        const startsAfter = order(...nextTrack.from) > after;
        const [ns,na] = startsAfter ? nextTrack.from : [track.to[0],track.to[1] + 1];
        track = nextTrack;
        const nz = zoneOf(track.number, `${ns}:${na}`);
        if (nz) { data = indexed(track); startMs = nz.fromMs; startKey = `${ns}:${na}`; continue; }
        const nextIndex = indexed(track);
        data = startsAfter && nextIndex?.complete ? nextIndex : await ensure(track, nextIndex, ns, na);
        signal.throwIfAborted();
        startMs = data && lib.findAyah(data,ns,na);
        if (startMs == null && startsAfter && data) startMs = 0; // Known recording boundary, not a fabricated ayah timestamp.
        if (startMs == null) throw new Error('لم تتأكد بداية الموضع التالي في التسجيل.');
      }
      if (r.audible) this.echoUntil = Date.now() + 400;
      this.active = null;
      send('stopped');
    } catch (e) {
      if (this.active !== r || signal.aborted) return;
      if (r.audible) this.echoUntil = Date.now() + 400;
      this.active = null;
      const msg = /[\u0600-\u06ff]/.test(e.message) ? e.message : 'تعذّر تشغيل تسجيل الحصري. تأكّد من تثبيت mpv وتوفّر الملفات المحلية.';
      send('error', {msg,detail:String(e.message || e)});
    }
  }
  async #playLocalPiece(r, send, track, getData, setData, indexed, startMs, stopMs, speed, signal) {
    let last = null, playing = false, checkedAt = 0;
    r.audible = true;
    await this.player({file:track.file, startMs, stopMs, speed, signal, tick: ms => {
      if (this.active !== r) return;
      if (!playing) { playing = true; send('playing', {file:track.number, startMs}); }
      let data = getData();
      // Refresh while a pre-indexed prefix plays and the same file is still being indexed.
      if (data.complete === false && Date.now() - checkedAt > 1000) {
        checkedAt = Date.now();
        data = indexed(track) || data; setData(data);
      }
      if (data.complete === false && ms > data.analyzedMs) {
        if (last) { last = null; this.emit({ev:'listenWord',w:null}); }
        return;
      }
      const w = ms >= startMs - 12 ? wordAt(data.words, Math.max(ms, startMs)) : null;
      if (!w || w[0] < startMs || w === last || (last && w[0] === last[0])) return;
      last = w;
      this.emit({ev:'listenWord',w:w.slice(1),ms:Math.round(ms)});
    }});
    signal.throwIfAborted();
  }
}
