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

export async function playLocal({file, startMs, endMs, speed = 1, tick, signal}) {
  signal.throwIfAborted();
  const dir = mkdtempSync(join(process.env.XDG_RUNTIME_DIR || tmpdir(), 'msh-'));
  const path = join(dir, 'mpv.sock');
  const args = ['--no-config', '--no-video', '--no-terminal', '--no-input-default-bindings',
    `--input-ipc-server=${path}`, `--start=${startMs / 1000}`, '--hr-seek=yes', `--speed=${speed}`];
  if (endMs != null) args.push(`--ab-loop-a=${startMs / 1000}`, `--ab-loop-b=${endMs / 1000}`);
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
      const ensure = async (t, loaded, s0, a0) => {
        if (loaded && lib.findAyah(loaded, s0, a0) != null) return loaded;
        send('indexing', {s:s0, a:a0});
        return await lib.indexTrack(t, lib.defaultIndexDir, {tilawa:this.tilawa() || undefined, signal, target:[s0,a0]});
      };
      const first = candidates.map(t => [t,indexed(t)]).find(([,d]) => d && lib.findAyah(d,s,a) != null) || [candidates[0], null];
      let [track, data] = first;
      data = await ensure(track, data, s, a);
      signal.throwIfAborted();
      let startMs = data && lib.findAyah(data,s,a);
      if (startMs == null) throw new Error('تعذّر تأكيد بداية الآية في التسجيل. لم يُشغّل موضع تقريبي.');
      speed = typeof speed === 'number' ? Math.max(.65, Math.min(1.35, speed)) : 1;
      for (let i = tracks.indexOf(track); i < tracks.length; i++) {
        let endMs;
        if (repeat) {
          const seq = lib.ordinal || order;
          const targetOrd = seq(s,a);
          const next = data.words.find(w => w[0] > startMs && seq(w[1],w[2]) === targetOrd + 1 && w[3] === 1);
          endMs = next && lib.findAyah(data,next[1],next[2]);
          if (endMs == null && key === order(...track.to) && data.complete) endMs = data.durationMs;
          if (!(endMs > startMs)) throw new Error('لم تتأكد نهاية الآية بعد؛ لا يمكن تكرارها.');
        }
        let last = null, playing = false, checkedAt = 0;
        r.audible = true;
        await this.player({file:track.file, startMs, endMs, speed, signal, tick: ms => {
          if (this.active !== r) return;
          if (!playing) { playing = true; send('playing', {file:track.number, startMs}); }
          // Refresh while a pre-indexed prefix plays and the same file is still being indexed.
          if (data.complete === false && Date.now() - checkedAt > 1000) {
            checkedAt = Date.now();
            data = indexed(track) || data;
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
        if (repeat || i + 1 === tracks.length) break;
        const nextTrack = tracks[i+1];
        const after = order(...track.to);
        const startsAfter = order(...nextTrack.from) > after;
        const [ns,na] = startsAfter ? nextTrack.from : [track.to[0],track.to[1] + 1];
        track = nextTrack;
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
}
