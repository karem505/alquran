#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""تصحيح فواصل الأسطر: بعض أسطر تخطيط QPC V2 تختلف عن طبعة الصور (كلمة تنتقل لسطر مجاور)،
فيظهر سطر مضغوط وجاره مفرود. نعيد توزيع الكلمات بين الأسطر المتجاورة بحيث:
  - يطابق عدد علامات الآيات في كل سطر عدد الأوسمة المكتشفة في السطر نفسه من الصورة (إن وُجدت)،
  - ويقترب امتداد الحبر الطبيعي لكل سطر (بخط الصفحة) من امتداده في الصورة.
المدخلات: data/tasmee/layout.json + قياسات الرموز (tools/qpc-measure.qml → tmp/tasmee/widths.log) + صور pages/.
المخرج: data/tasmee/break-fixes.json  {"<page>": {"<firstLine>": [عدد الرموز لكل سطر في المقطع ...]}}
يطبّقه tools/build_tasmee_layout.py عند البناء.
"""
import json, os, sys, statistics
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
INNER = (63, 64, 743, 1140)
LH = (INNER[3] - INNER[1]) / 15.0
INK_Y0, INK_DY = 113.3, 70.37


def medallion_centers(p):
    """مراكز أوسمة الآيات (x) في كل سطر من الصورة، من اليمين لليسار (كتل بنفسجية؛ البتلتان = وسام واحد)."""
    a = np.asarray(Image.open(os.path.join(ROOT, 'pages', f'p{p:03d}.jpg')).convert('RGB')).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    purple = (b - g > 35) & (r - g > 15) & (b > r)
    purple[:, :66] = False
    purple[:, 741:] = False
    counts = [[] for _ in range(15)]
    for i in range(15):
        y0 = int(INK_Y0 + INK_DY * i - INK_DY / 2)
        y1 = int(INK_Y0 + INK_DY * i + INK_DY / 2)
        cols = np.where(purple[y0:y1].sum(0) > 0)[0]
        runs = []
        for c in cols:
            if runs and c - runs[-1][1] <= 22:
                runs[-1][1] = c
            else:
                runs.append([c, c])
        counts[i] = sorted([(c0 + c1) / 2 for c0, c1 in runs if c1 - c0 >= 5 and purple[y0:y1, c0:c1 + 1].sum() >= 20],
                           reverse=True)
    return counts


def span(items, k):
    """امتداد الحبر الطبيعي لسطر مرصوص بعرض التقدّم من اليمين (نفس منطق TasmeePage)."""
    o, L, R = 0.0, [], []
    for adv, rx, rw in items:
        o -= adv * k
        L.append(o + rx * k)
        R.append(o + (rx + rw) * k)
    return R[0] - L[-1]


def main():
    lay = json.load(open(os.path.join(ROOT, 'data', 'tasmee', 'layout.json'), encoding='utf-8'))
    W = {}
    for line in open(os.path.join(ROOT, 'tmp', 'tasmee', 'widths.log'), encoding='utf-8'):
        _, _, p, js = line.strip().split(' ', 3)
        W[int(p)] = json.loads(js)
    fixes, report = {}, []
    for p in range(3, 605):
        pg = lay['pages'][p - 1]
        if pg.get('own'):
            continue
        idx = [i for i, l in enumerate(pg['l']) if l['t'] == 'w']
        ws = {i: W[p][i] for i in idx}
        ks = [(pg['l'][i]['x'][1] - pg['l'][i]['x'][0]) / sum(w[0] for w in ws[i]) for i in idx
              if pg['l'][i]['x'][1] - pg['l'][i]['x'][0] > 600 and len(ws[i]) > 2]
        if not ks:
            continue
        K = statistics.median(ks)
        med = None
        medx = None
        runs, cur = [], []
        for i in idx:
            if cur and i != cur[-1] + 1:
                runs.append(cur)
                cur = []
            cur.append(i)
        if cur:
            runs.append(cur)
        for run in runs:
            if len(run) < 2:
                continue
            seq = [(w, it) for i in run for w, it in zip(ws[i], pg['l'][i]['w'])]
            E = [pg['l'][i]['x'][1] - pg['l'][i]['x'][0] for i in run]
            orig = [len(pg['l'][i]['w']) for i in run]

            def devs(counts):
                pos, out = 0, []
                for n, e in zip(counts, E):
                    part = seq[pos:pos + n]
                    pos += n
                    if n < 1 or part[0][1][3] == 0:      # لا يبدأ سطر بعلامة آية
                        return None
                    out.append(e / span([w for w, _ in part], K) - 1)
                return out

            def ends(counts):
                pos, out = 0, []
                for n in counts:
                    out.append(sum(1 for _, it in seq[pos:pos + n] if it[3] == 0))
                    pos += n
                return out

            def pos_cost(part, j):
                """انحراف مواضع الأوسمة المتوقعة عن مواضعها في الصورة (بعد مدّ السطر ليطابق امتداده)."""
                xs = medx[run[j]]
                ends_at, o = [], 0.0
                for (adv, rx, rw), it in part:
                    if it[3] == 0:
                        ends_at.append(o + adv * K / 2)
                    o += adv * K
                if len(ends_at) != len(xs) or o <= 0:
                    return 0.0
                x1 = pg['l'][run[j]]['x'][1]
                e = E[j]
                return sum(((x1 - a / o * e) - x) ** 2 for a, x in zip(ends_at, xs)) / (e * e)

            d0 = devs(orig)
            if d0 is None:
                continue
            if med is None:
                medx = medallion_centers(p)
                med = [len(x) for x in medx]
            def orig_pos():
                pos, tot = 0, 0.0
                for j, n in enumerate(orig):
                    tot = max(tot, pos_cost(seq[pos:pos + n], j))
                    pos += n
                return tot
            if max(abs(x) for x in d0) < 0.05 and ends(orig) == [med[i] for i in run] and orig_pos() < 0.03 ** 2:
                continue

            def cost(counts):
                d = devs(counts)
                if d is None:
                    return None, None
                c = sum(x * x for x in d)
                # عدد الأوسمة: عقوبة كبيرة لعدم التطابق مع الصورة
                c += 0.05 * sum(abs(a - med[i]) for a, i in zip(ends(counts), run))
                return c, d

            # برمجة ديناميكية على كل فواصل المقطع (قد ينزاح أكثر من سطر متتالٍ بكلمة)
            N, M = len(seq), len(run)
            INF = float('inf')
            lim = 4                                   # أقصى انزياح لأي فاصل عن موضعه الأصلي (رموز)
            ob = [sum(orig[:j]) for j in range(M + 1)]
            dp = [dict() for _ in range(M + 1)]
            dp[0][0] = (0.0, None)
            for j in range(M):
                for st, (c0, _) in dp[j].items():
                    lo = max(st + 1, ob[j + 1] - lim) if j < M - 1 else N
                    hi = min(N - (M - j - 1), ob[j + 1] + lim) if j < M - 1 else N
                    for en in range(lo, hi + 1):
                        part = seq[st:en]
                        if not part or part[0][1][3] == 0:
                            continue
                        d = E[j] / span([w for w, _ in part], K) - 1
                        ne = sum(1 for _, it in part if it[3] == 0)
                        c = c0 + d * d + 0.05 * abs(ne - med[run[j]]) + 20 * pos_cost(part, j)
                        if en not in dp[j + 1] or c < dp[j + 1][en][0]:
                            dp[j + 1][en] = (c, st)
            if N not in dp[M]:
                continue
            cnt, en = [], N
            for j in range(M, 0, -1):
                st = dp[j][en][1]
                cnt.append(en - st)
                en = st
            cnt.reverse()
            best = (dp[M][N][0], cnt)
            if best[1] != orig:
                d1 = devs(best[1])
                mr = [med[i] for i in run]
                # عدد الأوسمة في كل سطر من الصورة هو المرجع الأقوى لمحتوى السطر: نقبل التوزيع الذي يطابقه
                # (حتى لو اتسع/ضاق السطر قليلًا لاختلاف عرض رموز الخط عن الطبعة)، بشرط اتساق المجموع
                by_med = (ends(best[1]) == mr and ends(orig) != mr and sum(mr) == sum(ends(orig))
                          and max(abs(x) for x in d1) < 0.2)
                by_fit = (max(abs(x) for x in d1) < max(abs(x) for x in d0) * 0.6 and ends(best[1]) == mr) \
                    or max(abs(x) for x in d1) < 0.04
                def tot_pos(counts):
                    pos, tot = 0, 0.0
                    for j, n in enumerate(counts):
                        tot += pos_cost(seq[pos:pos + n], j)
                        pos += n
                    return tot
                by_pos = (ends(best[1]) == mr and tot_pos(best[1]) < tot_pos(orig) * 0.3
                          and max(abs(x) for x in d1) < 0.2)
                if by_med or by_fit or by_pos:
                    fixes.setdefault(str(p), {})[str(run[0] + 1)] = best[1]
                    report.append((p, run[0] + 1, [round(x, 3) for x in d0 if abs(x) >= 0.05], round(max(abs(x) for x in d1), 3)))
    out = os.path.join(ROOT, 'data', 'tasmee', 'break-fixes.json')
    json.dump(fixes, open(out, 'w'), separators=(',', ':'))
    print(f'✓ {out}: {sum(len(v) for v in fixes.values())} مقطع في {len(fixes)} صفحة')
    for r in report[:40]:
        print(' ', r)


if __name__ == '__main__':
    main()
