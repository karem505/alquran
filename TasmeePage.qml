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

                // غطاء الورق فوق السطر الأصلي
                Rectangle {
                    // الصفحات ٣+: عرض الإطار الداخلي كاملًا؛ ١ و٢: حدود داخل البيضاوي (m)
                    x: lineItem.isText ? ((lineItem.ln.m ? lineItem.ln.m[0] : 66) - lineItem.ln.x[0]) : 0
                    width: lineItem.isText ? ((lineItem.ln.m ? lineItem.ln.m[1] : 740) - (lineItem.ln.m ? lineItem.ln.m[0] : 66)) : 0
                    y: root.special ? -1 : 1
                    height: parent.height - (root.special ? -2 : 2)
                    color: "#ffffff"
                }

                // حجم الخط لهذا السطر: يُضبط بحيث يملأ مجموع الكلمات عرض السطر مع فراغات طبيعية
                property real fs: root.special ? 38 : 47.2
                property var widths: []
                property bool laid: false

                function relayout() {
                    if (!isText) return;
                    var n = words.count;
                    if (n === 0) return;
                    var sum = 0, ws = [];
                    for (var i = 0; i < n; i++) {
                        var it = words.itemAt(i);
                        if (!it) return;
                        var w = it.natural;
                        ws.push(w);
                        sum += w;
                    }
                    var W = lineItem.width;
                    // ملاءمة السطر وحده (فراغ أدنى ٢) + ملاءمة مريحة (فراغ ٦) تُرسل لحساب مقياس الصفحة
                    var fitMax = W / sum;
                    var fitNice = W / sum;
                    if (W >= root.fullW * 0.9 && n > 2) root.reportFit(index, fitNice);
                    var k = Math.min(root.kPage, fitMax);
                    var gap = n > 1 ? (W - sum * k) / (n - 1) : 0;
                    var xr = W;               // من اليمين لليسار
                    if (n === 1) xr = W / 2 + ws[0] * k / 2;
                    for (var j = 0; j < n; j++) {
                        var it2 = words.itemAt(j);
                        it2.k = k;
                        it2.x = xr - ws[j] * k;
                        xr -= ws[j] * k + gap;
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
                        readonly property real natural: glyph.implicitWidth
                        height: lineItem.height
                        width: natural * k

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

                        // علامة نهاية الآية بألوان الطبعة: قرص كريمي + بتلتان بنفسجيتان أعلى وأسفل
                        Item {
                            visible: wordItem.isEnd && !wordItem.hidden
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: root.special ? 1 : -1
                            width: wordItem.width * 0.74
                            height: width * 1.42
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 0
                                width: parent.width * 0.62
                                height: parent.height
                                radius: width / 2
                                color: "#7A5A9C"
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.width
                                radius: width / 2
                                color: "#F1E8E1"
                                border.color: "#A0958C"
                                border.width: 1
                            }
                        }
                        Text {
                            id: glyph
                            text: wordItem.wd[0]
                            font.family: qfont.name
                            font.pixelSize: lineItem.fs
                            color: wordItem.isCur ? root.curColor
                                 : wordItem.st === 3 ? root.wrongColor
                                 : wordItem.st === 4 ? root.missColor
                                 : wordItem.st === 5 ? root.skipColor
                                 : root.inkColor
                            opacity: wordItem.hidden ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            scale: wordItem.k
                            transformOrigin: Item.Left
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
