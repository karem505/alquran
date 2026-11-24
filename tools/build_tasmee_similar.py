#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""جدول المتشابهات اللفظية لوضع التسميع.

لكل آية: أقرب الآيات لها لفظًا في القرآن كله (مقاطع مشتركة طويلة) — تُعرض في اللوحة الجانبية
وتُستخدم في كشف «الانتقال إلى متشابه» أثناء التسميع.

المدخل: مرجع Tilawa (نص Tanzil العثماني، نفس ترقيم كلمات المحرك).
المخرج: data/tasmee/similar.json  {"s:a": [["s:a", score, run], ...]}
  score: نسبة التشابه (difflib على مستوى الكلمات المطبّعة)، run: أطول مقطع متطابق بالكلمات.
"""
import json, os, re, difflib
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, 'engine', 'node_modules', '@tilawa', 'core', 'assets', 'ref-v2.json')
OUT = os.path.join(ROOT, 'data', 'tasmee', 'similar.json')

HARAKAT = re.compile(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u0640\u200E\u200F\uFEFF]')


def norm(w):
    w = HARAKAT.sub('', w)
    w = re.sub('[أإآٱ]', 'ا', w)
    return w.replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي').replace('ء', '')


def main():
    ref = json.load(open(REF, encoding='utf-8'))
    ay = [((a['s'], a['a']), [norm(w) for w in a['w']]) for a in ref['ayahs']]
    N = 3
    idx = defaultdict(set)
    for i, (_, ws) in enumerate(ay):
        for j in range(len(ws) - N + 1):
            idx[tuple(ws[j:j + N])].add(i)
    out = {}
    pairs = 0
    for i, (k, ws) in enumerate(ay):
        if len(ws) < 4:
            continue
        cand = defaultdict(int)
        for j in range(len(ws) - N + 1):
            g = idx[tuple(ws[j:j + N])]
            if len(g) > 60:          # عبارات شائعة جدًا (إن الله على كل شيء قدير...) لا تكفي وحدها
                continue
            for o in g:
                if o != i:
                    cand[o] += 1
        res = []
        for o, c in cand.items():
            ws2 = ay[o][1]
            if len(ws2) < 4:
                continue
            sm = difflib.SequenceMatcher(None, ws, ws2, autojunk=False)
            ratio = sm.ratio()
            run = max((b.size for b in sm.get_matching_blocks()), default=0)
            if ratio >= 0.55 or run >= 6:
                res.append((o, round(ratio, 3), run))
        res.sort(key=lambda t: (-t[1], -t[2]))
        if res:
            out[f'{k[0]}:{k[1]}'] = [[f'{ay[o][0][0]}:{ay[o][0][1]}', r, n] for o, r, n in res[:5]]
            pairs += len(res[:5])
    json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
    print(f'✓ {OUT}: {len(out)} آية لها متشابهات ({pairs} زوج)')
    for k in ('2:35', '2:58', '7:19', '2:5', '55:13', '6:151'):
        print(' ', k, out.get(k))


if __name__ == '__main__':
    main()
