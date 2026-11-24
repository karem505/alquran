import QtQuick
import Quickshell
import Quickshell.Io
import "theme.js" as T
import "utils.js" as U

// وضع التسميع: الصفحتان مرندرتان كلمةً كلمة + لوحة جانبية (التحكم، الموضع، المتشابهات، الأخطاء، الملخص)
Item {
    id: tv

    property var engine: null          // TasmeeEngine
    property var qdata: null           // Data
    property int rightPage: 1
    property string pagesDir: ""
    property string fontsDir: ""
    readonly property int leftPage: rightPage + 1

    signal jump(int page)
    signal exitRequested()

    // ---------- بيانات التخطيط ----------
    property var layout: null
    FileView {
        id: layFile
        path: Quickshell.shellDir + "/data/tasmee/layout.json"
        watchChanges: false
        onLoaded: {
            try {
                var L = JSON.parse(layFile.text());
                // صفحة (طبعة V2، مطابقة للصور) لكل آية
                var ap = {};
                for (var p = 0; p < L.pages.length; p++) {
                    var ls = L.pages[p].l;
                    for (var i = 0; i < ls.length; i++) {
                        if (!ls[i] || ls[i].t !== "w") continue;
                        for (var j = 0; j < ls[i].w.length; j++) {
                            var k = ls[i].w[j][1] + ":" + ls[i].w[j][2];
                            if (ap[k] === undefined) ap[k] = p + 1;
                        }
                    }
                }
                tv.ayahPage = ap;
                tv.layout = L;
            } catch (e) { console.log("layout parse:", e); }
        }
    }
    property var ayahPage: ({})
    function pageOf(s, a) { var p = tv.ayahPage[s + ":" + a]; return p ? p : 1; }
    // سجل الجلسات (يكتبه المحرك)
    property var history: []
    FileView {
        id: histFile
        path: Quickshell.stateDir + "/tasmee-history.json"
        watchChanges: true
        printErrors: false
        onLoaded: { try { tv.history = JSON.parse(histFile.text()); } catch (e) { tv.history = []; } }
        onFileChanged: reload()
    }

    // ---------- حالة الجلسة ----------
    property var marks: ({})
    property int marksRev: 0
    property var readSet: ({})
    property string current: ""
    property bool hideUnread: false
    property var mistakes: []          // [{id, cls, loc, text, sura, page}]
    property var sims: []              // أحداث sim (الأحدث أولًا)
    property var near: null            // متشابهات الآية الحالية
    property var summary: null
    property var pos: null             // {st, w, exp, conf, page}
    property string mode: "free"       // free | page | spread | range | sura | rub | hizb
    property int rangeSura: 1
    property int rangeFrom: 1
    property int rangeTo: 7
    property string message: ""
    property var lastLockedKey: null
    property var pendingSkip: null
    property bool showOriginal: false
    property int tab: 0                // 0 الجلسة، 1 السجل

    readonly property bool active: engine ? engine.sessionActive : false

    function key(s, a, w) { return s + ":" + a + ":" + w; }
    function suraName(s) { return (qdata && qdata.ready) ? qdata.q.surahs[s - 1].name : ""; }
    function ayaCount(s) { return (qdata && qdata.ready) ? qdata.q.surahs[s - 1].ayas : 0; }
    function clsName(c) {
        return c === "wrong_word" ? "كلمة خطأ" : c === "omitted_word" ? "كلمة ناقصة"
             : c === "added_word" ? "كلمة زائدة" : c === "skipped_passage" ? "مقطع متخطّى" : c;
    }
    function clsColor(c) {
        return c === "wrong_word" ? "#b3261e" : c === "omitted_word" ? "#c2610c"
             : c === "added_word" ? "#8e3b74" : "#7b6a8f";
    }
    function clsState(c) {
        return c === "wrong_word" ? 3 : c === "omitted_word" ? 4 : c === "skipped_passage" ? 5 : 6;
    }
    property int fontsTick: 0          // يزيد بعد تنزيل خطوط جديدة لإعادة تحميلها
    function fontUrl(p) { return "file://" + encodeURI(tv.fontsDir + "/p" + p + ".woff2") + (tv.fontsTick ? "#" + tv.fontsTick : ""); }
    function imgUrl(p) {
        var n = p < 10 ? "00" + p : (p < 100 ? "0" + p : "" + p);
        return "file://" + encodeURI(tv.pagesDir) + "/p" + n + ".jpg";
    }

    // ---------- المقاطع ----------
    // كلمات صفحة: أول/آخر آية فيها
    function pageAyahRange(p) {
        if (!tv.layout) return null;
        var first = null, last = null;
        var L = tv.layout.pages[p - 1].l;
        for (var i = 0; i < L.length; i++) {
            if (!L[i] || L[i].t !== "w") continue;
            for (var j = 0; j < L[i].w.length; j++) {
                var w = L[i].w[j];
                if (first === null) first = [w[1], w[2]];
                last = [w[1], w[2]];
            }
        }
        return first ? { from: first, to: last } : null;
    }
    // من (سورة، آية) إلى (سورة، آية) → مقاطع لكل سورة
    function segs(s0, a0, s1, a1) {
        var out = [];
        for (var s = s0; s <= s1; s++) {
            var fa = (s === s0) ? a0 : 1;
            var ta = (s === s1) ? a1 : tv.ayaCount(s);
            if (ta >= fa) out.push({ surah: s, fromAyah: fa, toAyah: ta });
        }
        return out;
    }
    function gToSA(g) {
        var si = tv.qdata.suraOfIdx(g);
        return [si + 1, tv.qdata.ayaOfIndex(g)];
    }
    function divisionSegs(arrG, i) {          // i: 1-based رقم الربع/الحزب
        var g0 = arrG[i - 1];
        var g1 = (i < arrG.length) ? arrG[i] - 1 : tv.qdata.totalAyas - 1;
        var a = gToSA(g0), b = gToSA(g1);
        return tv.segs(a[0], a[1], b[0], b[1]);
    }
    function passageFor(m) {
        var loc = tv.qdata.locate(tv.rightPage);
        if (m === "page" || m === "spread") {
            var r1 = tv.pageAyahRange(tv.rightPage);
            var r2 = (m === "spread" && tv.leftPage <= 604) ? tv.pageAyahRange(tv.leftPage) : r1;
            return { segs: tv.segs(r1.from[0], r1.from[1], r2.to[0], r2.to[1]),
                     label: m === "page" ? "الصفحة " + U.ar(tv.rightPage) : "الصفحتان " + U.ar(tv.rightPage) + "–" + U.ar(tv.leftPage) };
        }
        if (m === "range") {
            var s = tv.rangeSura, n = tv.ayaCount(s);
            var f = Math.max(1, Math.min(tv.rangeFrom, n)), t = Math.max(f, Math.min(tv.rangeTo, n));
            return { segs: [{ surah: s, fromAyah: f, toAyah: t }], label: "سورة " + tv.suraName(s) + " " + U.ar(f) + "–" + U.ar(t) };
        }
        if (m === "sura") {
            var ss = tv.rangeSura;
            return { segs: [{ surah: ss, fromAyah: 1, toAyah: tv.ayaCount(ss) }], label: "سورة " + tv.suraName(ss) };
        }
        if (m === "rub") return { segs: tv.divisionSegs(tv.qdata.rubG, loc.rub), label: "الربع " + U.ar(loc.rubInHizb) + " من الحزب " + U.ar(loc.hizb) };
        if (m === "hizb") return { segs: tv.divisionSegs(tv.qdata.hizbG, loc.hizb), label: "الحزب " + U.ar(loc.hizb) };
        return null;
    }

    // ---------- بدء/إيقاف ----------
    function resetSession() {
        tv.marks = {};
        tv.readSet = {};
        tv.current = "";
        tv.mistakes = [];
        tv.sims = [];
        tv.near = null;
        tv.summary = null;
        tv.pos = null;
        tv.message = "";
        tv.lastLockedKey = null;
        tv.pendingSkip = null;
        tv.marksRev++;
    }
    // src: "mic" أو كائن ملف (للاختبار والعرض)
    property var pendingStart: null
    function startSession(src) {
        if (!tv.engine) return;
        if (!tv.engine.ready) { tv.pendingStart = src || "mic"; tv.engine.boot(); return; }
        tv.pendingStart = null;
        tv.resetSession();
        tv.tab = 0;
        var o = { mode: "free", src: src || "mic", label: "تسميع حر" };
        if (tv.mode !== "free") {
            var p = tv.passageFor(tv.mode);
            if (!p || p.segs.length === 0) { tv.message = "تعذّر تحديد المقطع"; return; }
            o.mode = "passage";
            o.passage = p.segs;
            o.label = p.label;
            // انتقل لبداية المقطع
            var pg = tv.pageOf(p.segs[0].surah, p.segs[0].fromAyah);
            if (pg < tv.rightPage || pg > tv.leftPage) tv.jump(pg);
        }
        tv.engine.start(o);
    }
    function stopSession() { if (tv.engine) tv.engine.stop(); }

    // ---------- أحداث المحرك ----------
    Connections {
        target: tv.engine
        function onEvent(e) { tv.onEngineEvent(e); }
        function onReadyChanged() { if (tv.engine.ready && tv.pendingStart !== null) tv.startSession(tv.pendingStart); }
    }

    // ترتيب الكلمات: كل كلمات Tilawa بين موضعين (في نفس الصفحة أو صفحتين متتاليتين)
    function wordsBetween(a, b) {         // a, b: [s, a, w] — حصريًا للطرفين
        var out = [], on = false;
        if (!tv.layout) return out;
        var pa = tv.pageOfWord(a), pb = tv.pageOfWord(b);
        if (pa <= 0 || pb <= 0 || pb < pa || pb - pa > 3) return out;
        for (var p = pa; p <= Math.min(604, pb + 1); p++) {
            var L = tv.layout.pages[p - 1].l;
            for (var i = 0; i < L.length; i++) {
                if (!L[i] || L[i].t !== "w") continue;
                for (var j = 0; j < L[i].w.length; j++) {
                    var w = L[i].w[j];
                    for (var t = w[3]; t <= w[4] && w[3] > 0; t++) {
                        var c = [w[1], w[2], t];
                        if (c[0] === b[0] && c[1] === b[1] && c[2] === b[2]) return out;
                        if (on) out.push(c);
                        if (c[0] === a[0] && c[1] === a[1] && c[2] === a[2]) on = true;
                    }
                }
            }
        }
        return out;
    }
    function pageOfWord(w) { return tv.pageOf(w[0], w[1]); }

    function onEngineEvent(e) {
        var m, i, k;
        if (e.ev === "started") {
            tv.message = "";
        } else if (e.ev === "pos") {
            tv.pos = e;
            var w = e.w || (e.st !== "acquiring" ? e.exp : null);
            if (e.st === "locked" && e.w) {
                k = tv.key(e.w[0], e.w[1], e.w[2]);
                m = tv.marks;
                var rs = tv.readSet;
                // كلمات بين آخر موضع وهذا الموضع في نفس الآية/التي تليها = مقروءة
                if (tv.lastLockedKey) {
                    var prev = tv.lastLockedKey;
                    var gap = tv.wordsBetween(prev, e.w);
                    if (gap.length < 25) for (i = 0; i < gap.length; i++) {
                        var gk = tv.key(gap[i][0], gap[i][1], gap[i][2]);
                        rs[gk] = true;
                        if (tv.pendingSkip && !m[gk]) m[gk] = 5;
                        else if (!m[gk]) m[gk] = 1;
                    }
                    if (prev[1] !== e.w[1] || prev[0] !== e.w[0]) rs[tv.key(prev[0], prev[1], 0)] = true;
                }
                tv.pendingSkip = null;
                rs[k] = true;
                if (!m[k]) m[k] = 1;
                tv.current = k;
                tv.lastLockedKey = e.w;
                tv.marksRev++;
            } else if (e.exp && !e.w) {
                tv.current = tv.key(e.exp[0], e.exp[1], e.exp[2]);
            }
            // الانتقال التلقائي للصفحة
            if (e.page > 0 && (e.page < tv.rightPage || e.page > tv.leftPage) && (e.st === "locked"))
                tv.jump(e.page);
        } else if (e.ev === "chk") {
            k = tv.key(e.loc[0], e.loc[1], e.loc[2]);
            m = tv.marks;
            var list = tv.mistakes.filter(function (x) { return x.id !== e.id; });
            if (e.st === "confirmed") {
                m[k] = tv.clsState(e.cls);
                if (e.cls === "skipped_passage") tv.pendingSkip = e.loc;
                list.unshift(e);
            } else if (e.st === "resolved" || e.st === "uncertain") {
                if (m[k] && m[k] >= 3) m[k] = 1;
            }
            tv.mistakes = list;
            tv.marksRev++;
        } else if (e.ev === "sim") {
            var arr = tv.sims.slice();
            arr.unshift(e);
            tv.sims = arr.slice(0, 6);
        } else if (e.ev === "near") {
            tv.near = e;
        } else if (e.ev === "ended") {
            tv.summary = e.summary;
            tv.current = "";
            histFile.reload();
        } else if (e.ev === "error") {
            tv.message = e.msg;
        }
    }

    // ---------- العرض: الصفحتان ----------
    readonly property real panelW: Math.min(420, Math.max(330, width * 0.24))
    Item {
        id: pagesArea
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: panel.right
        anchors.leftMargin: 8

        readonly property real gap: 14
        readonly property real pageAR: 0.6697
        readonly property real pageH: Math.min(height - 44, (width - gap - 24) / 2 / pageAR)
        readonly property real pageW: pageH * pageAR

        Rectangle {
            id: rightRect
            width: pagesArea.pageW
            height: pagesArea.pageH
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -12
            anchors.left: parent.horizontalCenter
            anchors.leftMargin: pagesArea.gap / 2
            color: T.paper
            border.color: T.edge
            border.width: 1
            radius: 3
            clip: true
            TasmeePage {
                anchors.fill: parent
                anchors.margins: 1
                page: tv.rightPage
                lay: tv.layout ? tv.layout.pages[tv.rightPage - 1] : null
                imageUrl: tv.imgUrl(tv.rightPage)
                fontUrl: tv.fontUrl(tv.rightPage)
                marks: tv.marks
                marksRev: tv.marksRev
                current: tv.current
                hideUnread: tv.hideUnread
                readSet: tv.readSet
                showOriginal: tv.showOriginal
                onWordClicked: function (s, a, w) { if (tv.engine) tv.engine.similar(s, a); }
            }
        }
        Rectangle {
            id: leftRect
            visible: tv.leftPage <= 604
            width: pagesArea.pageW
            height: pagesArea.pageH
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -12
            anchors.right: parent.horizontalCenter
            anchors.rightMargin: pagesArea.gap / 2
            color: T.paper
            border.color: T.edge
            border.width: 1
            radius: 3
            clip: true
            TasmeePage {
                anchors.fill: parent
                anchors.margins: 1
                page: tv.leftPage
                lay: (tv.layout && tv.leftPage <= 604) ? tv.layout.pages[tv.leftPage - 1] : null
                imageUrl: tv.leftPage <= 604 ? tv.imgUrl(tv.leftPage) : ""
                fontUrl: tv.fontUrl(tv.leftPage)
                marks: tv.marks
                marksRev: tv.marksRev
                current: tv.current
                hideUnread: tv.hideUnread
                readSet: tv.readSet
                showOriginal: tv.showOriginal
                onWordClicked: function (s, a, w) { if (tv.engine) tv.engine.similar(s, a); }
            }
        }
        Text {
            text: U.ar(tv.rightPage)
            color: T.gold
            font.family: T.fontTitle
            font.pixelSize: 17
            anchors.horizontalCenter: rightRect.horizontalCenter
            anchors.top: rightRect.bottom
            anchors.topMargin: 6
        }
        Text {
            visible: leftRect.visible
            text: U.ar(tv.leftPage)
            color: T.gold
            font.family: T.fontTitle
            font.pixelSize: 17
            anchors.horizontalCenter: leftRect.horizontalCenter
            anchors.top: leftRect.bottom
            anchors.topMargin: 6
        }

        // تقليب يدوي بالعجلة (خارج الجلسة أو أثناءها)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (ev) {
                if (ev.angleDelta.y < 0) tv.jump(tv.rightPage + 2);
                else if (ev.angleDelta.y > 0) tv.jump(tv.rightPage - 2);
            }
        }

        // شاشة تحميل النموذج (أول مرة تنزيل ~٦٨ ميجابايت ثم من الذاكرة المحلية)
        Rectangle {
            anchors.fill: parent
            visible: tv.engine && (tv.engine.loading || (!tv.engine.ready && tv.engine.error !== ""))
            color: Qt.rgba(0.93, 0.89, 0.82, 0.93)
            MouseArea { anchors.fill: parent }
            Column {
                anchors.centerIn: parent
                spacing: 18
                width: Math.min(parent.width - 60, 520)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "التسميع"
                    color: T.gold
                    font.family: T.fontUI
                    font.pixelSize: 38
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: !tv.engine ? "" : (tv.engine.error !== "" ? tv.engine.error
                          : (!tv.engine.loadFromCache && tv.engine.loadStage === "model")
                            ? "جارٍ تنزيل نموذج التسميع (٦٨ ميجابايت — مرة واحدة فقط، ثم يعمل بلا إنترنت)"
                            : tv.engine.loadStage === "setup" ? "جارٍ تثبيت محرك التسميع (مرة واحدة فقط)…"
                            : "جارٍ تجهيز محرك التسميع على جهازك…")
                    color: tv.engine && tv.engine.error !== "" ? "#A93B2E" : T.inkSoft
                    font.family: T.fontUI
                    font.pixelSize: 16
                }
                Rectangle {
                    visible: tv.engine && tv.engine.error === ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 420; height: 12; radius: 6
                    color: T.panel
                    border.color: T.goldSoft
                    Rectangle {
                        width: parent.width * (tv.engine ? (tv.engine.loadStage === "model" ? tv.engine.loadFraction * 0.85 : (tv.engine.loadStage === "warmup" ? 0.85 + 0.15 * tv.engine.loadFraction : 0.02)) : 0)
                        height: parent.height
                        radius: 6
                        color: T.gold
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "الصوت يُعالَج على جهازك ولا يُرسَل إلى أي مكان"
                    color: T.inkFaint
                    font.family: T.fontUI
                    font.pixelSize: 12
                }
                Rectangle {
                    visible: tv.engine && tv.engine.error !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 170; height: 42; radius: 21
                    color: rtMa.containsMouse ? T.gold : T.panel
                    border.color: T.goldSoft
                    Text { anchors.centerIn: parent; text: "إعادة المحاولة"; color: rtMa.containsMouse ? "#fff" : T.ink; font.family: T.fontUI; font.pixelSize: 15 }
                    MouseArea { id: rtMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tv.engine.boot() }
                }
            }
        }
    }

    // ---------- اللوحة الجانبية ----------
    TasmeePanel {
        id: panel
        tv: tv
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        anchors.leftMargin: 12
        width: tv.panelW
    }
}
