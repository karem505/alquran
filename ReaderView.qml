import QtQuick
import "theme.js" as T
import "utils.js" as U

// عرض الصفحتين المتجاورتين (يمين: فردي — يسار: زوجي) كما في المصحف المطبوع
// + علامة موضع الآية + بطاقة النتيجة في الفراغ الجانبي بخط إرشادي + تلميحات التقليب عند الحاجة
Item {
    id: root

    property int rightPage: 1          // الصفحة اليمنى (فردية)
    property int totalPages: 604
    property string pagesDir: ""       // مجلد الصور
    property var found: null           // {s, sName, a, page} آية مقصودة من البحث
    property var foundPos: null        // {x, y, w, h} موضع الآية على الصورة الأصلية
    readonly property int leftPage: rightPage + 1

    signal forward()
    signal backward()
    signal jump(int page)

    // نسبة عرض/ارتفاع صفحة المصحف
    readonly property real pageAR: 0.6697
    readonly property real gap: Math.max(14, width * 0.012)

    // ---------- حدود وأبعاد ----------
    readonly property real padTop: 10
    readonly property real padBottom: 40   // مكان أرقام الصفحات
    readonly property real availH: height - padTop - padBottom
    readonly property real maxPageW: (width - gap - 40) / 2
    readonly property real pageH: Math.min(availH, maxPageW / pageAR)
    readonly property real pageW: pageH * pageAR

    // الفراغ الجانبي (يمين ويسار الصفحتين)
    readonly property real sideSpace: Math.max(0, (width - (2 * pageW + gap)) / 2 - 10)
    readonly property bool foundOnLeft: found !== null && found.page === leftPage
    readonly property bool foundOnRight: found !== null && found.page === rightPage
    readonly property bool sideCard: found !== null && sideSpace >= 150

    // موضع العلامة في إحداثيات النافذة (لرسم الخط الإرشادي)
    readonly property real markX: {
        if (foundPos === null || found === null) return -1;
        if (foundOnRight) return rightRect.x + (foundPos.x / foundPos.w) * rightRect.width;
        if (foundOnLeft) return leftRect.x + (foundPos.x / foundPos.w) * leftRect.width;
        return -1;
    }
    readonly property real markY: {
        if (foundPos === null || found === null) return -1;
        if (foundOnRight) return rightRect.y + (foundPos.y / foundPos.h) * rightRect.height;
        if (foundOnLeft) return leftRect.y + (foundPos.y / foundPos.h) * leftRect.height;
        return -1;
    }

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

        // علامة موضع الآية المقصودة
        Item {
            id: markR
            visible: root.foundPos !== null && root.found !== null && root.found.page === root.rightPage
            width: 44
            height: 44
            x: root.foundPos ? (root.foundPos.x / root.foundPos.w) * rightRect.width - width / 2 : 0
            y: root.foundPos ? (root.foundPos.y / root.foundPos.h) * rightRect.height - height / 2 : 0
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: "transparent"
                border.color: T.gold
                border.width: 2.5
            }
            Rectangle {
                anchors.centerIn: parent
                width: 54
                height: 54
                radius: 27
                color: "transparent"
                border.color: T.gold
                border.width: 2
                SequentialAnimation on opacity {
                    running: markR.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.65; duration: 850; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 0.0; duration: 850; easing.type: Easing.InQuad }
                }
            }
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

        // علامة موضع الآية المقصودة
        Item {
            id: markL
            visible: root.foundPos !== null && root.found !== null && root.found.page === root.leftPage
            width: 44
            height: 44
            x: root.foundPos ? (root.foundPos.x / root.foundPos.w) * leftRect.width - width / 2 : 0
            y: root.foundPos ? (root.foundPos.y / root.foundPos.h) * leftRect.height - height / 2 : 0
            Rectangle {
                anchors.centerIn: parent
                width: 40
                height: 40
                radius: 20
                color: "transparent"
                border.color: T.gold
                border.width: 2.5
            }
            Rectangle {
                anchors.centerIn: parent
                width: 54
                height: 54
                radius: 27
                color: "transparent"
                border.color: T.gold
                border.width: 2
                SequentialAnimation on opacity {
                    running: markL.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.65; duration: 850; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 0.0; duration: 850; easing.type: Easing.InQuad }
                }
            }
        }
    }

    // ---------- الخط الإرشادي: من البطاقة الجانبية إلى موضع الآية (شبه شفاف) ----------
    Canvas {
        id: guideLine
        anchors.fill: parent
        visible: root.sideCard && cardSide.visible
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.sideCard || root.markX < 0 || root.markY < 0)
                return;
            var x0 = (cardSide.x + (root.foundOnLeft ? 0 : cardSide.width));
            var y0 = cardSide.y + cardSide.height / 2;
            var x1 = root.markX;
            var y1 = root.markY;
            ctx.strokeStyle = "rgba(169, 131, 54, 0.35)";
            ctx.lineWidth = 1.6;
            ctx.beginPath();
            var midx = (x0 + x1) / 2;
            ctx.moveTo(x0, y0);
            ctx.bezierCurveTo(midx, y0, midx, y1, x1, y1);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(x1, y1, 3.2, 0, Math.PI * 2);
            ctx.fillStyle = "rgba(169, 131, 54, 0.55)";
            ctx.fill();
        }
    }
    Connections {
        target: root
        function onFoundChanged() { settle.restart(); }
        function onFoundPosChanged() { settle.restart(); }
        function onRightPageChanged() { settle.restart(); }
        function onWidthChanged() { settle.restart(); }
        function onHeightChanged() { settle.restart(); }
    }
    Timer {
        id: settle
        interval: 60
        onTriggered: guideLine.requestPaint()
    }

    // ---------- البطاقة الجانبية في الفراغ (عند الحاجة) ----------
    Rectangle {
        id: cardSide
        visible: root.sideCard
        x: root.foundOnLeft ? (root.width - width - 14) : 14
        y: {
            var cy = root.markY - height / 2;
            return Math.max(8, Math.min(cy, root.height - height - 8));
        }
        width: Math.min(216, Math.max(150, root.sideSpace))
        height: col.implicitHeight + 26
        radius: 12
        color: T.panel
        border.color: T.goldSoft
        border.width: 1
        MouseArea { anchors.fill: parent }   // تستهلك النقر حتى لا يقلب الصفحة

        Column {
            id: col
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: root.found ? ("﴿ سورة " + root.found.sName + " ﴾") : ""
                color: T.gold
                font.family: T.fontTitle
                font.pixelSize: 16
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Rectangle {
                width: Math.min(parent.width, 150)
                height: 1
                color: T.goldSoft
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: root.found ? ("الآية " + U.ar(root.found.a) + " · الصفحة " + U.ar(root.found.page)) : ""
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 13
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ---------- بطاقة سفلية احتياطية (لو الفراغ الجانبي ضيق) ----------
    Rectangle {
        id: cardBottom
        visible: root.found !== null && !root.sideCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: Math.min(parent.width * 0.78, cardText.implicitWidth + 60)
        height: Math.max(34, cardText.implicitHeight + 14)
        radius: 8
        color: T.panel
        border.color: T.goldSoft
        border.width: 1
        MouseArea { anchors.fill: parent }

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

    // ---------- مناطق الضغط: اليسار = التالي، اليمين = السابق + تلميح عند الحاجة ----------
    MouseArea {
        id: leftZone
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.horizontalCenter
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.forward()

        Rectangle {
            width: 2
            height: parent.height * 0.3
            radius: 1
            color: T.gold
            opacity: leftZone.containsMouse ? 0.4 : 0.0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 7
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Text {
            text: "‹"
            color: T.gold
            font.pixelSize: 30
            opacity: leftZone.containsMouse ? 0.55 : 0.0
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 16
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
    }
    MouseArea {
        id: rightZone
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.horizontalCenter
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.backward()

        Rectangle {
            width: 2
            height: parent.height * 0.3
            radius: 1
            color: T.gold
            opacity: rightZone.containsMouse ? 0.4 : 0.0
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 7
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
        Text {
            text: "›"
            color: T.gold
            font.pixelSize: 30
            opacity: rightZone.containsMouse ? 0.55 : 0.0
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 16
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }
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
}
