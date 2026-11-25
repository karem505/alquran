import QtQuick
import "theme.js" as T
import "utils.js" as U

// الشريط العلوي: معلومات حية (السورة/الجزء/الحزب/الربع/الصفحة) + أزرار
Item {
    id: root
    height: 56

    property var loc: null
    property int page: 1
    property int totalPages: 604
    property bool bookmarked: false
    property bool tasmeeOn: false
    property bool listenOn: false      // مشغّل السماع مفتوح
    property bool listenBusy: false    // الشيخ يقرأ/يجهّز الآن

    signal openMenu()
    signal openSearch()
    signal addBookmark()
    signal toggleTasmee()
    signal toggleListen()

    Rectangle { anchors.fill: parent; color: "transparent" }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: T.edge; opacity: 0.7 }

    // ---------- يمين: الأزرار + اسم السورة ----------
    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        layoutDirection: Qt.RightToLeft
        Row {
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            // زر الفهرس
            Rectangle {
                width: menuTxt.implicitWidth + 22
                height: 32
                radius: 16
                color: menuMa.containsMouse ? T.selBg : "transparent"
                border.color: T.goldSoft
                border.width: 1
                Text { id: menuTxt; anchors.centerIn: parent; text: "الفهرس"; color: T.gold; font.family: T.fontUI; font.pixelSize: 15 }
                MouseArea { id: menuMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openMenu() }
            }
            // زر البحث
            Rectangle {
                width: searchTxt.implicitWidth + 22
                height: 32
                radius: 16
                color: searchMa.containsMouse ? T.selBg : "transparent"
                border.color: T.goldSoft
                border.width: 1
                Text { id: searchTxt; anchors.centerIn: parent; text: "بحث"; color: T.gold; font.family: T.fontUI; font.pixelSize: 15 }
                MouseArea { id: searchMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSearch() }
            }
            // زر التسميع — Ctrl+T
            Rectangle {
                width: tsTxt.implicitWidth + 22
                height: 32
                radius: 16
                color: root.tasmeeOn ? T.gold : (tsMa.containsMouse ? T.selBg : "transparent")
                border.color: root.tasmeeOn ? T.gold : T.goldSoft
                border.width: 1
                Text { id: tsTxt; anchors.centerIn: parent; text: root.tasmeeOn ? "العودة للقراءة" : "تسميع"; color: root.tasmeeOn ? "#FFFFFF" : T.gold; font.family: T.fontUI; font.pixelSize: 15 }
                MouseArea { id: tsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleTasmee() }
            }
            // زر السماع (الشيخ الحصري) — P يبدأ/يوقف
            Rectangle {
                width: lsTxt.implicitWidth + 22
                height: 32
                radius: 16
                color: root.listenOn ? "#1B7A3A" : (lsMa.containsMouse ? T.selBg : "transparent")
                border.color: (root.listenOn || root.listenBusy) ? "#1B7A3A" : T.goldSoft
                border.width: root.listenBusy ? 1.6 : 1
                Text { id: lsTxt; anchors.centerIn: parent; text: "السماع"; color: root.listenOn ? "#FFFFFF" : (root.listenBusy ? "#1B7A3A" : T.gold); font.family: T.fontUI; font.pixelSize: 15 }
                MouseArea { id: lsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleListen() }
            }
            // زر العلامة (حفظ الموضع) — Ctrl+B
            Rectangle {
                width: markTxt.implicitWidth + 22
                height: 32
                radius: 16
                color: markMa.containsMouse ? T.selBg : (root.bookmarked ? T.selBg : "transparent")
                border.color: root.bookmarked ? T.gold : T.goldSoft
                border.width: root.bookmarked ? 1.6 : 1
                Text { id: markTxt; anchors.centerIn: parent; text: "علامة"; color: T.gold; font.family: T.fontUI; font.pixelSize: 15 }
                MouseArea {
                    id: markMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addBookmark()
                }
            }
        }
        // اسم السورة
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.loc ? ("سورة " + root.loc.suraName) : ""
            color: T.ink
            font.family: T.fontTitle
            font.pixelSize: 21
        }
    }

    // ---------- الوسط: الجزء/الحزب/الربع ----------
    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        x: Math.min((root.width - width) / 2, actions.x - width - 12)
        visible: x >= pageLabel.x + pageLabel.width + 12
        text: root.loc
              ? ("الجزء " + U.ar(root.loc.juz) + "  ·  الحزب " + U.ar(root.loc.hizb) + "  ·  الربع " + U.ar(root.loc.rubInHizb))
              : ""
        color: T.inkSoft
        font.family: T.fontUI
        font.pixelSize: 15
    }

    // ---------- يسار: الصفحة ----------
    Text {
        id: pageLabel
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "صفحة " + U.ar(root.page) + " / " + U.ar(root.totalPages)
        color: T.inkSoft
        font.family: T.fontUI
        font.pixelSize: 14
    }
}
