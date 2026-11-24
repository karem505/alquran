#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""امتداد كل آية على صور الصفحات (لتظليل علامة «آخر تسميع» في وضع القراءة بالصور).

لكل صفحة صورة: نكتشف الأسطر النصية (بالحبر) وترويسات السور (بالتشبّع اللوني) وأوسمة الآيات (البنفسجي)،
ثم نمشي على آيات الصفحة بترتيب القراءة (ترتيبها وأين تنتهي من data/tasmee/layout.json):
كل آية تمتد من موضع المؤشر حتى يسار وسامها؛ والآية الممتدة للصفحة التالية حتى آخر السطر الأخير.
لا نعتمد على توزيع الكلمات على الأسطر في البيانات (يختلف عن الصورة في صفحات قليلة).

المخرج: data/tasmee/ayah-bands.json  {"s:a": [[صفحة, x0, y0, x1, y1], ...]}  بإحداثيات الصورة الأصلية.
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INK_Y0, INK_DY = 113.3, 70.37
LH = (1140 - 64) / 15.0
MED_HALF = 18          # نصف عرض الوسام


def img(p):
    return np.asarray(Image.open(os.path.join(ROOT, 'pages', f'p{p:03d}.jpg')).convert('RGB')).astype(int)


def page_lines(a):
    """لكل سطر من ١٥: ('h' ترويسة | 't' نص | '.' فارغ، امتداد الحبر [xl, xr])."""
    sat = (a.max(2) - a.min(2)) > 40
    ink = a.max(2) < 110
    out = []
    for i in range(15):
        y0, y1 = int(64 + i * LH), int(64 + (i + 1) * LH)
        frac = sat[y0:y1, 70:736].mean()
        if frac > 0.08:
            out.append(('h', None))
            continue
        cy = INK_Y0 + INK_DY * i
        band = ink[int(cy - 26):int(cy + 22), 70:738]
        cols = np.where(band.sum(0) >= 2)[0]
        if len(cols) < 20:
            out.append(('.', None))
        else:
            out.append(('t', [int(cols[0]) + 70, int(cols[-1]) + 70]))
    return out


def medallions(a, kinds):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    purple = (b - g > 35) & (r - g > 15) & (b > r)
    purple[:, :66] = False
    purple[:, 741:] = False
    res = []
    for i in range(15):
        if kinds[i][0] != 't':
            res.append([])
            continue
        y0 = int(INK_Y0 + INK_DY * i - INK_DY / 2)
        y1 = int(INK_Y0 + INK_DY * i + INK_DY / 2)
        cols = np.where(purple[y0:y1].sum(0) > 0)[0]
        runs = []
        for c in cols:
            if runs and c - runs[-1][1] <= 22:
                runs[-1][1] = c
            else:
                runs.append([c, c])
        res.append(sorted([(c0 + c1) / 2 for c0, c1 in runs if c1 - c0 >= 5 and purple[y0:y1, c0:c1 + 1].sum() >= 20],
                          reverse=True))
    return res


def main():
    lay = json.load(open(os.path.join(ROOT, 'data', 'tasmee', 'layout.json'), encoding='utf-8'))
    bands, bad = {}, []
    for p in range(3, 605):
        pg = lay['pages'][p - 1]
        # آيات الصفحة بالترتيب، وهل تنتهي فيها، وهل تبدأ فيها (لبدايات السور)
        order, ends, starts = [], set(), set()
        for l in pg['l']:
            if not l or l['t'] != 'w':
                continue
            for w in l['w']:
                k = (w[1], w[2])
                if not order or order[-1] != k:
                    if k not in order:
                        order.append(k)
                if w[3] == 0:
                    ends.add(k)
                if w[3] == 1:
                    starts.add(k)
        a = img(p)
        kinds = page_lines(a)
        med = medallions(a, kinds)
        nmed = sum(len(m) for m in med)
        # ترويسات السور في الصورة بالترتيب ↔ السور التي تبدأ في الصفحة
        heads = [i for i, k in enumerate(kinds) if k[0] == 'h']
        new_suras = [k for k in order if k[1] == 1 and k in starts]
        if nmed != len(ends) or len(heads) != len(new_suras):
            bad.append((p, nmed, len(ends), len(heads), len(new_suras)))
        text_lines = [i for i, k in enumerate(kinds) if k[0] == 't']
        # بعد كل ترويسة: سطر البسملة (عدا التوبة) ليس جزءًا من الآيات
        skip = set()
        for h, (s, _) in zip(heads, new_suras):
            if s != 9 and s != 1 and h + 1 < 15:
                skip.add(h + 1)
        text_lines = [i for i in text_lines if i not in skip]
        meds = [(i, x) for i in range(15) for x in med[i] if i in text_lines]
        mi = 0
        cur = text_lines[0] if text_lines else 0
        cx = kinds[cur][1][1] if text_lines else 721
        hi = 0
        for k in order:
            if k[1] == 1 and k in starts and k in new_suras:
                # أول سطر نصي بعد ترويسة هذه السورة (وبسملتها)
                idx = new_suras.index(k)
                if idx < len(heads):
                    after = [i for i in text_lines if i > heads[idx]]
                    if after:
                        cur = after[0]
                        cx = kinds[cur][1][1]
            segs = []
            if k in ends and mi < len(meds):
                ml, mx = meds[mi]
                mi += 1
                for ln in [i for i in text_lines if cur <= i <= ml]:
                    xr = cx if ln == cur else kinds[ln][1][1]
                    xl = mx - MED_HALF if ln == ml else kinds[ln][1][0]
                    if xr - xl > 4:
                        segs.append((ln, xl, xr))
                cur, cx = ml, mx - MED_HALF - 1
                if cx - kinds[cur][1][0] < 10:
                    nxt = [i for i in text_lines if i > cur]
                    if nxt:
                        cur = nxt[0]
                        cx = kinds[cur][1][1]
            else:
                for ln in [i for i in text_lines if i >= cur]:
                    xr = cx if ln == cur else kinds[ln][1][1]
                    segs.append((ln, kinds[ln][1][0], xr))
            key = f'{k[0]}:{k[1]}'
            for ln, xl, xr in segs:
                cy = INK_Y0 + INK_DY * ln
                bands.setdefault(key, []).append([p, int(xl), int(cy - 31), int(xr), int(cy + 33)])
    # الصفحتان ١ و٢ (داخل البيضاوي): من بيانات التخطيط مباشرة (مطابقة للصورة)
    for p in (1, 2):
        pg = lay['pages'][p - 1]
        for l in pg['l']:
            if not l or l['t'] != 'w':
                continue
            n = len(l['w'])
            x0, x1 = l['x']
            seen = {}
            for j, w in enumerate(l['w']):
                seen.setdefault((w[1], w[2]), []).append(j)
            for (s, aa), js in seen.items():
                # تقدير خطي داخل السطر بعدد الرموز (السطر قصير)
                r = x1 - (x1 - x0) * js[0] / n
                lft = x1 - (x1 - x0) * (js[-1] + 1) / n
                bands.setdefault(f'{s}:{aa}', []).append([p, int(lft), int(l['y'] - 24), int(r), int(l['y'] + 26)])
    out = os.path.join(ROOT, 'data', 'tasmee', 'ayah-bands.json')
    json.dump(bands, open(out, 'w'), separators=(',', ':'))
    print(f'✓ {out}: {len(bands)} آية، {os.path.getsize(out) // 1024} ك.ب')
    print(f'صفحات بعدم تطابق (أوسمة/ترويسات): {len(bad)}', bad[:30])


if __name__ == '__main__':
    main()
