import QtQuick
import "theme.js" as T
import "utils.js" as U

// عرض الصفحتين المتجاورتين (يمين: فردي — يسار: زوجي) كما في المصحف المطبوع
Item {
    id: root

    property int rightPage: 1          // الصفحة اليمنى (فردية)
    property int totalPages: 604
    property string pagesDir: ""       // مجلد الصور
    property var found: null           // {sName, a, page} آية مقصودة من البحث (بطاقة سفلية)
    readonly property int leftPage: rightPage + 1

    signal forward()
    signal backward()
    signal jump(int page)

    // نسبة عرض/ارتفاع صفحة المصحف (تُضبط بعد توليد الصور)
    readonly property real pageAR: 0.6697
    readonly property real gap: Math.max(14, width * 0.012)

    // ---------- حدود وأبعاد ----------
    readonly property real padTop: 10
    readonly property real padBottom: 40   // مكان أرقام الصفحات والبطاقة
    readonly property real availH: height - padTop - padBottom
    readonly property real maxPageW: (width - gap - 40) / 2
    readonly property real pageH: Math.min(availH, maxPageW / pageAR)
    readonly property real pageW: pageH * pageAR

    function src(p) {
        var n = p < 10 ? "00" + p : (p < 100 ? "0" + p : "" + p);
        var base = String(root.pagesDir);
        if (base.indexOf("file://") === 0)
            base = base.substring(7);
        return "file://" + encodeURI(base) + "/p" + n + ".jpg";
    }

    // ---------- الصفحة اليمنى ----------
    Rectangle {
        id: rightRect
        width: root.pageW
        height: root.pageH
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: (root.padTop - root.padBottom) / 2
        anchors.left: parent.horizontalCenter
        anchors.leftMargin: root.gap / 2
        color: T.paper
        border.color: T.edge
        border.width: 1
        radius: 3
        clip: true

        Image {
            id: rightImg
            anchors.fill: parent
            anchors.margins: 1
            source: root.src(root.rightPage)
            asynchronous: true
            smooth: true
            mipmap: true
            cache: false
        }
    }

    // ---------- الصفحة اليسرى ----------
    Rectangle {
        id: leftRect
        width: root.pageW
        height: root.pageH
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: (root.padTop - root.padBottom) / 2
        anchors.right: parent.horizontalCenter
        anchors.rightMargin: root.gap / 2
        color: T.paper
        border.color: T.edge
        border.width: 1
        radius: 3
        clip: true

        Image {
            id: leftImg
            anchors.fill: parent
            anchors.margins: 1
            source: root.leftPage <= root.totalPages ? root.src(root.leftPage) : ""
            asynchronous: true
            smooth: true
            mipmap: true
            cache: false
        }
    }

    // ---------- أرقام الصفحات ----------
    Text {
        text: U.ar(root.rightPage)
        color: T.gold
        font.family: T.fontTitle
        font.pixelSize: 17
        anchors.horizontalCenter: rightRect.horizontalCenter
        anchors.top: rightRect.bottom
        anchors.topMargin: 7
    }
    Text {
        visible: root.leftPage <= root.totalPages
        text: U.ar(root.leftPage)
        color: T.gold
        font.family: T.fontTitle
        font.pixelSize: 17
        anchors.horizontalCenter: leftRect.horizontalCenter
        anchors.top: leftRect.bottom
        anchors.topMargin: 7
    }

    // ---------- مناطق الضغط: اليسار = التالي، اليمين = السابق (اتجاه القراءة) ----------
    MouseArea {
        // النصف الأيسر = التقدم
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.horizontalCenter
        cursorShape: Qt.PointingHandCursor
        onClicked: root.forward()
    }
    MouseArea {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.horizontalCenter
        cursorShape: Qt.PointingHandCursor
        onClicked: root.backward()
    }

    // ---------- العجلة ----------
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (ev) {
            if (ev.angleDelta.y < 0) root.forward();
            else if (ev.angleDelta.y > 0) root.backward();
        }
    }

    // ---------- لوحة المفاتيح ----------
    focus: true
    Keys.onPressed: function (ev) {
        switch (ev.key) {
        case Qt.Key_Left: case Qt.Key_Down: case Qt.Key_PageDown: case Qt.Key_Space:
            root.forward(); ev.accepted = true; break;
        case Qt.Key_Right: case Qt.Key_Up: case Qt.Key_PageUp:
            root.backward(); ev.accepted = true; break;
        case Qt.Key_Home: root.jump(1); ev.accepted = true; break;
        case Qt.Key_End: root.jump(603); ev.accepted = true; break;
        }
    }

    // ---------- بطاقة الآية المقصودة ----------
    Rectangle {
        id: card
        visible: root.found !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: Math.min(parent.width * 0.78, cardText.implicitWidth + 60)
        height: Math.max(34, cardText.implicitHeight + 14)
        radius: 8
        color: T.panel
        border.color: T.goldSoft
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "﴿"
                color: T.gold
                font.family: T.fontDecor
                font.pixelSize: 20
            }
            Text {
                id: cardText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(root.width * 0.7, implicitWidth)
                text: root.found ? (root.found.sName + " · الآية " + U.ar(root.found.a)) : ""
                color: T.ink
                font.family: T.fontUI
                font.pixelSize: 16
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "﴾"
                color: T.gold
                font.family: T.fontDecor
                font.pixelSize: 20
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "الصفحة " + (root.found ? U.ar(root.found.page) : "")
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 13
            }
        }
    }
}
