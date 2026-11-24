#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""بناء بيانات وضع التسميع: تخطيط صفحات مصحف المدينة (١٥ سطرًا) كلمةً كلمة.

المصادر:
  - تخطيط QPC V2 (صفحة ← سطر ← كلمة + رمز الخط لكل كلمة) من Quran.com API v4
    (نفس بيانات Quranic Universal Library — qul.tarteel.ai). تُخزَّن الردود الخام في
    data/raw/qpc-v2/<page>.json (خارج git) وتُنزَّل لو ناقصة.
  - مرجع Tilawa (engine/node_modules/@tilawa/core/assets/ref-v2.json، نص Tanzil العثماني):
    ترقيم الكلمات الذي يرسله المحرك (surah, ayah, word).
  - صور الصفحات (pages/pNNN.jpg، طبعة الوسط): تُقاس منها حدود كل سطر نصي أفقيًا لتطابق
    الكلمات المرندرة موضعها في الصورة.

المخرج: data/tasmee/layout.json
  {
    "v": 1, "src": ..., "geo": {...},
    "pages": [ <page 1>, ... <page 604> ],
    "suraFirst": {"<s>": [page, line]}
  }
  كل صفحة: {"l": [ line ... 15 ]}; السطر:
    {"t": "h", "s": <sura>}     ترويسة سورة (تبقى من الصورة)
    {"t": "b"}                  بسملة (تبقى من الصورة)
    {"t": "w", "x": [x0, x1], "y": cy, "w": [[glyph, s, a, t0, t1], ...]}
       t0..t1: مدى كلمات Tilawa (1-based) التي يغطيها رمز QPC؛ t0 = 0 ⇒ علامة نهاية الآية.
"""
import json, os, re, sys, time, urllib.request, concurrent.futures

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'data', 'raw', 'qpc-v2')
OUT = os.path.join(ROOT, 'data', 'tasmee')
REF = os.path.join(ROOT, 'engine', 'node_modules', '@tilawa', 'core', 'assets', 'ref-v2.json')
PAGES = os.path.join(ROOT, 'pages')
FIELDS = 'code_v2,text_uthmani,line_number,page_number,v2_page,line_v2'

# هندسة الصورة (807×1205) للصفحات 3..604: الإطار الداخلي الأبيض ثابت
INNER = (63, 64, 743, 1140)          # x0, y0, x1, y1
LINE_H = (INNER[3] - INNER[1]) / 15.0
INK_Y0, INK_DY = 113.3, 70.37      # مركز حبر السطر i (0-based) = INK_Y0 + INK_DY × i


def fetch(p):
    out = os.path.join(RAW, f'{p}.json')
    if os.path.exists(out):
        return
    url = (f'https://api.quran.com/api/v4/verses/by_page/{p}?words=true&word_fields={FIELDS}'
           f'&per_page=300&fields=verse_key')
    err = None
    for t in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'mushafi-build/1.0'})
            d = json.load(urllib.request.urlopen(req, timeout=40))
            assert d['pagination']['total_pages'] == 1
            json.dump(d, open(out, 'w'), ensure_ascii=False)
            return
        except Exception as e:  # noqa
            err = e
            time.sleep(2 + 3 * t)
    raise err


def skel(w):
    w = re.sub(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u0640\u200F\u200E\s]', '', w)
    return w.replace('ٱ', 'ا')


def word_map(tw, qw):
    """ربط كلمات QPC (قد تدمج كلمتين مثل «بعد ما») بمدى كلمات Tilawa. يرجع [(t0,t1)] لكل كلمة QPC."""
    if len(tw) == len(qw):
        return [(i + 1, i + 1) for i in range(len(qw))]
    out, j = [], 0
    for q in qw:
        target = skel(q)
        acc, j0 = '', j
        while j < len(tw) and len(acc) < len(target):
            acc += skel(tw[j])
            j += 1
        if acc != target:
            raise SystemExit(f'تعذّر الربط: {q} ↔ {tw[j0:j]}')
        out.append((j0 + 1, j))
    assert j == len(tw)
    return out


def measure_mask(p, lines):
    """حدود الغطاء الرأسية لكل سطر نص (بإحداثيات الصورة): حزمة السطر، لكن تتوقف قبل خطوط إطار
    ترويسة السورة المجاورة (صفوف داكنة تعبر عرض الصفحة) حتى لا يُمسح جزء من الإطار."""
    from PIL import Image
    import numpy as np
    a = np.asarray(Image.open(os.path.join(PAGES, f'p{p:03d}.jpg')).convert('RGB')).astype(int)
    # خط الإطار: صف داكن يعبر ٩٠٪ من العرض، ونبحث عنه قرب حافتي الحزمة فقط (١٢ بكسل) حتى لا
    # يُخلط بخط الكشيدة الممتد داخل نص السطر نفسه
    rule = (a.min(2)[:, 70:736] < 200).mean(1) > 0.9
    out = {}
    for i in lines:
        # تداخل بكسلين مع حزم الأسطر المجاورة (الأغطية تُرسم قبل النص كله فلا تقصّ حروفًا)
        top = INNER[1] + i * LINE_H - 2
        bot = INNER[1] + (i + 1) * LINE_H + 2
        hits = [y for y in range(int(top), int(top) + 12) if rule[y]]
        if hits:
            top = max(hits) + 2
        hits = [y for y in range(int(bot) - 12, int(bot) + 1) if rule[y]]
        if hits:
            bot = min(hits) - 2
        out[i] = [round(top, 1), round(bot, 1)]
    return out


def measure_lines(p, ys):
    """حدود النص الأفقية لكل سطر من صورة الصفحة (بإحداثيات الصورة)."""
    try:
        from PIL import Image
        import numpy as np
    except ImportError:
        return {}
    f = os.path.join(PAGES, f'p{p:03d}.jpg')
    if not os.path.exists(f):
        return {}
    a = np.asarray(Image.open(f).convert('RGB')).astype(int)
    mx, mn = a.max(2), a.min(2)
    ink = (mx < 120) & ((mx - mn) < 40)      # حبر أسود (بلا زخارف ملوّنة)
    res = {}
    for ln, (cy, half, xa, xb) in ys.items():
        band = ink[int(cy - half):int(cy + half), xa:xb]
        cols = np.where(band.sum(0) > 0)[0]
        if len(cols):
            res[ln] = [int(cols.min() + xa), int(cols.max() + xa)]
    return res


def measure_oval(p):
    """الصفحتان ١ و٢: {سطر: ([حبر x0, x1], [غطاء x0, x1])} من داخل البيضاوي الأبيض."""
    from PIL import Image
    import numpy as np
    from collections import deque
    a = np.asarray(Image.open(os.path.join(PAGES, f'p{p:03d}.jpg')).convert('RGB')).astype(int)
    mn, mx = a.min(2), a.max(2)
    paper = mn > 228
    H, W = paper.shape
    seen = np.zeros((H, W), bool)
    sy, sx = 440, 421
    while not paper[sy, sx]:
        sy += 1
    q = deque([(sy, sx)])
    seen[sy, sx] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and not seen[ny, nx] and paper[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    out = {}
    for ln in range(2, 9):
        cy = int(413 + 52.8 * (ln - 2))
        rows = [r for r in seen[cy - 24:cy + 24] if r.any()]
        L = max(int(np.where(r)[0].min()) for r in rows)
        R = min(int(np.where(r)[0].max()) for r in rows)
        inkm = (mx < 120) | ((mx - mn) > 45)
        cols = np.where(inkm[cy - 24:cy + 24, L + 2:R - 1].sum(0) > 0)[0] + L + 2
        if len(cols):
            out[ln] = ([int(cols.min()), int(cols.max())], [L + 1, R - 1])
    return out


def detect_shifted_headers(pages):
    """أزواج (P, P+1): البيانات تضع ترويسة في السطر ١٥ من P والصورة تضعها في السطر ١ من P+1."""
    from PIL import Image
    import numpy as np

    def img_headers(p):
        a = np.asarray(Image.open(os.path.join(PAGES, f'p{p:03d}.jpg')).convert('RGB')).astype(int)
        sat = (a.max(2) - a.min(2)) > 40
        out = []
        for i in range(15):
            band = sat[int(INNER[1] + i * LINE_H):int(INNER[1] + (i + 1) * LINE_H), 70:736]
            out.append(band.mean() > 0.08)        # الترويسة مساحة ملوّنة كبيرة
        return out

    res, bad = [], []
    for p in range(3, 604):
        L = pages[p - 1]['l']
        dh = [ln['t'] == 'h' for ln in L]
        ih = img_headers(p)
        if dh == ih:
            continue
        if dh[14] and not ih[14] and img_headers(p + 1)[0] and not any(x['t'] == 'h' for x in pages[p]['l']):
            res.append((p, p + 1))
        elif not (p - 1, p) in res:
            bad.append(p)
    if bad:
        print('⚠ صفحات تختلف ترويساتها عن الصور ولم تُعالج:', bad)
    return res


def main():
    os.makedirs(RAW, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    missing = [p for p in range(1, 605) if not os.path.exists(os.path.join(RAW, f'{p}.json'))]
    if missing:
        print(f'→ تنزيل {len(missing)} صفحة من بيانات QPC V2 ...', flush=True)
        with concurrent.futures.ThreadPoolExecutor(3) as ex:
            list(ex.map(fetch, missing))

    ref = json.load(open(REF, encoding='utf-8'))
    T = {(a['s'], a['a']): a['w'] for a in ref['ayahs']}

    # كل الكلمات مجمّعة حسب (صفحة V2، سطر)
    lines = {}
    qwords = {}
    for p in range(1, 605):
        d = json.load(open(os.path.join(RAW, f'{p}.json'), encoding='utf-8'))
        for v in d['verses']:
            s, a = map(int, v['verse_key'].split(':'))
            for w in v['words']:
                key = (w['v2_page'], w['line_v2'])
                lines.setdefault(key, []).append((s, a, w['position'], w['char_type_name'], w['code_v2'], w['text_uthmani']))
                if w['char_type_name'] == 'word':
                    qwords.setdefault((s, a), []).append(w['text_uthmani'])
    # ترتيب الكلمات داخل السطر (حسب الآية ثم الموضع) + إزالة التكرار (الصفحة نفسها قد تظهر في ردّين)
    for k in lines:
        seen, uniq = set(), []
        for t in sorted(lines[k], key=lambda x: (x[0], x[1], x[2])):
            if (t[0], t[1], t[2]) in seen:
                continue
            seen.add((t[0], t[1], t[2]))
            uniq.append(t)
        lines[k] = uniq

    maps = {k: word_map(T[k], qwords[k]) for k in T}
    merged = {k: m for k, m in maps.items() if any(a != b for a, b in m)}
    print('آيات فيها كلمة QPC مدمجة:', {f'{k[0]}:{k[1]}': [list(x) for x in m if x[0] != x[1]] for k, m in merged.items()})

    pages = []
    fixed_markers = [0]
    fixed_breaks = [0]
    bf = os.path.join(OUT, 'break-fixes.json')
    BREAK_FIXES = json.load(open(bf)) if os.path.exists(bf) else {}
    sura_first = {}
    n_words = n_ends = 0
    for p in range(1, 605):
        special = p <= 2
        out_lines = []
        present = [ln for ln in range(1, 16) if (p, ln) in lines]
        last = max(present)
        nlines = 8 if special else 15
        for ln in range(1, nlines + 1):
            ws = lines.get((p, ln))
            if not ws:
                out_lines.append(None)
                continue
            row = []
            for s, a, pos, typ, glyph, txt in ws:
                if typ == 'end':
                    row.append([glyph, s, a, 0, 0])
                    n_ends += 1
                else:
                    row.append([glyph, s, a, pos, pos])   # pos مؤقت ← يُستبدل بمدى Tilawa
                    n_words += 1
            out_lines.append({'t': 'w', 'w': row})
        # تحويل موضع QPC إلى مدى Tilawa
        for L in out_lines:
            if not L:
                continue
            for w in L['w']:
                if w[3] == 0:
                    continue
                s, a = w[1], w[2]
                # position في QPC يعدّ العلامة أيضًا؟ لا: العلامة آخر عنصر؛ الكلمات 1..n
                t0, t1 = maps[(s, a)][w[3] - 1]
                w[3], w[4] = t0, t1
        # تصحيح بيانات QPC: علامة نهاية آية في أول السطر تخص آخر السطر السابق (لا يبدأ سطر بعلامة آية
        # في مصحف المدينة؛ مؤكد بالمقارنة مع الصور)
        for i in range(1, len(out_lines)):
            L, P = out_lines[i], out_lines[i - 1]
            while L and P and L['w'] and L['w'][0][3] == 0:
                P['w'].append(L['w'].pop(0))
                fixed_markers[0] += 1
        # فواصل أسطر مصحَّحة لتطابق طبعة الصور (tools/fix_tasmee_breaks.py → data/tasmee/break-fixes.json)
        for first, counts in BREAK_FIXES.get(str(p), {}).items():
            run = list(range(int(first) - 1, int(first) - 1 + len(counts)))
            items = [w for i in run for w in out_lines[i]['w']]
            pos = 0
            for i, n in zip(run, counts):
                out_lines[i]['w'] = items[pos:pos + n]
                pos += n
            assert pos == len(items), (p, first)
            fixed_breaks[0] += 1
        # الأسطر الفارغة: ترويسة سورة + بسملة قبل أول كلمة لكل سورة تبدأ في الصفحة
        for i, L in enumerate(out_lines):
            if L:
                for w in L['w']:
                    if w[3] == 1 and w[2] == 1 and w[1] not in sura_first:
                        sura_first[w[1]] = [p, i + 1]
        for i, L in enumerate(out_lines):
            if L is not None:
                continue
            # أقرب سطر كلمات بعده
            nxt = next((j for j in range(i + 1, len(out_lines)) if out_lines[j]), None)
            s_next = out_lines[nxt]['w'][0][1] if nxt is not None else None
            gap_to = (nxt - i) if nxt is not None else None
            if s_next and gap_to == 1 and s_next not in (1, 9) and out_lines[nxt]['w'][0][2] == 1:
                out_lines[i] = {'t': 'b'}
            elif s_next and out_lines[nxt]['w'][0][2] == 1:
                out_lines[i] = {'t': 'h', 's': s_next}
            else:
                # ترويسة في آخر الصفحة لسورة تبدأ في الصفحة التالية (لا تحدث في V2 لكن للاحتياط)
                out_lines[i] = {'t': 'h', 's': (out_lines[i - 1]['w'][-1][1] + 1) if i and out_lines[i - 1] and out_lines[i - 1].get('w') else 0}
        pages.append({'l': out_lines})

    # ---------- هندسة الأسطر من الصور ----------
    # الصفحتان ١ و٢ (843×1140): النص داخل بيضاوي مزخرف؛ نُحدد داخل البيضاوي بملء من المركز عبر
    # بكسلات الورق، ثم حدود الحبر وحدود الغطاء (داخل البيضاوي) لكل سطر. مراكز الأسطر: 413 + 52.8 × (السطر − 2)
    geo_pages12 = {p: measure_oval(p) for p in (1, 2)}
    measured = 0
    for p in range(1, 605):
        L = pages[p - 1]['l']
        ys = {}
        for i, line in enumerate(L):
            if not line or line['t'] != 'w':
                continue
            if p <= 2:
                g = geo_pages12[p].get(i + 1)
                if not g:
                    raise SystemExit(f'تعذّر قياس السطر {i + 1} في الصفحة {p} (هل صورها موجودة في pages/؟)')
                line['y'] = round(413 + 52.8 * (i - 1), 1)
                line['x'], line['m'] = g
                measured += 1
                continue
            cy = INNER[1] + LINE_H * (i + 0.5)
            ys[i] = (cy, LINE_H * 0.3, INNER[0] + 3, INNER[2] - 3)
            # مركز حبر السطر في الصورة (انحدار خطي على صفحات متفرقة: خطأ ≤ ٣ بكسل)
            line['y'] = round(INK_Y0 + INK_DY * i, 1)
        if p <= 2:
            continue
        ext = measure_lines(p, ys)
        mk = measure_mask(p, list(ys.keys()))
        for i in ys:
            L[i]['mk'] = mk[i]
        for i, line in enumerate(L):
            if line and line['t'] == 'w':
                if i in ext:
                    line['x'] = ext[i]
                    measured += 1
                else:
                    line['x'] = [86, 721] if p > 2 else [250, 595]

    # ---------- صفحات تختلف فيها الطبعة المصورة عن بيانات V2 في موضع ترويسة السورة ----------
    # V2 يضع الترويسة في آخر سطر من الصفحة P، والصورة تضعها أول الصفحة P+1 (فتختلف أسطر الصفحتين).
    # هذه الصفحات تُرسم كاملة من البيانات ("own"): غطاء أبيض على كل المساحة الداخلية، والترويسة/البسملة
    # صورة مقتطعة من سطرها في الصورة الأصلية (src = [صفحة، سطر]).
    own = detect_shifted_headers(pages)
    for p, nxt in own:
        P, N = pages[p - 1], pages[nxt - 1]
        P['own'] = True
        N['own'] = True
        for i, line in enumerate(P['l']):
            if line['t'] == 'h':
                line['src'] = [nxt, 1]
        for i, line in enumerate(N['l']):
            if line['t'] == 'b':
                line['src'] = [nxt, 2]
        for pg in (P, N):
            for line in pg['l']:
                if line['t'] == 'w':
                    line['x'] = [86, 721]
                    line.pop('m', None)
    print(f'فواصل أسطر مصحّحة: {fixed_breaks[0]}')
    print(f'علامات آيات نُقلت لآخر السطر السابق: {fixed_markers[0]}، صفحات مرسومة كاملة (ترويسة منقولة): {[x for pr in own for x in pr]}')

    data = {
        'v': 1,
        'src': 'QPC V2 layout (Quran.com API / QUL) + Tilawa ref-v2 (Tanzil Uthmani)',
        'geo': {'w': 807, 'h': 1205, 'inner': INNER, 'lineH': LINE_H,
                'w12': 843, 'h12': 1140, 'lineH12': 55},
        'pages': pages,
        'suraFirst': {str(k): v for k, v in sorted(sura_first.items())},
    }
    path = os.path.join(OUT, 'layout.json')
    json.dump(data, open(path, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print(f'✓ {path}: {n_words} كلمة، {n_ends} علامة آية، أسطر مقاسة من الصور: {measured}، سور: {len(sura_first)}')
    assert n_words == 77429 and n_ends == 6236 and len(sura_first) == 114


if __name__ == '__main__':
    main()
