import QtQuick
import Quickshell
import Quickshell.Io

// غلاف محرك التسميع: يشغّل engine/tasmee-engine.mjs (Node) ويتبادل معه أسطر JSON
Item {
    id: eng

    property string appDir: Quickshell.shellDir
    property string engineDir: ""        // يُحدَّد بالفحص: engine/ في المستودع أو نسخة المستخدم
    property string historyPath: Quickshell.stateDir + "/tasmee-history.json"

    property bool started: false        // العملية تعمل
    property bool ready: false          // النموذج محمَّل
    property bool loading: false
    property string loadStage: ""
    property real loadFraction: 0
    property bool loadFromCache: true
    property string error: ""
    property bool sessionActive: false
    property real level: -90

    signal event(var e)

    function send(o) {
        if (!proc.running) return;
        proc.write(JSON.stringify(o) + "\n");
    }
    function boot() {
        if (proc.running) { if (!eng.ready) eng.send({ cmd: "init", history: eng.historyPath }); return; }
        if (probe.running || setup.running) return;
        eng.error = "";
        eng.loading = true;
        eng.loadStage = "probe";
        probe.running = true;
    }
    // ١) أين المحرك المثبَّت؟
    Process {
        id: probe
        command: ["bash", "-c",
            'for d in "$1/engine" "${XDG_DATA_HOME:-$HOME/.local/share}/alquran/engine"; do ' +
            '[ -d "$d/node_modules/@tilawa/core" ] && [ -f "$d/tasmee-engine.mjs" ] && { echo "OK $d"; exit 0; }; done; echo MISSING', "_", eng.appDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim();
                if (t.indexOf("OK ") === 0) {
                    eng.engineDir = t.substring(3);
                    proc.running = true;
                } else {
                    eng.loadStage = "setup";
                    setup.running = true;
                }
            }
        }
    }
    // ٢) أول مرة: تثبيت حزم المحرك (npm) — يحتاج إنترنت مرة واحدة
    Process {
        id: setup
        command: ["bash", eng.appDir + "/tools/setup-tasmee.sh", "--no-fonts"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                if (line.indexOf("OK ") === 0) eng.engineDir = line.substring(3);
                else if (line.indexOf("ERR node") === 0) eng.error = "وضع التسميع يحتاج Node.js الإصدار ٢٠ أو أحدث — ثبّته (sudo pacman -S nodejs npm) ثم أعد المحاولة";
                else if (line.indexOf("ERR npm") === 0) eng.error = "تعذّر تثبيت محرك التسميع — تأكد من اتصال الإنترنت (مرة واحدة فقط) ثم أعد المحاولة";
            }
        }
        onExited: function (code) {
            if (code === 0 && eng.engineDir !== "") proc.running = true;
            else { eng.loading = false; if (eng.error === "") eng.error = "تعذّر تجهيز محرك التسميع"; }
        }
    }
    function start(o) { eng.send(Object.assign({ cmd: "start" }, o)); }
    function stop() { eng.send({ cmd: "stop" }); }
    function clearMistakes() { eng.send({ cmd: "clearMistakes" }); }
    function similar(s, a) { eng.send({ cmd: "similar", s: s, a: a }); }
    function quit() { if (proc.running) eng.send({ cmd: "quit" }); }

    Process {
        id: proc
        // nice: المحرك يعمل بأولوية منخفضة حتى لا يزاحم الواجهة
        command: ["nice", "-n", "10", "node", eng.engineDir + "/tasmee-engine.mjs"]
        workingDirectory: eng.engineDir
        environment: ({ MUSHAF_APP_DIR: eng.appDir })
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                var e;
                try { e = JSON.parse(line); } catch (x) { return; }
                eng.handle(e);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function (line) { if (line.length) console.log("TASMEE engine stderr: " + line); }
        }
        onRunningChanged: {
            eng.started = running;
            if (running) {
                eng.send({ cmd: "init", history: eng.historyPath });
            } else {
                eng.ready = false;
                eng.sessionActive = false;
                if (eng.loading) {
                    eng.loading = false;
                    if (eng.error === "")
                        eng.error = "تعذّر تشغيل محرك التسميع — تأكد من تثبيت Node.js (الإصدار ٢٠ أو أحدث) ثم شغّل tools/setup-tasmee.sh";
                }
            }
        }
    }

    function handle(e) {
        switch (e.ev) {
        case "load":
            eng.loading = true;
            eng.loadStage = e.stage;
            eng.loadFraction = e.fraction;
            eng.loadFromCache = e.fromCache;
            break;
        case "ready":
            eng.loading = false;
            eng.ready = true;
            eng.error = "";
            break;
        case "started":
            eng.sessionActive = true;
            break;
        case "ended":
            eng.sessionActive = false;
            eng.level = -90;
            break;
        case "level":
            eng.level = e.db;
            break;
        case "error":
            if (e.code === "load") { eng.loading = false; eng.error = e.msg; }
            if (e.code === "mic") eng.sessionActive = false;
            console.log("TASMEE error " + e.code + ": " + e.msg + (e.detail ? " — " + e.detail : ""));
            break;
        }
        eng.event(e);
    }
}
