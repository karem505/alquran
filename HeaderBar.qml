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

    signal openMenu()
    signal openSearch()
    signal addBookmark()

    Rectangle { anchors.fill: parent; color: "transparent" }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: T.edge; opacity: 0.7 }

    // ---------- يمين: الأزرار + اسم السورة ----------
    Row {
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
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        text: root.loc
              ? ("الجزء " + U.ar(root.loc.juz) + "  ·  الحزب " + U.ar(root.loc.hizb) + "  ·  الربع " + U.ar(root.loc.rubInHizb))
              : ""
        color: T.inkSoft
        font.family: T.fontUI
        font.pixelSize: 15
    }

    // ---------- يسار: الصفحة ----------
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "صفحة " + U.ar(root.page) + " / " + U.ar(root.totalPages)
        color: T.inkSoft
        font.family: T.fontUI
        font.pixelSize: 14
    }
}
