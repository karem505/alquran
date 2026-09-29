#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""بناء فهارس تطبيق مصحفي.

المدخلات (data/raw/):
  - tanzil_uthmani.txt          نص عثماني: سورة|آية|نص
  - quran-data.xml              قوائم: سور/أجزاء/أرباع(quarters)/صفحات (tanzil)
  - alquran_uthmani_meta.json   صفحة/ربع/جزء لكل آية (alquran.cloud)

المخرجات (data/):
  - quran.json   نص + مؤشر مطبّع + صفحة/ربع/جزء لكل آية + بيانات السور
  - nav.json     الأجزاء(30) والأحزاب(60) والأرباع(240) وبدايات الصفحات(604)
"""
import json, re, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'data', 'raw')
OUT = os.path.join(ROOT, 'data')

HARAKAT = re.compile(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\uFEFF\u200F\u200E]')

def norm(s: str) -> str:
    s = HARAKAT.sub('', s)
    s = s.replace('\u0640', '')          # تطويل
    s = re.sub(r'[أإآٱ]', 'ا', s)        # ألف بكل صورها
    s = s.replace('ى', 'ي').replace('ة', 'ه')
    s = s.replace('ؤ', 'و').replace('ئ', 'ي').replace('ء', '')
    s = s.replace('\u06DD', ' ')         # علامة نهاية الآية
    s = re.sub(r'\s+', ' ', s).strip()
    return s

def main():
    # ---------- 1) النص ----------
    ayas = []  # (sura, aya, text)
    for line in open(os.path.join(RAW, 'tanzil_uthmani.txt'), encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        s, a, t = line.split('|', 2)
        ayas.append((int(s), int(a), t))
    assert len(ayas) == 6236, f'عدد الآيات غير متوقع: {len(ayas)}'

    # ---------- 2) بيانات السور والقوائم ----------
    xml = open(os.path.join(RAW, 'quran-data.xml'), encoding='utf-8').read()
    suras = []
    for m in re.finditer(r'<sura index="(\d+)" ayas="(\d+)" start="(\d+)" name="([^"]+)"[^>]*type="([^"]+)"', xml):
        suras.append({'i': int(m.group(1)), 'ayas': int(m.group(2)),
                      'name': m.group(4), 'type': m.group(5)})
    assert len(suras) == 114, len(suras)

    juzs = [{'i': int(m.group(1)), 's': int(m.group(2)), 'a': int(m.group(3))}
            for m in re.finditer(r'<juz index="(\d+)" sura="(\d+)" aya="(\d+)"\s*/>', xml)]
    quarters = [{'i': int(m.group(1)), 's': int(m.group(2)), 'a': int(m.group(3))}
                for m in re.finditer(r'<quarter index="(\d+)" sura="(\d+)" aya="(\d+)"\s*/>', xml)]
    assert len(juzs) == 30 and len(quarters) == 240, (len(juzs), len(quarters))
    hizbs = [dict(quarters[k * 4], i=k + 1) for k in range(60)]

    # ---------- 3) خريطة عامة: (سورة،آية) -> فهرس ----------
    offset = {}
    gi = 0
    for su in suras:
        offset[su['i']] = gi
        gi += su['ayas']

    def gidx(s, a):
        return offset[s] + (a - 1)

    # ---------- 4) صفحة/ربع/جزء لكل آية من alquran.cloud (ترقيم المصحف المعتمد) ----------
    meta = json.load(open(os.path.join(RAW, 'alquran_uthmani_meta.json'), encoding='utf-8'))
    page_of = [0] * 6236
    rub_of = [0] * 6236
    juz_of = [0] * 6236
    for su in meta['data']['surahs']:
        s = su['number']
        for a in su['ayahs']:
            j = gidx(s, a['numberInSurah'])
            page_of[j] = a['page']
            rub_of[j] = a['hizbQuarter']
            juz_of[j] = a['juz']
    assert all(1 <= p <= 604 for p in page_of), 'ترقيم صفحات غير صالح'

    # بدايات الصفحات من الترقيم المعتمد
    pages = []
    last = 0
    for j in range(6236):
        if page_of[j] != last:
            last = page_of[j]
            pages.append({'s': ayas[j][0], 'a': ayas[j][1], 'i': page_of[j]})
    print('عدد الصفحات:', len(pages))
    assert len(pages) == 604, len(pages)

    # أرباع: من بيانات tanzil + تحقق مقابل alquran.cloud
    rubs = []
    bad = 0
    for qt in quarters:
        j = gidx(qt['s'], qt['a'])
        if rub_of[j] != qt['i']:
            bad += 1
        rubs.append({'i': qt['i'], 's': qt['s'], 'a': qt['a'], 'p': page_of[j]})
    print('تحقق الأرباع: عدد الاختلافات =', bad, '(المتوقع 0)')
    assert len(rubs) == 240, len(rubs)
    for d in (juzs, hizbs):
        for it in d:
            it['p'] = page_of[gidx(it['s'], it['a'])]

    # ---------- 5) الكتابة ----------
    quran = {
        'surahs': [{'i': s['i'], 'name': s['name'], 'ayas': s['ayas'], 'type': s['type'],
                    'p': page_of[offset[s['i']]]} for s in suras],
        'text': [t for _, _, t in ayas],
        'norm': [norm(t) for _, _, t in ayas],
        'page': page_of,
        'rub': rub_of,
        'juz': juz_of,
    }
    nav = {'juz': juzs, 'hizb': hizbs, 'rub': rubs, 'pages': pages}
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'quran.json'), 'w', encoding='utf-8') as f:
        json.dump(quran, f, ensure_ascii=False, separators=(',', ':'))
    with open(os.path.join(OUT, 'nav.json'), 'w', encoding='utf-8') as f:
        json.dump(nav, f, ensure_ascii=False, separators=(',', ':'))
    print('quran.json:', os.path.getsize(os.path.join(OUT, 'quran.json')) // 1024, 'KB')
    print('nav.json:', os.path.getsize(os.path.join(OUT, 'nav.json')) // 1024, 'KB')
    # فحوصات نهائية
    print('1:1 صفحة:', page_of[gidx(1, 1)], '| 2:1 صفحة:', page_of[gidx(2, 1)],
          '| 2:255 صفحة:', page_of[gidx(2, 255)], '| 114:6 صفحة:', page_of[gidx(114, 6)])

if __name__ == '__main__':
    main()
