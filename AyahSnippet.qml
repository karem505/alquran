import QtQuick
import "theme.js" as T
import "utils.js" as U

// مقطع آية مرسوم بخط صفحتها (QPC V2) مع تعليم الكلمات المختلفة — للوحة المتشابهات
// view: {s, a, sura, page, g: [[glyph, page, t0, diff], ...], text}
Item {
    id: sn
    property var view: null
    property string fontsDir: ""
    property color accent: "#b3261e"
    property string tag: ""              // «المقروء» / «المتوقع» ...
    property real glyphSize: 27
    signal clicked(int s, int a, int page)

    implicitHeight: col.implicitHeight
    width: parent ? parent.width : 300

    function fontUrl(p) { return "file://" + encodeURI(sn.fontsDir + "/p" + p + ".woff2"); }

    Column {
        id: col
        width: parent.width
        spacing: 4
        Row {
            width: parent.width
            layoutDirection: Qt.RightToLeft
            spacing: 8
            Rectangle {
                visible: sn.tag !== ""
                width: tagT.implicitWidth + 14
                height: 20
                radius: 10
                color: Qt.rgba(sn.accent.r, sn.accent.g, sn.accent.b, 0.12)
                Text { id: tagT; anchors.centerIn: parent; text: sn.tag; color: sn.accent; font.family: T.fontUI; font.pixelSize: 11 }
            }
            Text {
                text: sn.view ? ("سورة " + sn.view.sura + " · الآية " + U.ar(sn.view.a) + " · ص " + U.ar(sn.view.page)) : ""
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Flow {
            id: flow
            width: parent.width
            layoutDirection: Qt.RightToLeft
            spacing: 1
            Repeater {
                model: sn.view ? sn.view.g : []
                delegate: Item {
                    id: gw
                    required property var modelData
                    readonly property bool diff: modelData[3] === 1
                    readonly property bool isEnd: modelData[2] === 0
                    width: gt.implicitWidth + 2
                    height: sn.glyphSize * 1.55
                    FontLoader { id: fl; source: sn.fontUrl(gw.modelData[1]) }
                    Rectangle {
                        visible: gw.diff
                        anchors.fill: parent
                        anchors.topMargin: 3
                        anchors.bottomMargin: 2
                        radius: 6
                        color: Qt.rgba(sn.accent.r, sn.accent.g, sn.accent.b, 0.13)
                    }
                    Text {
                        id: gt
                        anchors.centerIn: parent
                        text: fl.status === FontLoader.Ready ? gw.modelData[0] : ""
                        font.family: fl.name
                        font.pixelSize: sn.glyphSize
                        color: gw.diff ? sn.accent : (gw.isEnd ? T.gold : T.ink)
                        renderType: Text.QtRendering
                    }
                }
            }
        }
        // احتياط: لو خط الصفحة غير متاح، النص العثماني (Tanzil)
        Text {
            visible: sn.view !== null && flow.children.length <= 1
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignRight
            text: sn.view ? sn.view.text : ""
            color: T.ink
            font.family: T.fontTitle
            font.pixelSize: 18
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (sn.view) sn.clicked(sn.view.s, sn.view.a, sn.view.page)
    }
}
