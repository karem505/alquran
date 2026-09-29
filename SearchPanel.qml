import QtQuick
import "theme.js" as T
import "utils.js" as U

// لوحة البحث: كلمة/اسم سورة/حرف/رقم صفحة — ضغط نتيجة ينقلك للصفحة
Item {
    id: root
    visible: false

    property var qdata: null
    property int totalPages: 604

    signal jump(int page, var info)
    signal closed()

    function pageForSura(i) { return root.qdata.q.surahs[i - 1].p; }

    function arToInt(s) {
        var m = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9" };
        var o = "";
        for (var i = 0; i < s.length; i++) o += (m[s[i]] !== undefined ? m[s[i]] : s[i]);
        return parseInt(o, 10);
    }

    function open() {
        visible = true;
        input.text = "";
        list.model = [];
        input.forceActiveFocus();
    }
    function close() {
        visible = false;
        root.closed();
    }

    function title(m) {
        if (m.kind === "page") return m.label;
        if (m.kind === "sura") return "سورة " + m.name;
        return m.sName + " · الآية " + U.ar(m.a) + " — ص " + U.ar(m.page);
    }

    function runSearch() {
        if (!root.qdata || !root.qdata.ready) return;
        var q = input.text.trim();
        var res = [];
        if (q.length === 0) { list.model = res; return; }
        if (/^[0-9٠-٩]+$/.test(q)) {
            var n = root.arToInt(q);
            if (n >= 1 && n <= root.totalPages)
                res.push({ kind: "page", page: n, label: "الانتقال إلى صفحة " + U.ar(n) });
            if (n >= 1 && n <= 114)
                res.push({ kind: "sura", page: root.pageForSura(n), name: root.qdata.q.surahs[n - 1].name });
        }
        res = res.concat(root.qdata.search(q, 150));
        list.model = res;
    }

    function jumpTo(m) {
        if (!m) return;
        var info = null;
        if (m.kind === "aya") info = { sName: m.sName, a: m.a, page: m.page };
        root.close();
        root.jump(m.page, info);
    }
    function jumpFirst() {
        if (list.model && list.model.length > 0) root.jumpTo(list.model[0]);
    }

    // خلفية معتمة
    Rectangle {
        anchors.fill: parent
        color: "#40000000"
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // اللوح
    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(20, parent.height * 0.06)
        width: Math.min(800, parent.width * 0.92)
        height: Math.min(parent.height * 0.82, inputBox.height + list.contentHeight + 46)
        radius: 14
        color: T.panel
        border.color: T.goldSoft
        border.width: 1

        // حقل الإدخال
        Rectangle {
            id: inputBox
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14
            height: 52
            radius: 10
            color: T.paper
            border.color: T.goldSoft
            border.width: 1

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                color: T.ink
                font.family: T.fontUI
                font.pixelSize: 18
                selectionColor: T.gold
                selectedTextColor: "#FFF8E8"
                onTextChanged: debounce.restart()
                onAccepted: root.jumpFirst()
            }
            Text {
                visible: input.text.length === 0
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "ابحث بكلمة أو اسم سورة أو حرف… أو رقم صفحة"
                color: T.inkFaint
                font.family: T.fontUI
                font.pixelSize: 16
            }
        }
        Timer { id: debounce; interval: 130; onTriggered: root.runSearch() }

        // النتائج
        ListView {
            id: list
            anchors.top: inputBox.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            clip: true
            spacing: 2
            model: []

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: modelData.kind === "aya" ? 64 : 44
                radius: 8
                color: rowMa.containsMouse ? T.selBg : "transparent"

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: modelData.kind === "aya" ? 8 : 0
                    anchors.verticalCenter: modelData.kind === "aya" ? undefined : parent.verticalCenter
                    text: root.title(parent.modelData)
                    color: T.gold
                    font.family: T.fontUI
                    font.pixelSize: 15
                }
                Text {
                    visible: parent.modelData.kind === "aya"
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.top: parent.top
                    anchors.topMargin: 30
                    text: parent.modelData.text
                    color: T.ink
                    font.family: T.fontUI
                    font.pixelSize: 15
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                }
                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.jumpTo(parent.modelData)
                }
            }
        }
    }
}
