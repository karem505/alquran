import QtQuick
import "theme.js" as T
import "utils.js" as U

// قائمة التقسيمات: سورة / جزء / حزب / ربع / صفحة / العلامات — تفتح على موضع القراءة الحالي
Item {
    id: root
    visible: false

    property var qdata: null      // عنصر Data
    property var loc: null        // نتيجة locate للصفحة الحالية
    property int currentPage: 1
    property int totalPages: 604
    property var bookmarks: []    // علامات الحفظ

    signal jump(int page)
    signal closed()
    signal bookmarkRemove(var bm)

    property int tab: 0          // 0 سور 1 أجزاء 2 أحزاب 3 أرباع 4 صفحات 5 علامات
    property var tabTitles: ["السور", "الأجزاء", "الأحزاب", "الأرباع", "الصفحات", "العلامات"]
    property var model: []

    function open() {
        visible = true;
        rebuild();
        root.forceActiveFocus();
    }
    function close() {
        visible = false;
        root.closed();
    }

    // لوحة المفاتيح: ١-٦ للتبويبات، والأسهم للتنقل بينها
    focus: true
    Keys.onPressed: function (ev) {
        if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_6) {
            tab = ev.key - Qt.Key_1;
            rebuild();
            ev.accepted = true;
        } else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) {
            tab = (tab + 1) % 6;
            rebuild();
            ev.accepted = true;
        } else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) {
            tab = (tab + 5) % 6;
            rebuild();
            ev.accepted = true;
        }
    }

    onBookmarksChanged: if (visible && tab === 5) rebuild()

    function rebuild() {
        if (!root.qdata || !root.qdata.ready) return;
        var out = [];
        var i;
        if (tab === 0) {
            for (i = 1; i <= 114; i++) {
                var su = root.qdata.q.surahs[i - 1];
                out.push({ t: su.name, s: U.ar(su.ayas) + " آية", p: su.p, idx: i });
            }
        } else if (tab === 1) {
            for (i = 1; i <= 30; i++) {
                var jz = root.qdata.nv.juz[i - 1];
                out.push({ t: "الجزء " + U.ar(i), s: "سورة " + root.qdata.q.surahs[jz.s - 1].name + " · آية " + U.ar(jz.a), p: jz.p, idx: i });
            }
        } else if (tab === 2) {
            for (i = 1; i <= 60; i++) {
                var hz = root.qdata.nv.hizb[i - 1];
                out.push({ t: "الحزب " + U.ar(i), s: "الجزء " + U.ar(Math.ceil(i / 2)) + " · سورة " + root.qdata.q.surahs[hz.s - 1].name, p: hz.p, idx: i });
            }
        } else if (tab === 3) {
            for (i = 1; i <= 240; i++) {
                var rb = root.qdata.nv.rub[i - 1];
                out.push({ t: "الربع " + U.ar(i), s: "الحزب " + U.ar(Math.ceil(i / 4)) + " · الجزء " + U.ar(Math.ceil(i / 8)) + " · سورة " + root.qdata.q.surahs[rb.s - 1].name, p: rb.p, idx: i });
            }
        } else if (tab === 4) {
            for (i = 1; i <= 604; i++) {
                var lc = root.qdata.locate(i);
                out.push({ t: "صفحة " + U.ar(i), s: lc ? ("سورة " + lc.suraName) : "", p: i, idx: i });
            }
        } else {
            var bms = root.bookmarks || [];
            for (i = 0; i < bms.length; i++) {
                var b = bms[i];
                var lc2 = root.qdata.locate(b.p);
                var sub = lc2 ? ("سورة " + lc2.suraName + " · الجزء " + U.ar(lc2.juz)) : "";
                out.push({
                    t: "صفحة " + U.ar(b.p) + "–" + U.ar(Math.min(b.p + 1, root.totalPages)),
                    s: b.a ? ("الآية " + U.ar(b.a) + " · " + sub) : sub,
                    p: b.p,
                    idx: i,
                    bm: b
                });
            }
        }
        root.model = out;
        scrollToCurrent();
    }

    function currentIdx() {
        if (root.tab === 5 || !root.loc) return 0;
        if (tab === 0) return root.loc.suraI - 1;
        if (tab === 1) return root.loc.juz - 1;
        if (tab === 2) return root.loc.hizb - 1;
        if (tab === 3) return root.loc.rub - 1;
        return currentPage - 1;
    }

    function scrollToCurrent() {
        var idx = currentIdx();
        if (idx >= 0 && idx < list.count) list.positionViewAtIndex(idx, ListView.Center);
    }

    // ---------- الخلفية المعتمة ----------
    Rectangle {
        anchors.fill: parent
        color: "#40000000"
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // ---------- اللوح ----------
    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.min(460, parent.width * 0.42)
        color: T.panel
        border.color: T.edge
        border.width: 1

        // رأس اللوح
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 54
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: T.edge }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "الانتقال إلى"
                color: T.ink
                font.family: T.fontTitle
                font.pixelSize: 19
            }
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: closeMa.containsMouse ? T.selBg : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: T.inkSoft; font.pixelSize: 14 }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // التبويبات
        Row {
            id: tabsRow
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            height: 40
            spacing: 4
            layoutDirection: Qt.RightToLeft
            Repeater {
                model: root.tabTitles
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    width: (tabsRow.width - 20) / 6
                    height: 36
                    radius: 18
                    color: root.tab === index ? T.sel : (tabMa.containsMouse ? T.selBg : "transparent")
                    border.color: root.tab === index ? T.sel : T.goldSoft
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: root.tab === index ? "#FFF8E8" : T.ink
                        font.family: T.fontUI
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: tabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        property var navRoot: root
                        onClicked: { tabMa.navRoot.tab = tabMa.parent.index; tabMa.navRoot.rebuild(); }
                    }
                }
            }
        }

        // القائمة
        ListView {
            id: list
            anchors.top: tabsRow.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            clip: true
            model: root.model

            delegate: Rectangle {
                id: bmRow
                required property var modelData
                required property int index
                width: list.width
                height: 58
                color: index === root.currentIdx() ? T.selBg : (rowMa.containsMouse ? "#18845D22" : "transparent")
                Rectangle { anchors.bottom: parent.bottom; width: parent.width - 24; x: 12; height: 1; color: T.edge; opacity: 0.4 }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.t
                    color: index === root.currentIdx() ? T.gold : T.ink
                    font.family: T.fontUI
                    font.pixelSize: 17
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.tab === 5 ? 46 : 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.tab === 5 ? parent.width - 160 : undefined
                    elide: Text.ElideRight
                    text: parent.modelData.s + (root.tab === 5 ? "" : ("  ·  ص " + U.ar(parent.modelData.p)))
                    color: T.inkFaint
                    font.family: T.fontUI
                    font.pixelSize: 12
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.jump(bmRow.modelData.p);
                        root.close();
                    }
                }
                // زر إزالة العلامة (تبويب العلامات فقط) — فوق منطقة النقر
                Rectangle {
                    visible: root.tab === 5
                    z: 10
                    width: 30; height: 30; radius: 15
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: delMa.containsMouse ? "#33A93B2E" : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: delMa.containsMouse ? "#A93B2E" : T.inkFaint; font.pixelSize: 13 }
                    MouseArea {
                        id: delMa
                        anchors.fill: parent
                        hoverEnabled: true
                        z: 10
                        cursorShape: Qt.PointingHandCursor
                        onPressed: function (mouse) { mouse.accepted = true; }
                        onClicked: function (mouse) {
                            mouse.accepted = true;
                            root.bookmarkRemove(bmRow.modelData.bm);
                        }
                    }
                }
            }
        }

        // رسالة فارغة لتبويب العلامات
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: tabsRow.bottom
            anchors.topMargin: 96
            width: parent.width - 70
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.7
            visible: root.tab === 5 && list.count === 0
            text: "لا توجد علامات محفوظة بعد.\nأثناء القراءة اضغط زر «علامة» أعلى الشاشة أو Ctrl+B\nلحفظ موضعك — الصفحة أو الآية اللي واقف عندها."
            color: T.inkFaint
            font.family: T.fontUI
            font.pixelSize: 14
        }
    }
}
