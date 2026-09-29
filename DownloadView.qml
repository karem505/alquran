import QtQuick
import "theme.js" as T
import "utils.js" as U

// شاشة أول تشغيل: تنزيل صفحات المصحف (٦٠٤ صفحات — لمرة واحدة)
Rectangle {
    id: dv
    property int count: 0
    property int total: 604
    property bool failed: false
    signal retry()

    color: T.bg

    Column {
        anchors.centerIn: parent
        spacing: 24

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "القرآن الكريم"
            color: T.gold
            font.family: T.fontUI
            font.pixelSize: 46
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: dv.failed ? "تعذّر تنزيل صفحات المصحف — تأكد من اتصال الإنترنت ثم أعد المحاولة"
                            : "جارٍ تنزيل صفحات مصحف المدينة النبوية (٦٠٤ صفحات — لمرة واحدة فقط)"
            color: dv.failed ? "#A93B2E" : T.inkFaint
            font.family: T.fontUI
            font.pixelSize: 16
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 460; height: 14; radius: 7
            color: T.panel
            border.color: T.goldSoft
            border.width: 1
            Rectangle {
                width: Math.max(0, Math.min(parent.width, parent.width * (dv.count / dv.total)))
                height: parent.height
                radius: 7
                color: T.gold
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !dv.failed
            text: U.ar(dv.count) + " / " + U.ar(dv.total) + "  (" + Math.round(dv.count * 100 / dv.total) + "٪)"
            color: T.inkFaint
            font.family: T.fontUI
            font.pixelSize: 15
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: dv.failed
            width: 170; height: 44; radius: 22
            color: retMa.containsMouse ? T.gold : T.panel
            border.color: T.goldSoft
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "إعادة المحاولة"
                color: retMa.containsMouse ? "#FFFFFF" : T.ink
                font.family: T.fontUI
                font.pixelSize: 16
            }
            MouseArea {
                id: retMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: dv.retry()
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !dv.failed
            text: "تُنزَّل الصفحات إلى مجلد بيانات المستخدم وتُستخدم بلا إنترنت بعد ذلك"
            color: T.edge
            font.family: T.fontUI
            font.pixelSize: 12
        }
    }
}
