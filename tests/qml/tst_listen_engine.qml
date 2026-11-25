//@ pragma AppId alquran-test
// اختبار منطق السماع في TasmeeEngine بلا واجهة ولا محرك Node (أحداث مُحاكاة).
// تشغيل: tests/qml/run.sh  (ينسخ الاختبار + TasmeeEngine.qml لمجلد مؤقت لأن Quickshell يحجب الملفات خارج مجلد الإعداد)
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property int fails: 0
    property var sent: []
    function check(name, cond) {
        console.log((cond ? "PASS " : "FAIL ") + name);
        if (!cond) root.fails++;
    }

    // يُحمَّل ديناميكيًا لأن Quickshell لا يقرأ ملفات خارج مجلد الإعداد (انظر run.sh)
    Loader { id: ld; source: "TasmeeEngine.qml" }
    property var eng: ld.item

    Component.onCompleted: {
        if (!eng) { console.log("FAIL load TasmeeEngine"); Qt.quit(); return; }
        // نلتقط الأوامر بدل كتابتها في عملية Node
        eng.sendHook = function (o) { root.sent.push(o); return true; };
        eng.bootHook = function () { };
        check("initial idle", eng.listenSt === "idle" && !eng.listening);

        eng.started = true;
        eng.listenStart(1, 2, false);
        var last = root.sent[root.sent.length - 1];
        check("listenStart cmd", last.cmd === "listenStart" && last.s === 1 && last.a === 2 && last.repeat === false);
        check("starting state", eng.listenSt === "starting" && eng.listening);

        eng.handle({ ev: "listen", st: "indexing" });
        check("indexing", eng.listenSt === "indexing" && eng.listening);
        eng.handle({ ev: "listen", st: "playing", s: 1, a: 3 });
        check("playing follows ayah", eng.listenSt === "playing" && eng.listenS === 1 && eng.listenA === 3);
        eng.handle({ ev: "listenWord", w: [1, 3, 4] });
        check("word tracked", eng.listenWord.length === 3 && eng.listenWord[2] === 4);

        eng.listenStop();
        last = root.sent[root.sent.length - 1];
        check("listenStop cmd", last.cmd === "listenStop");
        check("stop clears locally", eng.listenSt === "stopped" && !eng.listening && eng.listenWord === null);
        var n = root.sent.length;
        eng.listenStop();
        check("stop idempotent (no extra cmd)", root.sent.length === n);

        eng.handle({ ev: "listenWord", w: [1, 3, 5] });
        check("late word ignored when stopped", eng.listenWord === null);

        eng.listenStart(2, 255, true);
        check("repeat flag", root.sent[root.sent.length - 1].repeat === true);
        eng.handle({ ev: "listen", st: "error", msg: "الفهرس غير موجود" });
        check("error state+msg", eng.listenSt === "error" && eng.listenMsg === "الفهرس غير موجود" && !eng.listening);
        eng.handle({ ev: "listen", st: "stopped" });
        check("stopped after error keeps error msg cleared", eng.listenSt === "stopped");

        // بدء قبل تشغيل العملية: يُحفظ الطلب ويُرسل عند التشغيل
        eng.started = false;
        root.sent = [];
        eng.listenStart(18, 1, false);
        check("pending when not started", root.sent.length === 0 && eng.listenSt === "starting");
        eng.flushListen();
        check("flushed on start", root.sent.length === 1 && root.sent[0].s === 18);
        eng.listenStop();
        check("stop cancels nothing extra", eng.listenSt === "stopped");

        // توقف العملية أثناء السماع
        eng.started = true;
        eng.listenStart(1, 1, false);
        eng.handle({ ev: "listen", st: "playing", s: 1, a: 1 });
        eng.processStopped();
        check("process death -> error", eng.listenSt === "error" && eng.listenMsg !== "");

        console.log(root.fails === 0 ? "ALL PASS" : ("FAILED " + root.fails));
        Qt.quit();
    }
}
