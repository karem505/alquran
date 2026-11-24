import QtQuick
import "theme.js" as T
import "utils.js" as U

// اللوحة الجانبية لوضع التسميع
Rectangle {
    id: pn
    property var tv: null
    readonly property var eng: tv ? tv.engine : null

    color: T.panel
    radius: 14
    border.color: T.goldSoft
    border.width: 1

    // زر صغير بهوية التطبيق
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool on: false
        property bool enabledX: true
        property color tint: T.gold
        signal clicked()
        width: pillT.implicitWidth + 24
        height: 32
        radius: 16
        opacity: enabledX ? 1 : 0.45
        color: on ? tint : (pma.containsMouse ? T.selBg : "transparent")
        border.color: on ? tint : T.goldSoft
        border.width: 1
        Text {
            id: pillT
            anchors.centerIn: parent
            text: pill.label
            color: pill.on ? "#FFFFFF" : T.ink
            font.family: T.fontUI
            font.pixelSize: 14
        }
        MouseArea {
            id: pma
            anchors.fill: parent
            hoverEnabled: true
            enabled: pill.enabledX
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
    // حقل رقمي مع − و +
    component Stepper: Row {
        id: st
        property int value: 1
        property int minV: 1
        property int maxV: 286
        property string caption: ""
        signal edited(int v)
        spacing: 6
        layoutDirection: Qt.RightToLeft
        Text { text: st.caption; color: T.inkSoft; font.family: T.fontUI; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
            width: 26; height: 26; radius: 13; color: plusMa.containsMouse ? T.selBg : "transparent"; border.color: T.goldSoft
            Text { anchors.centerIn: parent; text: "+"; color: T.gold; font.pixelSize: 16 }
            MouseArea { id: plusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: st.edited(Math.min(st.maxV, st.value + 1)) }
        }
        Text { text: U.ar(st.value); color: T.ink; font.family: T.fontUI; font.pixelSize: 15; width: 34; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
        Rectangle {
            width: 26; height: 26; radius: 13; color: minusMa.containsMouse ? T.selBg : "transparent"; border.color: T.goldSoft
            Text { anchors.centerIn: parent; text: "−"; color: T.gold; font.pixelSize: 16 }
            MouseArea { id: minusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: st.edited(Math.max(st.minV, st.value - 1)) }
        }
    }
    component SectionTitle: Text {
        color: T.gold
        font.family: T.fontTitle
        font.pixelSize: 17
        width: parent ? parent.width : 100
        horizontalAlignment: Text.AlignRight
    }
    component Sep: Rectangle { width: parent ? parent.width : 100; height: 1; color: T.edge; opacity: 0.6 }

    // ---------- الرأس ----------
    Item {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 58
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "التسميع"
            color: T.ink
            font.family: T.fontTitle
            font.pixelSize: 22
        }
        // حالة المايك + مؤشر المستوى
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                width: 10; height: 10; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: pn.tv && pn.tv.active ? "#2e7d32" : (pn.eng && pn.eng.ready ? T.goldSoft : T.edge)
                SequentialAnimation on opacity {
                    running: pn.tv ? pn.tv.active : false
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !pn.eng ? "" : (pn.tv.active ? statusText() : (pn.eng.ready ? "جاهز" : (pn.eng.loading ? "جارٍ التحميل" : "متوقف")))
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 13
                function statusText() {
                    var p = pn.tv.pos;
                    if (!p) return "يستمع…";
                    return p.st === "locked" ? "يتابعك" : p.st === "acquiring" ? "يبحث عن موضعك" : p.st === "ambiguous" ? "عدة مواضع محتملة" : "فقد الموضع";
                }
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                visible: pn.tv ? pn.tv.active : false
                Repeater {
                    model: 8
                    Rectangle {
                        required property int index
                        width: 4
                        height: 6 + index * 2
                        anchors.bottom: parent ? parent.bottom : undefined
                        radius: 2
                        color: (pn.eng && pn.eng.level > -60 + index * 6) ? T.gold : T.edge
                    }
                }
            }
        }
        Sep { anchors.bottom: parent.bottom }
    }

    // ---------- المحتوى القابل للتمرير ----------
    Flickable {
        id: fl
        anchors.top: head.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 14
        contentHeight: body.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: fl.width
            spacing: 12

            // ======== التحكم ========
            Flow {
                width: parent.width
                layoutDirection: Qt.RightToLeft
                spacing: 6
                visible: pn.tv && !pn.tv.active
                Repeater {
                    model: [["free", "تسميع حر"], ["page", "الصفحة"], ["spread", "الصفحتان"], ["range", "من آية إلى آية"], ["sura", "السورة"], ["rub", "الربع"], ["hizb", "الحزب"]]
                    delegate: Pill {
                        required property var modelData
                        label: modelData[1]
                        on: pn.tv && pn.tv.mode === modelData[0]
                        onClicked: {
                            pn.tv.mode = modelData[0];
                            if ((modelData[0] === "range" || modelData[0] === "sura") && pn.tv.qdata.ready) {
                                var loc = pn.tv.qdata.locate(pn.tv.rightPage);
                                var r = pn.tv.pageAyahRange(pn.tv.rightPage);
                                pn.tv.rangeSura = r ? r.from[0] : loc.suraI;
                                pn.tv.rangeFrom = r ? r.from[1] : 1;
                                pn.tv.rangeTo = r ? (r.to[0] === r.from[0] ? r.to[1] : pn.tv.ayaCount(r.from[0])) : 7;
                            }
                        }
                    }
                }
            }
            // شرح الوضع المختار
            Text {
                width: parent.width
                visible: pn.tv && !pn.tv.active
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 13
                text: {
                    if (!pn.tv || !pn.tv.qdata || !pn.tv.qdata.ready) return "";
                    if (pn.tv.mode === "free") return "اقرأ من أي موضع في القرآن، وسيجد التطبيق موضعك وينتقل إليه ويتابعك كلمةً كلمة.";
                    var p = pn.tv.passageFor(pn.tv.mode);
                    if (!p) return "";
                    var s = p.segs[0], e = p.segs[p.segs.length - 1];
                    return "المقطع: " + p.label + " — من سورة " + pn.tv.suraName(s.surah) + " آية " + U.ar(s.fromAyah)
                         + " إلى سورة " + pn.tv.suraName(e.surah) + " آية " + U.ar(e.toAyah) + ". يُقارَن ما تقرؤه بالمقطع كلمةً كلمة.";
                }
            }
            Column {
                width: parent.width
                spacing: 8
                visible: pn.tv && !pn.tv.active && (pn.tv.mode === "range" || pn.tv.mode === "sura")
                Row {
                    layoutDirection: Qt.RightToLeft
                    anchors.right: parent.right
                    spacing: 10
                    Stepper {
                        caption: "السورة"
                        value: pn.tv ? pn.tv.rangeSura : 1
                        maxV: 114
                        onEdited: function (v) {
                            pn.tv.rangeSura = v;
                            pn.tv.rangeFrom = 1;
                            pn.tv.rangeTo = Math.min(10, pn.tv.ayaCount(v));
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pn.tv ? pn.tv.suraName(pn.tv.rangeSura) : ""
                        color: T.ink
                        font.family: T.fontTitle
                        font.pixelSize: 17
                    }
                }
                Row {
                    visible: pn.tv && pn.tv.mode === "range"
                    layoutDirection: Qt.RightToLeft
                    anchors.right: parent.right
                    spacing: 14
                    Stepper {
                        caption: "من"
                        value: pn.tv ? pn.tv.rangeFrom : 1
                        maxV: pn.tv ? pn.tv.ayaCount(pn.tv.rangeSura) : 1
                        onEdited: function (v) { pn.tv.rangeFrom = v; if (pn.tv.rangeTo < v) pn.tv.rangeTo = v; }
                    }
                    Stepper {
                        caption: "إلى"
                        value: pn.tv ? pn.tv.rangeTo : 1
                        minV: pn.tv ? pn.tv.rangeFrom : 1
                        maxV: pn.tv ? pn.tv.ayaCount(pn.tv.rangeSura) : 1
                        onEdited: function (v) { pn.tv.rangeTo = v; }
                    }
                }
            }
            Flow {
                width: parent.width
                layoutDirection: Qt.RightToLeft
                spacing: 8
                Rectangle {
                    width: startT.implicitWidth + 40
                    height: 42
                    radius: 21
                    color: pn.tv && pn.tv.active ? "#a93b2e" : T.gold
                    opacity: (pn.eng && pn.eng.ready) ? 1 : 0.45
                    Text {
                        id: startT
                        anchors.centerIn: parent
                        text: pn.tv && pn.tv.active ? "إنهاء التسميع" : "ابدأ التسميع"
                        color: "#FFFFFF"
                        font.family: T.fontUI
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: pn.eng && pn.eng.ready
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pn.tv.active ? pn.tv.stopSession() : pn.tv.startSession()
                    }
                }
                Pill {
                    y: 5
                    label: "إخفاء الآيات"
                    on: pn.tv ? pn.tv.hideUnread : false
                    onClicked: pn.tv.hideUnread = !pn.tv.hideUnread
                }
                Pill {
                    y: 5
                    label: "الصورة الأصلية"
                    on: pn.tv ? pn.tv.showOriginal : false
                    onClicked: pn.tv.showOriginal = !pn.tv.showOriginal
                }
            }
            Text {
                visible: pn.tv && pn.tv.message !== ""
                width: parent.width
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                text: pn.tv ? pn.tv.message : ""
                color: "#A93B2E"
                font.family: T.fontUI
                font.pixelSize: 13
            }

            // ======== الموضع الحالي ========
            Rectangle {
                visible: pn.tv && pn.tv.pos !== null && pn.tv.active
                width: parent.width
                height: posCol.implicitHeight + 18
                radius: 10
                color: T.paper
                border.color: T.edge
                Column {
                    id: posCol
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 2
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: {
                            var p = pn.tv ? pn.tv.pos : null;
                            var w = p ? (p.w || p.exp) : null;
                            if (!w) return "استمع… ابدأ القراءة";
                            return "سورة " + pn.tv.suraName(w[0]) + " · الآية " + U.ar(w[1]) + " · الكلمة " + U.ar(w[2]);
                        }
                        color: T.ink
                        font.family: T.fontTitle
                        font.pixelSize: 17
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        visible: pn.tv && pn.tv.pos && pn.tv.pos.st === "ambiguous"
                        text: "المقطع مكرر في أكثر من موضع — استمر في القراءة ليتحدد الموضع"
                        color: T.inkSoft
                        font.family: T.fontUI
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ======== المتشابهات: انتقال إلى موضع متشابه ========
            Repeater {
                model: pn.tv ? pn.tv.sims : []
                delegate: Rectangle {
                    id: simCard
                    required property var modelData
                    required property int index
                    width: body.width
                    height: simCol.implicitHeight + 22
                    radius: 12
                    color: "#FBF4F1"
                    border.color: "#D9A99F"
                    border.width: index === 0 ? 1.6 : 1
                    opacity: index === 0 ? 1 : 0.85
                    Column {
                        id: simCol
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 8
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.WordWrap
                            text: simCard.modelData.kind === "reloc" ? "تحدّد موضعك بين آيتين متشابهتين"
                                : simCard.modelData.kind === "confusion" ? "يبدو أنك خلطتَ بآية متشابهة"
                                : simCard.modelData.kind === "passage" ? "خرجتَ إلى آية متشابهة خارج المقطع"
                                : "انتقلتَ إلى آية متشابهة"
                            color: "#8f2d22"
                            font.family: T.fontUI
                            font.pixelSize: 15
                            font.bold: true
                        }
                        AyahSnippet {
                            width: parent.width
                            view: simCard.modelData.a
                            fontsDir: pn.tv.fontsDir
                            tag: simCard.modelData.kind === "reloc" ? "الموضع الأول" : "المطلوب"
                            accent: "#2e6b3a"
                            onClicked: function (s, a, p) { pn.tv.jump(p); }
                        }
                        Sep {}
                        AyahSnippet {
                            width: parent.width
                            view: simCard.modelData.b
                            fontsDir: pn.tv.fontsDir
                            tag: simCard.modelData.kind === "reloc" ? "الموضع المؤكَّد" : (simCard.modelData.kind === "confusion" ? "الآية المتشابهة" : "ما قرأته")
                            accent: "#b3261e"
                            onClicked: function (s, a, p) { pn.tv.jump(p); }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: "الكلمات المظللة هي مواضع الاختلاف بين الآيتين"
                            color: T.inkFaint
                            font.family: T.fontUI
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // ======== الأخطاء ========
            SectionTitle {
                visible: pn.tv && (pn.tv.mistakes.length > 0 || pn.tv.active)
                text: pn.tv && pn.tv.mistakes.length ? ("الأخطاء (" + U.ar(pn.tv.mistakes.length) + ")") : "الأخطاء"
            }
            Text {
                visible: pn.tv && pn.tv.active && pn.tv.mistakes.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: "لا أخطاء حتى الآن"
                color: T.inkFaint
                font.family: T.fontUI
                font.pixelSize: 13
            }
            Repeater {
                model: pn.tv ? pn.tv.mistakes : []
                delegate: Rectangle {
                    id: mrow
                    required property var modelData
                    width: body.width
                    height: 44
                    radius: 10
                    color: mma.containsMouse ? T.panelAlt : T.paper
                    border.color: T.edge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 8
                        width: chipT.implicitWidth + 16
                        height: 24
                        radius: 12
                        color: Qt.rgba(0, 0, 0, 0)
                        border.color: pn.tv.clsColor(mrow.modelData.cls)
                        Text { id: chipT; anchors.centerIn: parent; text: pn.tv.clsName(mrow.modelData.cls); color: pn.tv.clsColor(mrow.modelData.cls); font.family: T.fontUI; font.pixelSize: 12 }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: mrow.modelData.text
                        color: T.ink
                        font.family: T.fontTitle
                        font.pixelSize: 19
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: mrow.modelData.sura + " " + U.ar(mrow.modelData.loc[1])
                        color: T.inkSoft
                        font.family: T.fontUI
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: mma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pn.tv.jump(mrow.modelData.page);
                            pn.tv.current = pn.tv.key(mrow.modelData.loc[0], mrow.modelData.loc[1], mrow.modelData.loc[2]);
                        }
                    }
                }
            }

            // ======== ملخص الجلسة ========
            Rectangle {
                visible: pn.tv && pn.tv.summary !== null && !pn.tv.active
                width: parent.width
                height: sumCol.implicitHeight + 22
                radius: 12
                color: T.paper
                border.color: T.goldSoft
                Column {
                    id: sumCol
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 6
                    readonly property var s: pn.tv ? pn.tv.summary : null
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: "ملخص الجلسة" + (sumCol.s && sumCol.s.label ? " — " + sumCol.s.label : "")
                        color: T.gold
                        font.family: T.fontTitle
                        font.pixelSize: 17
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        color: T.ink
                        font.family: T.fontUI
                        font.pixelSize: 14
                        text: {
                            var s = sumCol.s;
                            if (!s) return "";
                            var mins = Math.floor(s.durMs / 60000), secs = Math.round((s.durMs % 60000) / 1000);
                            return "المدة " + U.ar(mins) + ":" + (secs < 10 ? "٠" : "") + U.ar(secs)
                                 + " · الآيات " + U.ar(s.ayahs) + " · الأخطاء " + U.ar(s.mistakes)
                                 + (s.sims ? " · متشابهات " + U.ar(s.sims) : "");
                        }
                    }
                    Flow {
                        width: parent.width
                        layoutDirection: Qt.RightToLeft
                        spacing: 6
                        Repeater {
                            model: sumCol.s ? Object.keys(sumCol.s.byClass) : []
                            delegate: Rectangle {
                                required property var modelData
                                width: bcT.implicitWidth + 16; height: 24; radius: 12
                                color: "transparent"; border.color: pn.tv.clsColor(modelData)
                                Text { id: bcT; anchors.centerIn: parent; text: pn.tv.clsName(modelData) + " " + U.ar(sumCol.s.byClass[modelData]); color: pn.tv.clsColor(modelData); font.family: T.fontUI; font.pixelSize: 12 }
                            }
                        }
                    }
                    Text {
                        visible: sumCol.s && sumCol.s.hot.length > 0
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        color: T.inkSoft
                        font.family: T.fontUI
                        font.pixelSize: 13
                        text: sumCol.s && sumCol.s.hot.length
                              ? "أكثر المواضع أخطاءً: " + sumCol.s.hot.map(function (h) { return h.sura + " " + U.ar(h.a) + " (" + U.ar(h.n) + ")"; }).join("، ")
                              : ""
                    }
                }
            }

            // ======== متشابهات الآية الحالية ========
            Rectangle {
                visible: pn.tv && pn.tv.near !== null && pn.tv.near.list.length > 0
                width: parent.width
                height: nearCol.implicitHeight + 22
                radius: 12
                color: T.paper
                border.color: T.edge
                Column {
                    id: nearCol
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 8
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: pn.tv && pn.tv.near ? ("متشابهات الآية " + U.ar(pn.tv.near.a) + " من سورة " + pn.tv.near.sura) : ""
                        color: T.gold
                        font.family: T.fontTitle
                        font.pixelSize: 16
                    }
                    Repeater {
                        model: pn.tv && pn.tv.near ? pn.tv.near.list.slice(0, 2) : []
                        delegate: Column {
                            required property var modelData
                            width: nearCol.width
                            spacing: 6
                            AyahSnippet {
                                width: parent.width
                                view: modelData.b
                                fontsDir: pn.tv.fontsDir
                                accent: "#8a5a00"
                                glyphSize: 24
                                onClicked: function (s, a, p) { pn.tv.jump(p); }
                            }
                            Sep {}
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        text: "المظلل: ما يختلف عن الآية الحالية. انقر أي كلمة في الصفحة لعرض متشابهات آيتها."
                        color: T.inkFaint
                        font.family: T.fontUI
                        font.pixelSize: 11
                    }
                }
            }

            // ======== سجل الجلسات ========
            SectionTitle {
                visible: pn.tv && !pn.tv.active && pn.tv.history.length > 0
                text: "الجلسات السابقة"
            }
            Repeater {
                model: pn.tv && !pn.tv.active ? pn.tv.history.slice(0, 8) : []
                delegate: Rectangle {
                    id: hrow
                    required property var modelData
                    width: body.width
                    height: 40
                    radius: 10
                    color: T.paper
                    border.color: T.edge
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: hrow.modelData.label || (hrow.modelData.mode === "free" ? "تسميع حر" : "مقطع")
                        color: T.ink
                        font.family: T.fontUI
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            var d = new Date(hrow.modelData.startedAt);
                            var mins = Math.max(1, Math.round(hrow.modelData.durMs / 60000));
                            return U.ar(d.getDate()) + "/" + U.ar(d.getMonth() + 1) + " · " + U.ar(mins) + " د · " + U.ar(hrow.modelData.ayahs) + " آية · " + U.ar(hrow.modelData.mistakes) + " خطأ";
                        }
                        color: T.inkSoft
                        font.family: T.fontUI
                        font.pixelSize: 12
                    }
                }
            }

            // ======== إسناد ========
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                text: "محرك التسميع: Tilawa (MIT) — نموذج spliced-clean برخصة CC BY 4.0. النص: Tanzil.net. خطوط الصفحات: مجمع الملك فهد (QPC). لا يُقيَّم التجويد أو النطق."
                color: T.inkFaint
                font.family: T.fontUI
                font.pixelSize: 11
            }
        }
    }
}
