import QtQuick
import Quickshell
import Quickshell.Io
import "utils.js" as U

// تحميل بيانات القرآن والقوائم + دوال البحث والتحديد
Item {
    id: data

    property bool ready: false
    property var q: null      // quran.json
    property var nv: null     // nav.json
    property var pos: null    // إحداثيات الآيات على الصور
    property var suraStart: []   // فهرس أول آية لكل سورة
    property var juzG: []
    property var hizbG: []
    property var rubG: []
    property int totalAyas: 0

    FileView {
        id: qf
        path: Quickshell.shellDir + "/data/quran.json"
        watchChanges: false
        printErrors: true
        onLoaded: {
            try { data.q = JSON.parse(qf.text()); } catch (e) { console.log("quran.json parse:", e); }
            data.check();
        }
    }
    FileView {
        id: nf
        path: Quickshell.shellDir + "/data/nav.json"
        watchChanges: false
        printErrors: true
        onLoaded: {
            try { data.nv = JSON.parse(nf.text()); } catch (e) { console.log("nav.json parse:", e); }
            data.check();
        }
    }
    FileView {
        id: pf
        path: Quickshell.shellDir + "/data/ayah_positions.json"
        watchChanges: false
        onLoaded: {
            try { data.pos = JSON.parse(pf.text()); } catch (e) { console.log("positions parse:", e); }
        }
    }

    function check() {
        if (data.q === null || data.nv === null) return;
        var starts = [];
        var acc = 0;
        for (var i = 0; i < data.q.surahs.length; i++) { starts.push(acc); acc += data.q.surahs[i].ayas; }
        data.suraStart = starts;
        data.totalAyas = acc;
        function gs(it) { return data.gi(it.s, it.a); }
        data.juzG = data.nv.juz.map(function (it) { return data.gi(it.s, it.a); });
        data.hizbG = data.nv.hizb.map(function (it) { return data.gi(it.s, it.a); });
        data.rubG = data.nv.rub.map(function (it) { return data.gi(it.s, it.a); });
        data.ready = true;
        console.log("مصحفي: البيانات جاهزة —", acc, "آية");
    }

    // فهرس عام لآية (سورة، آية) — 0-based
    function gi(s, a) { return data.suraStart[s - 1] + (a - 1); }

    // السورة الحاوية لفهرس عام — ترجع 0-based
    function suraOfIdx(j) {
        var lo = 0, hi = 113;
        while (lo < hi) {
            var mid = Math.floor((lo + hi + 1) / 2);
            if (data.suraStart[mid] <= j) lo = mid; else hi = mid - 1;
        }
        return lo;
    }

    function ayaOfIndex(j) { return j - data.suraStart[data.suraOfIdx(j)] + 1; }

    // بداية الصفحة (فهرس عام) من رقم الصفحة 1..604
    function pageStartG(page) {
        var pg = data.nv.pages[page - 1];
        return data.gi(pg.s, pg.a);
    }

    // آخر عنصر بدايته <= فهرس معين (1-based نتيجة)
    function lastLE(arr, j) {
        var lo = 0, hi = arr.length - 1, res = 0;
        while (lo <= hi) {
            var mid = Math.floor((lo + hi) / 2);
            if (arr[mid] <= j) { res = mid + 1; lo = mid + 1; } else hi = mid - 1;
        }
        return res;
    }

    // معلومات موضع: رقم الصفحة → {suraName, suraI, juz, hizb, rub, rubInHizb}
    function locate(page) {
        if (!data.ready) return null;
        var j = data.pageStartG(page);
        var si = data.suraOfIdx(j);
        var rub = data.lastLE(data.rubG, j);
        var hizb = data.lastLE(data.hizbG, j);
        var juz = data.lastLE(data.juzG, j);
        return {
            suraName: data.q.surahs[si].name,
            suraI: si + 1,
            juz: juz, hizb: hizb, rub: rub,
            rubInHizb: rub - (hizb - 1) * 4
        };
    }

    // هل الصفحة بداية سورة؟ (اسم السورة يظهر في الصفحة)
    function surasOnPage(page) {
        var out = [];
        if (!data.ready) return out;
        var j0 = data.pageStartG(page);
        var j1 = (page < 604) ? data.pageStartG(page + 1) : data.totalAyas;
        for (var i = 0; i < 114; i++) {
            var st = data.suraStart[i];
            if (st >= j0 && st < j1) out.push(i + 1);
        }
        return out;
    }

    // ---------------- البحث ----------------
    // يرجع: [{kind:"sura", i, name, page} , {kind:"aya", gi, s, sName, a, page, text}]
    function search(query, limit) {
        if (!data.ready || !query) return [];
        limit = limit || 150;
        var nq = U.normAr(query);
        if (nq.length === 0) return [];
        var res = [];
        // ١) أسماء السور
        if (nq.length >= 2) {
            for (var i = 0; i < 114; i++) {
                var nm = U.normAr(data.q.surahs[i].name);
                if (nm.indexOf(nq) !== -1) {
                    res.push({ kind: "sura", i: i + 1, name: data.q.surahs[i].name, page: data.q.surahs[i].p });
                }
            }
        }
        // ٢) بحث نصي (كل الكلمات موجودة كسلاسل فرعية — يشمل الحرف والكلمة)
        var toks = nq.split(" ").filter(function (t) { return t.length > 0; });
        var norm = data.q.norm;
        var found = 0;
        for (var j = 0; j < norm.length && found < limit; j++) {
            var t = norm[j];
            var ok = true;
            for (var k = 0; k < toks.length; k++) {
                if (t.indexOf(toks[k]) === -1) { ok = false; break; }
            }
            if (ok) {
                var si = data.suraOfIdx(j);
                res.push({ kind: "aya", gi: j, s: si + 1, sName: data.q.surahs[si].name,
                           a: data.ayaOfIndex(j), page: data.q.page[j], text: data.q.text[j] });
                found++;
            }
        }
        return res;
    }

    // إحداثيات الآية على صورتها (بمقياس الصورة الأصلية)
    function posOfAya(s, a) {
        if (!data.pos || !data.ready) return null;
        var j = data.gi(s, a);
        if (j < 0 || j >= data.pos.x.length) return null;
        return { x: data.pos.x[j], y: data.pos.y[j], w: data.pos.w, h: data.pos.h };
    }

    // رقم صفحة لآية
    function pageOfAya(s, a) { return data.q.page[data.gi(s, a)]; }
}
