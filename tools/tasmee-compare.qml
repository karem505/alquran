import QtQuick
import ".."

// أداة مقارنة (بيئة qml العادية، بلا Quickshell): صفحة مرندرة بجانب الصورة الأصلية
// QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml tools/tasmee-compare.qml -- <page> <out.png> [marks]
Window {
    id: w
    width: 1720
    height: 1225
    visible: true
    color: "#EDE3D0"

    property string root: Qt.resolvedUrl("..").toString().replace("file://", "")
    property var args: Qt.application.arguments
    property int pg: parseInt(args[args.length - (demo ? 3 : 2)])
    property string out: args[args.length - (demo ? 2 : 1)]
    property bool demo: args[args.length - 1] === "demo"
    property var layout: null

    function pad(n) { return n < 10 ? "00" + n : (n < 100 ? "0" + n : "" + n); }

    Component.onCompleted: {
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + root + "data/tasmee/layout.json", false);
        x.send();
        layout = JSON.parse(x.responseText);
        if (demo) {
            var m = {};
            var l = layout.pages[pg - 1].l;
            // أمثلة حالات على أول أسطر الصفحة
            var cnt = 0;
            for (var i = 0; i < l.length; i++) {
                if (!l[i] || l[i].t !== "w") continue;
                for (var j = 0; j < l[i].w.length; j++) {
                    var wd = l[i].w[j];
                    if (wd[3] === 0) continue;
                    cnt++;
                    if (cnt < 20) m[wd[1] + ":" + wd[2] + ":" + wd[3]] = 1;
                    if (cnt === 8) m[wd[1] + ":" + wd[2] + ":" + wd[3]] = 3;
                    if (cnt === 14) m[wd[1] + ":" + wd[2] + ":" + wd[3]] = 4;
                    if (cnt === 20) tp.current = wd[1] + ":" + wd[2] + ":" + wd[3];
                }
            }
            tp.marks = m;
            tp.marksRev++;
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 20
        Image {
            width: w.pg <= 2 ? 843 : 807
            height: w.pg <= 2 ? 1140 : 1205
            fillMode: Image.PreserveAspectFit
            source: "file://" + encodeURI(w.root + "pages/p" + w.pad(w.pg) + ".jpg")
        }
        TasmeePage {
            id: tp
            width: w.pg <= 2 ? 843 : 807
            height: w.pg <= 2 ? 1140 : 1205
            page: w.pg
            lay: w.layout ? w.layout.pages[w.pg - 1] : null
            imageUrl: "file://" + encodeURI(w.root + "pages/p" + w.pad(w.pg) + ".jpg")
            fontUrl: "file://" + encodeURI(w.root + "fonts/qpc-v2/p" + w.pg + ".woff2")
        }
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: w.contentItem.grabToImage(function (r) { r.saveToFile(w.out); Qt.quit(); })
    }
}
