import QtQuick
import "theme.js" as T
import "utils.js" as U

// مشغّل السماع الجانبي: قراءة الشيخ الحصري (بلا إنترنت) على نفس الصفحتين المرندرتين
Rectangle {
    id: lp
    property var tv: null
    readonly property var eng: tv ? tv.engine : null
    readonly property string st: eng ? eng.listenSt : "idle"
    readonly property bool busy: eng ? eng.listening : false
    readonly property color green: "#1B7A3A"

    color: T.panel
    radius: 14
    border.color: T.goldSoft
    border.width: 1

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool on: false
        property bool enabledX: true
        property color tint: T.gold
        signal clicked()
        width: pillT.implicitWidth + 24
        height: 34
        radius: 17
        opacity: enabledX ? 1 : 0.45
        color: on ? tint : (pma.containsMouse ? T.selBg : "transparent")
        border.color: on ? tint : T.goldSoft
        border.width: 1
        Text { id: pillT; anchors.centerIn: parent; text: pill.label; color: pill.on ? "#FFFFFF" : T.ink; font.family: T.fontUI; font.pixelSize: 14 }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; enabled: pill.enabledX; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
    }
    component Stepper: Row {
        id: sp
        property int value: 1
        property int minV: 1
        property int maxV: 286
        property string caption: ""
        signal edited(int v)
        spacing: 6
        layoutDirection: Qt.RightToLeft
        Text { text: sp.caption; color: T.inkSoft; font.family: T.fontUI; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter; width: 44; horizontalAlignment: Text.AlignRight }
        Rectangle {
            width: 28; height: 28; radius: 14; color: plusMa.containsMouse ? T.selBg : "transparent"; border.color: T.goldSoft
            Text { anchors.centerIn: parent; text: "+"; color: T.gold; font.pixelSize: 16 }
            MouseArea { id: plusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sp.edited(Math.min(sp.maxV, sp.value + 1)) }
        }
        Rectangle {
            width: 48; height: 30; radius: 7; color: T.bg; border.color: T.goldSoft
            TextInput {
                id: numberEntry
                anchors.fill: parent; anchors.margins: 3
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                font.family: T.fontUI; font.pixelSize: 15; color: T.ink
                selectByMouse: true; maximumLength: 3
                validator: RegularExpressionValidator { regularExpression: /[0-9٠-٩۰-۹]{0,3}/ }
                Accessible.name: sp.caption
                text: U.ar(sp.value)
                onAccepted: {
                    var x = Number(text.replace(/[٠-٩]/g, function(c) { return String(c.charCodeAt(0) - 1632); })
                                       .replace(/[۰-۹]/g, function(c) { return String(c.charCodeAt(0) - 1776); }));
                    if (text.length && x >= sp.minV && x <= sp.maxV && x !== sp.value) sp.edited(x);
                    focus = false;
                }
                onActiveFocusChanged: {
                    if (activeFocus) selectAll();
                    else text = Qt.binding(function() { return U.ar(sp.value); });
                }
            }
        }
        Rectangle {
            width: 28; height: 28; radius: 14; color: minusMa.containsMouse ? T.selBg : "transparent"; border.color: T.goldSoft
            Text { anchors.centerIn: parent; text: "−"; color: T.gold; font.pixelSize: 16 }
            MouseArea { id: minusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sp.edited(Math.max(sp.minV, sp.value - 1)) }
        }
    }

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
            text: "السماع"
            color: T.ink
            font.family: T.fontTitle
            font.pixelSize: 22
        }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                width: 10; height: 10; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: lp.st === "playing" ? lp.green : lp.st === "error" ? "#A93B2E" : (lp.busy ? T.goldBright : T.edge)
                SequentialAnimation on opacity {
                    running: lp.busy
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 13
                text: lp.st === "starting" ? "جارٍ التشغيل" : lp.st === "indexing" ? "جارٍ الفهرسة"
                    : lp.st === "playing" ? "يُقرأ الآن" : lp.st === "error" ? "تعذّر السماع" : "متوقف"
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: T.edge; opacity: 0.6 }
    }

    Flickable {
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
            width: parent.width
            spacing: 12

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                color: T.inkSoft
                font.family: T.fontUI
                font.pixelSize: 13
                text: "استمع إلى تلاوة الشيخ محمود خليل الحصري على الصفحتين نفسيهما؛ الكلمة التي يقرؤها تُلوَّن بالأخضر."
            }

            // ---- اختيار السورة والآية ----
            Row {
                layoutDirection: Qt.RightToLeft
                anchors.right: parent.right
                spacing: 10
                Stepper {
                    caption: "السورة"
                    value: lp.tv ? lp.tv.lSura : 1
                    maxV: 114
                    onEdited: function (v) {
                        lp.tv.lSura = v;
                        lp.tv.lAyahNo = 1;
                        if (lp.busy) lp.tv.listenPlay(v, 1);
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: lp.tv ? lp.tv.suraName(lp.tv.lSura) : ""
                    color: T.ink
                    font.family: T.fontTitle
                    font.pixelSize: 17
                }
            }
            Stepper {
                anchors.right: parent.right
                caption: "الآية"
                value: lp.tv ? lp.tv.lAyahNo : 1
                maxV: lp.tv ? Math.max(1, lp.tv.ayaCount(lp.tv.lSura)) : 1
                onEdited: function (v) { if (lp.busy) lp.tv.listenPlay(lp.tv.lSura, v); else lp.tv.lAyahNo = v; }
            }
            Flow {
                width: parent.width
                layoutDirection: Qt.RightToLeft
                spacing: 8
                Pill {
                    label: "من الصفحة الحالية"
                    onClicked: {
                        lp.tv.listenFromPage();
                        if (lp.busy) lp.tv.listenPlay(lp.tv.lSura, lp.tv.lAyahNo);
                    }
                }
                Pill {
                    label: "تكرار الآية"
                    on: lp.tv ? lp.tv.lRepeat : false
                    onClicked: lp.tv.listenSetRepeat(!lp.tv.lRepeat)
                }
            }

            // ---- أزرار التحكم ----
            Row {
                layoutDirection: Qt.RightToLeft
                anchors.right: parent.right
                spacing: 8
                Rectangle {
                    id: playBtn
                    width: playT.implicitWidth + 44
                    height: 44
                    radius: 22
                    color: lp.busy ? "#a93b2e" : lp.green
                    Text {
                        id: playT
                        anchors.centerIn: parent
                        text: lp.busy ? "إيقاف" : "تشغيل"
                        color: "#FFFFFF"
                        font.family: T.fontUI
                        font.pixelSize: 16
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: lp.tv.listenToggleSel() }
                }
                Pill { label: "الآية التالية"; height: 44; radius: 22; onClicked: lp.tv.listenStep(1) }
                Pill { label: "الآية السابقة"; height: 44; radius: 22; onClicked: lp.tv.listenStep(-1) }
            }

            // ---- الحالة ----
            Rectangle {
                width: parent.width
                height: stT.implicitHeight + 20
                radius: 10
                color: lp.st === "error" ? "#14A93B2E" : "#141B7A3A"
                border.color: lp.st === "error" ? "#A93B2E" : "#661B7A3A"
                visible: lp.st !== "idle" && lp.st !== "stopped"
                Text {
                    id: stT
                    anchors.fill: parent
                    anchors.margins: 10
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                    font.family: T.fontUI
                    font.pixelSize: 14
                    color: lp.st === "error" ? "#A93B2E" : "#1B5E2F"
                    text: {
                        if (!lp.eng) return "";
                        if (lp.st === "error") return lp.eng.listenMsg !== "" ? lp.eng.listenMsg : "تعذّر تشغيل السماع. تأكد من وجود ملفات التلاوة ثم أعد المحاولة.";
                        if (lp.st === "starting") return "جارٍ تشغيل المحرك…";
                        if (lp.st === "indexing") return "جارٍ فهرسة التلاوة على جهازك (قد يستغرق ذلك لحظات في أول مرة)…";
                        return "يقرأ الشيخ: سورة " + lp.tv.suraName(lp.eng.listenS) + " — الآية " + U.ar(lp.eng.listenA);
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                color: T.inkFaint
                font.family: T.fontUI
                font.pixelSize: 12
                text: "يُكتم المايك أثناء السماع حتى لا يلتقط صوت الشيخ. اضغط P في أي وقت للتشغيل أو الإيقاف."
            }

            // ---- خروج ----
            Rectangle {
                anchors.right: parent.right
                width: closeT.implicitWidth + 36
                height: 38
                radius: 19
                color: closeMa.containsMouse ? T.selBg : "transparent"
                border.color: T.goldSoft
                Text {
                    id: closeT
                    anchors.centerIn: parent
                    text: "إغلاق المشغّل"
                    color: T.ink
                    font.family: T.fontUI
                    font.pixelSize: 15
                }
                MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lp.tv.listenCloseRequested() }
            }
        }
    }
}
