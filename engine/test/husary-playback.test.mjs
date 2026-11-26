import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { HusaryPlayback, wordAt } from '../husary-playback.mjs';

const word = [[100, 1, 1, 1], [300, 1, 1, 2], [800, 1, 2, 1]];
test('highlight uses the latest confirmed word at the player clock, never the next word', () => {
  assert.equal(wordAt(word, 99), null);
  assert.deepEqual(wordAt(word, 300), word[1]);
  assert.deepEqual(wordAt(word, 650), word[1]);
  assert.deepEqual(wordAt(word, 900), word[2]);
});

const track = {number: 1, file: '/offline/example.mp3', from: [1, 1], to: [1, 2]};
const index = {words: word, durationMs: 1000};
function fixture(overrides = {}) {
  const events = [], played = [];
  const library = {scanLibrary: () => [track], readTrack: () => index,
    indexTrack: async () => index, findAyah: (data, s, a) => data.words.find(x => x[1] === s && x[2] === a && x[3] === 1)?.[0] ?? null};
  const playback = new HusaryPlayback({emit: e => events.push(e), indexApi: async () => library,
    player: async ({startMs, tick, signal}) => { played.push(startMs); tick(startMs); await delay(20, null, {signal}); }, ...overrides});
  return {playback, library, events, played};
}
test('play seeks to first word of selected ayah and does not contact indexer for known timestamp', async () => {
  const {playback, library, events, played} = fixture();
  library.indexTrack = () => assert.fail('indexed ayah was indexed again');
  const completion = playback.start(1, 2);
  assert.equal(playback.blocksMic, true);
  await completion;
  assert.deepEqual(played, [800]);
  assert.deepEqual(events.filter(e => e.ev === 'listenWord').map(e => e.w), [[1, 2, 1]]);
  assert.equal(events.at(-1).st, 'stopped');
});
test('stop during indexing cancels the requested listen and does not start playback later', async () => {
  const {playback, library, events, played} = fixture();
  library.readTrack = () => null;
  library.indexTrack = async (_track, _index, {signal}) => { await delay(100, null, {signal}); return index; };
  const completion = playback.start(1, 1);
  await delay(5);
  playback.stop();
  await completion;
  assert.deepEqual(played, []);
  assert.deepEqual(events.map(e => e.st), ['indexing', 'stopped']);
});
test('after the end of a recording, playback continues in the next file without replaying the overlap', async () => {
  const {playback, library, played} = fixture();
  const second = {...track, number:2, file:'/offline/next.mp3', from:[1,2], to:[1,3]};
  library.scanLibrary = () => [track,second];
  library.readTrack = t => t === track ? index : {words:[[50,1,2,1],[600,1,3,1]],durationMs:1300};
  await playback.start(1,2);
  assert.deepEqual(played,[800,600]);
});

test('a non-overlapping next recording starts at the beginning if its first ayah is not indexed', async () => {
  const {playback, library, played} = fixture();
  const second = {...track, number:2, file:'/offline/next.mp3', from:[1,3], to:[1,4]};
  const nextData = {words:[[460,1,4,1]],durationMs:1300};
  library.scanLibrary = () => [track,second];
  library.readTrack = t => t === track ? index : nextData;
  library.indexTrack = async () => nextData;
  await playback.start(1,2);
  assert.deepEqual(played,[800,0]);
});

test('restarting playback cancels the old request without reporting the replacement stopped', async () => {
  const {playback, events, played} = fixture();
  const first = playback.start(1, 1);
  await delay(5);
  const second = playback.start(1, 2);
  await Promise.all([first, second]);
  assert.deepEqual(played,[100,800]);
  assert.equal(events.filter(e => e.st === 'stopped').length,1);
  assert.equal(events.at(-1).a,2);
});

test('unconfirmed ayah never plays an estimated or nearby verse', async () => {
  const {playback, library, events, played} = fixture();
  library.readTrack = () => null;
  library.indexTrack = async () => ({words: [], durationMs: 1000});
  await playback.start(1, 2);
  assert.deepEqual(played, []);
  assert.equal(events.at(-1).st, 'error');
});

// A recording with an edit cut: 1:3 opens with missing words. The repair zone swaps the
// local audio between the verified starts of 1:2 and 1:4 for the complete page edition.
function cutFixture() {
  const calls = [];
  const local = {...track, to: [1, 4]};
  const data = {words: [[100,1,1,1],[800,1,2,1],[1200,1,3,4],[1500,1,4,1]], durationMs: 2000, complete: true};
  const zone = {track: 1, fromMs: 800, toMs: 1500, segments: [
    {key:'1:2', file:'/supp/p1.mp3', startMs:5000, endMs:7000, words:[[5000,1,2,1]]},
    {key:'1:3', file:'/supp/p1.mp3', startMs:7000, endMs:9000, words:[[7000,1,3,1],[7600,1,3,2]]}]};
  const f = fixture({player: async ({file, startMs, stopMs, endMs, tick, signal}) => {
    calls.push({file, startMs, stopMs, endMs}); tick(startMs); await delay(5, null, {signal}); }});
  f.library.scanLibrary = () => [local];
  f.library.readTrack = () => data;
  f.library.indexTrack = () => assert.fail('a supplemented ayah must not trigger re-indexing');
  f.library.readSupplement = () => ({zones: [zone]});
  return {...f, calls};
}
test('ayah missing from the local recording plays from the supplement, then resumes locally after the cut', async () => {
  const {playback, calls, events} = cutFixture();
  await playback.start(1, 3);
  assert.deepEqual(calls, [
    {file:'/supp/p1.mp3', startMs:7000, stopMs:9000, endMs:undefined},
    {file:'/offline/example.mp3', startMs:1500, stopMs:undefined, endMs:undefined}]);
  assert.deepEqual(events.filter(e => e.ev === 'listenWord').map(e => e.w), [[1,3,1],[1,4,1]]);
  assert.equal(events.at(-1).st, 'stopped');
});
test('local playback stops before a cut and plays the complete ayat from the supplement', async () => {
  const {playback, calls} = cutFixture();
  await playback.start(1, 1);
  assert.deepEqual(calls.map(c => [c.file, c.startMs, c.stopMs]), [
    ['/offline/example.mp3', 100, 800], ['/supp/p1.mp3', 5000, 9000], ['/offline/example.mp3', 1500, undefined]]);
});
test('repeating a supplemented ayah loops its supplement segment', async () => {
  const {playback, calls} = cutFixture();
  await playback.start(1, 3, {repeat: true});
  assert.deepEqual(calls, [{file:'/supp/p1.mp3', startMs:7000, stopMs:undefined, endMs:9000}]);
});
