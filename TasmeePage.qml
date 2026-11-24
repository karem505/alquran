import QtQuick

// صفحة مصحف مرندرة من البيانات (وضع التسميع)
// تُرسم بإحداثيات صورة الصفحة الأصلية (807×1205 أو 843×1140) ثم تُكبَّر لتملأ مكانها:
//   - الصورة الأصلية خلفية (الإطار والترويسات والبسملة كما هي)
//   - كل سطر نصي يُغطّى بالورق الأبيض ويُعاد رسمه كلمةً كلمة بخط QPC V2 الخاص بالصفحة
//   - كل كلمة عنصر مستقل يتلوّن حسب حالة التسميع
Item {
    id: root

    property int page: 0
    property var lay: null            // كائن الصفحة من layout.json: {l: [...]}
    property string imageUrl: ""
    property string fontUrl: ""
    property var marks: ({})          // "s:a:w" → حالة (انظر stateColor)
    property int marksRev: 0          // يزيد عند كل تعديل على marks لإعادة التلوين
    property string current: ""       // "s:a:w" الكلمة الحالية
    property bool hideUnread: false   // وضع الحفظ: إخفاء الكلمات غير المقروءة
    property var readSet: ({})        // "s:a:w" → true للكلمات المقروءة (لوضع الحفظ)
    property bool fallbackFont: false // الخط غير متاح بعد
    property bool showOriginal: false // للمقارنة: الصورة الأصلية بلا رندرة

    property bool debugLayout: false  // أداة المقارنة: تطبع قياسات كل سطر (فراغات الحبر/التصغير)

    signal wordClicked(int s, int a, int w)

    readonly property bool special: page > 0 && page <= 2
    readonly property real srcW: special ? 843 : 807
    readonly property real srcH: special ? 1140 : 1205
    readonly property real lineH: special ? 52.8 : (1140 - 64) / 15
    readonly property real sc: Math.min(width / srcW, height / srcH)
    readonly property bool fontReady: qfont.status === FontLoader.Ready

    // ألوان الحالات (هوية المصحف: حبر داكن، ذهبي للتحديد)
    readonly property color inkColor: "#1c1610"
    readonly property color curColor: "#8a5a00"
    readonly property color okColor: "#1c1610"
    readonly property color wrongColor: "#b3261e"
    readonly property color missColor: "#c2610c"
    readonly property color skipColor: "#9a7b9a"

    // مقياس موحّد لكل كلمات الصفحة = وسيط ملاءمة الأسطر الكاملة
    property real kPage: 1.0
    property var fits: ({})
    readonly property real fullW: special ? 380 : 630
    function reportFit(i, f) { fits[i] = f; fitTimer.restart(); }
    Timer {
        id: fitTimer
        interval: 30
        onTriggered: {
            var v = [];
            for (var k in root.fits) v.push(root.fits[k]);
            if (v.length === 0) return;
            v.sort(function (a, b) { return a - b; });
            var m = v[Math.floor(v.length / 2)];
            if (Math.abs(m - root.kPage) > 0.002) root.kPage = m;
        }
    }
    onLayChanged: { fits = {}; kPage = 1.0; }

    FontLoader {
        id: qfont
        source: root.fontUrl
    }

    function key(s, a, w) { return s + ":" + a + ":" + w; }
    function arNum(n) {
        var d = "٠١٢٣٤٥٦٧٨٩", s = String(n), o = "";
        for (var i = 0; i < s.length; i++) o += d[+s[i]];
        return o;
    }

    Item {
        id: canvas
        width: root.srcW
        height: root.srcH
        // تمدد مثل وضع القراءة تمامًا (الصورة تملأ مكانها) — الصفحتان ١ و٢ نسبتهما مختلفة قليلًا
        transform: Scale { xScale: root.width / root.srcW; yScale: root.height / root.srcH }

        Image {
            anchors.fill: parent
            source: root.imageUrl
            asynchronous: true
            smooth: true
            mipmap: true
            cache: false
        }

        // صفحات «مرسومة كاملة» (ترويسة السورة في موضع مختلف عن الصورة): غطاء على المساحة الداخلية كلها
        Rectangle {
            visible: root.lay !== null && root.lay.own === true && root.fontReady && !root.showOriginal
            x: 64; y: 65; width: 678; height: 1074
            color: "#ffffff"
        }
        function srcUrl(p) {
            var n = p < 10 ? "00" + p : (p < 100 ? "0" + p : "" + p);
            return String(root.imageUrl).replace(/p[0-9]{3}\.jpg/, "p" + n + ".jpg");
        }
        Repeater {
            model: (root.lay && root.lay.own && root.fontReady && !root.showOriginal) ? root.lay.l : []
            delegate: Item {
                required property var modelData
                required property int index
                readonly property bool has: modelData && modelData.src !== undefined
                visible: has
                x: 63
                y: 64 + index * (1076 / 15)
                width: 680
                height: 1076 / 15
                clip: true
                Image {
                    visible: parent.has
                    source: parent.has ? canvas.srcUrl(parent.modelData.src[0]) : ""
                    x: -63
                    y: parent.has ? -(64 + (parent.modelData.src[1] - 1) * (1076 / 15)) : 0
                    width: 807
                    height: 1205
                    asynchronous: true
                    smooth: true
                    mipmap: true
                }
            }
        }

        // أغطية الورق فوق أسطر الصورة الأصلية — كلها قبل النص المرسوم، حتى لا يقصّ غطاءُ سطرٍ
        // أطرافَ حروف السطر الذي فوقه (الحركات والمدود الهابطة)
        Repeater {
            model: (root.lay && root.fontReady && !root.showOriginal) ? root.lay.l : []
            delegate: Rectangle {
                required property var modelData
                readonly property bool isText: modelData !== null && modelData !== undefined && modelData.t === "w"
                visible: isText
                // الصفحات ٣+: عرض الإطار الداخلي كاملًا؛ ١ و٢: حدود داخل البيضاوي (m)
                x: isText ? (modelData.m ? modelData.m[0] : 66) : 0
                width: isText ? ((modelData.m ? modelData.m[1] : 740) - x) : 0
                y: !isText ? 0 : (modelData.mk ? modelData.mk[0] : modelData.y - root.lineH / 2 - 1)
                height: !isText ? 0 : (modelData.mk ? modelData.mk[1] - modelData.mk[0] : root.lineH + 2)
                color: "#ffffff"
            }
        }

        Repeater {
            model: (root.lay && root.fontReady && !root.showOriginal) ? root.lay.l : []
            delegate: Item {
                id: lineItem
                required property var modelData
                required property int index
                readonly property var ln: modelData
                readonly property bool isText: ln !== null && ln !== undefined && ln.t === "w"
                visible: isText
                x: isText ? ln.x[0] : 0
                width: isText ? (ln.x[1] - ln.x[0]) : 0
                y: isText ? ln.y - root.lineH / 2 : 0
                height: root.lineH

                // التخطيط: خطوط QPC V2 مُبرّرة مسبقًا (عرض التقدّم لكل رمز يحمل فراغ السطر الطبيعي)،
                // فنرصّ الكلمات بعرض التقدّم من اليمين بمقياس موحّد للصفحة، ثم نضبط الفراغات بين حدود
                // الحبر لتطابق امتداد السطر في الصورة. ملاحظة: Text.implicitWidth لا يساوي عرض التقدّم
                // (يضيف امتداد العلامات)، لذلك نقيس بـ TextMetrics.advanceWidth ونرسم بمحاذاة يسار صريحة.
                property real fs: root.special ? 38 : 47
                property bool laid: false

                function relayout() {
                    if (!isText) return;
                    var n = words.count;
                    if (n === 0) return;
                    var adv = [], rx = [], rw = [], sumAdv = 0, i;
                    for (i = 0; i < n; i++) {
                        var it = words.itemAt(i);
                        if (!it || it.adv <= 0) return;
                        adv.push(it.adv); rx.push(it.inkX); rw.push(it.inkW);
                        sumAdv += it.adv;
                    }
                    var W = lineItem.width;
                    if (W >= root.fullW * 0.9 && n > 2) root.reportFit(index, W / sumAdv);
                    var k = root.kPage;
                    // ١) رصّ بعرض التقدّم من اليمين → حدود حبر كل كلمة
                    var L = [], R = [], o = W;
                    for (i = 0; i < n; i++) {
                        o -= adv[i] * k;
                        L.push(o + rx[i] * k);
                        R.push(o + (rx[i] + rw[i]) * k);
                    }
                    // ٢) فراغات الحبر بين الكلمات (قد تكون سالبة: تداخل طبيعي في الرسم العثماني)
                    var g = [];
                    for (i = 0; i < n - 1; i++) g.push(L[i] - R[i + 1]);
                    var span = R[0] - L[n - 1];
                    var target = W;
                    var own = root.lay && root.lay.own;
                    if (own && span < W * 0.8) target = span;          // سطر قصير في صفحة مرسومة كاملة: يُوسَّط
                    var delta = target - span;
                    if (n > 1 && delta > 0) {
                        for (i = 0; i < n - 1; i++) g[i] += delta / (n - 1);
                    } else if (n > 1 && delta < 0) {
                        // تقليص الفراغات الواسعة أولًا (لا ننزل تحت فراغ أدنى) ثم تصغير موحّد لو لزم
                        var gMin = 3, ex = 0;
                        for (i = 0; i < n - 1; i++) ex += Math.max(0, g[i] - gMin);
                        var need = -delta;
                        var f = ex > 0 ? Math.min(1, need / ex) : 0;
                        for (i = 0; i < n - 1; i++) { var e = Math.max(0, g[i] - gMin); g[i] -= e * f; }
                        need -= ex * f;
                        if (need > 0.5) {
                            var inkSum = 0, gSum = 0;
                            for (i = 0; i < n; i++) inkSum += rw[i] * k;
                            for (i = 0; i < n - 1; i++) gSum += g[i];
                            var sc = Math.max(0.5, (target - gSum) / inkSum);
                            k *= sc;
                        }
                    }
                    // ٢ب) فراغ أدنى حول علامات الآيات (حبر رمز العلامة في الخط ~٣٨ بكسل والوسام المرسوم ~٣٥؛ في الطبعة ٣–٥ بكسل) — يُعوَّض من الفراغات الواسعة
                    if (n > 1) {
                        var gM = 3, debt = 0, isEndAt = function (j) { return words.itemAt(j).isEnd; };
                        for (i = 0; i < n - 1; i++) {
                            if ((isEndAt(i) || isEndAt(i + 1)) && g[i] < gM) { debt += gM - g[i]; g[i] = gM; }
                        }
                        if (debt > 0) {
                            var ex2 = 0;
                            for (i = 0; i < n - 1; i++) if (!isEndAt(i) && !isEndAt(i + 1)) ex2 += Math.max(0, g[i] - 2);
                            var f2 = ex2 > 0 ? Math.min(1, debt / ex2) : 0;
                            for (i = 0; i < n - 1; i++) if (!isEndAt(i) && !isEndAt(i + 1)) g[i] -= Math.max(0, g[i] - 2) * f2;
                            var left2 = debt - ex2 * f2;
                            if (left2 > 0.5) {
                                var ink2 = 0;
                                for (i = 0; i < n; i++) ink2 += rw[i] * k;
                                k *= Math.max(0.5, (ink2 - left2) / ink2);
                            }
                        }
                    }
                    if (root.debugLayout) {
                        var mg = 1e9;
                        for (i = 0; i < n - 1; i++) mg = Math.min(mg, g[i]);
                        console.log("TASMEE-LAYOUT " + root.page + " " + (index + 1) + " n=" + n + " minGap=" + mg.toFixed(1)
                                    + " k=" + (k / root.kPage).toFixed(3) + " span=" + span.toFixed(0) + " W=" + W.toFixed(0));
                    }
                    // ٣) التموضع: حافة حبر الكلمة الأولى يمين السطر (أو وسطه)
                    var right = own && span < W * 0.8 ? (W + target) / 2 : W;
                    if (n === 1) right = W / 2 + rw[0] * k / 2;
                    for (i = 0; i < n; i++) {
                        var w2 = words.itemAt(i);
                        w2.k = k;
                        w2.x = right - rw[i] * k;
                        if (i < n - 1) right = w2.x - g[i];
                    }
                    laid = true;
                }
                Connections {
                    target: root
                    function onKPageChanged() { relayoutTimer.restart(); }
                }

                Repeater {
                    id: words
                    model: lineItem.isText ? lineItem.ln.w : []
                    delegate: Item {
                        id: wordItem
                        required property var modelData
                        readonly property var wd: modelData       // [glyph, s, a, t0, t1]
                        readonly property bool isEnd: wd[3] === 0
                        readonly property string k0: root.key(wd[1], wd[2], wd[3])
                        property real k: 1
                        // مقاييس الرمز: عرض التقدّم وحدود الحبر (نسبةً لبداية السطر المرسوم يسارًا)
                        readonly property real adv: tm.advanceWidth
                        readonly property real inkX: tm.tightBoundingRect.x
                        readonly property real inkW: Math.max(1, tm.tightBoundingRect.width)
                        onAdvChanged: relayoutTimer.restart()
                        TextMetrics {
                            id: tm
                            font: glyph.font
                            text: glyph.text
                        }
                        height: lineItem.height
                        width: inkW * k

                        // حالة الكلمة: أسوأ حالة بين كلمات Tilawa التي يغطيها الرمز
                        readonly property int st: {
                            root.marksRev;
                            if (isEnd) return 0;
                            var best = 0;
                            for (var t = wd[3]; t <= wd[4]; t++) {
                                var v = root.marks[root.key(wd[1], wd[2], t)];
                                if (v !== undefined && v > best) best = v;
                            }
                            return best;
                        }
                        readonly property bool isCur: {
                            if (isEnd || root.current === "") return false;
                            for (var t = wd[3]; t <= wd[4]; t++)
                                if (root.current === root.key(wd[1], wd[2], t)) return true;
                            return false;
                        }
                        readonly property bool hidden: {
                            root.marksRev;
                            if (!root.hideUnread) return false;
                            if (isEnd) return !root.readSet[root.key(wd[1], wd[2], 0)];
                            return !root.readSet[root.key(wd[1], wd[2], wd[4])];
                        }

                        // خلفية الكلمة الحالية / الخطأ
                        Rectangle {
                            visible: wordItem.isCur || wordItem.st >= 3
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 2
                            x: -4
                            width: parent.width + 8
                            height: parent.height * 0.86
                            radius: 10
                            color: wordItem.isCur ? "#33C9A24B" : (wordItem.st === 3 ? "#1FB3261E" : (wordItem.st === 4 ? "#1FC2610C" : "#1A9A7B9A"))
                            border.color: wordItem.isCur ? "#C9A24B" : "transparent"
                            border.width: wordItem.isCur ? 1.6 : 0
                        }
                        // خط تحت الكلمة الناقصة/المتخطاة
                        Rectangle {
                            visible: wordItem.st === 4 || wordItem.st === 5
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            width: parent.width
                            height: 2.5
                            radius: 1.25
                            color: wordItem.st === 4 ? root.missColor : root.skipColor
                        }
                        // موضع كلمة زائدة: نقطة قبل الكلمة
                        Rectangle {
                            visible: wordItem.st === 6
                            width: 9; height: 9; radius: 4.5
                            color: root.wrongColor
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width + 2
                        }

                        // علامة نهاية الآية: وسام الطبعة نفسه (مقتطع مرة واحدة من صورة المصحف، assets/ayah-medallion.png)
                        // بنفس المقاس في كل الصفحات + رقم الآية — شكل موحّد لكل العلامات
                        Item {
                            visible: wordItem.isEnd && !wordItem.hidden
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: root.special ? 0 : 3
                            width: root.special ? 33 : 37
                            height: width * 47 / 37
                            Image {
                                anchors.fill: parent
                                source: Qt.resolvedUrl("assets/ayah-medallion.png")
                                smooth: true
                                mipmap: true
                            }
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 1
                                text: root.arNum(wordItem.wd[2])
                                font.family: "Amiri"
                                font.pixelSize: wordItem.wd[2] >= 100 ? 13 : 15
                                color: "#2b241c"
                            }
                        }
                        Text {
                            id: glyph
                            // المسافة داخل رمز مركّب («۞ وما») أضيق في الطبعة من مسافة الخط
                            text: wordItem.wd[0].replace(" ", "\u200A")
                            font.family: qfont.name
                            font.pixelSize: lineItem.fs
                            color: wordItem.isCur ? root.curColor
                                 : wordItem.st === 3 ? root.wrongColor
                                 : wordItem.st === 4 ? root.missColor
                                 : wordItem.st === 5 ? root.skipColor
                                 : root.inkColor
                            opacity: (wordItem.hidden || wordItem.isEnd) ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            width: wordItem.adv
                            horizontalAlignment: Text.AlignLeft
                            scale: wordItem.k
                            transformOrigin: Item.Left
                            x: -wordItem.inkX * wordItem.k
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: root.special ? 2 : -2.0
                            renderType: Text.QtRendering
                        }
                        // مكان الكلمة المخفية (وضع الحفظ)
                        Rectangle {
                            visible: wordItem.hidden && !wordItem.isEnd
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 10
                            width: parent.width - 6
                            x: 3
                            height: 3
                            radius: 1.5
                            color: "#D9C79A"
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !wordItem.isEnd
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.wordClicked(wordItem.wd[1], wordItem.wd[2], wordItem.wd[3])
                        }
                        Component.onCompleted: relayoutTimer.restart()
                    }
                }
                Timer {
                    id: relayoutTimer
                    interval: 0
                    onTriggered: lineItem.relayout()
                }
                onWidthChanged: relayoutTimer.restart()
            }
        }
    }
}
