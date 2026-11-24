import QtQuick

// قياس عرض حبر كل رمز QPC لكل صفحة (لأداة تصحيح فواصل الأسطر)
// QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 /usr/lib/qt6/bin/qml tools/qpc-measure.qml 2> widths.log
// كل سطر مخرج: "QPCW <page> <json: [[w, ...] لكل سطر]>"
Item {
    id: m
    property string root: Qt.resolvedUrl("..").toString().replace("file://", "")
    property var layout: null
    property int page: 0
    property int fs: 100

    FontLoader { id: fl }
    TextMetrics { id: tm; font.family: fl.name; font.pixelSize: 47 }

    function next() {
        m.page++;
        if (m.page > 604) { Qt.quit(); return; }
        fl.source = "file://" + encodeURI(m.root + "fonts/qpc-v2/p" + m.page + ".woff2");
    }
    // FontLoader قد يصبح جاهزًا فورًا دون إشارة تغيّر — نتحقق دوريًا من تغيّر اسم العائلة
    property string lastName: ""
    Timer {
        interval: 15
        repeat: true
        running: m.layout !== null
        onTriggered: {
            if (fl.status === FontLoader.Error) { console.log("QPCW " + m.page + " null"); m.next(); return; }
            if (fl.status === FontLoader.Ready && fl.name !== m.lastName) { m.lastName = fl.name; m.measure(); }
        }
    }
    function measure() {
        var L = m.layout.pages[m.page - 1].l, out = [];
        for (var i = 0; i < L.length; i++) {
            if (!L[i] || L[i].t !== "w") { out.push(null); continue; }
            var ws = [];
            for (var j = 0; j < L[i].w.length; j++) {
                tm.text = L[i].w[j][0];
                ws.push([Math.round(tm.advanceWidth * 100) / 100, Math.round(tm.tightBoundingRect.x * 100) / 100, Math.round(tm.tightBoundingRect.width * 100) / 100]);
            }
            out.push(ws);
        }
        console.log("QPCW " + m.page + " " + JSON.stringify(out));
        m.next();
    }
    Component.onCompleted: {
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + m.root + "data/tasmee/layout.json", false);
        x.send();
        m.layout = JSON.parse(x.responseText);
        m.next();
    }
}
