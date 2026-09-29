//@ pragma AppId alquran
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "theme.js" as T
import "utils.js" as U

ShellRoot {
    FloatingWindow {
        id: win
        title: "القرآن الكريم"
        color: T.bg
        visible: true
        implicitWidth: Math.min(1760, screen ? screen.width - 24 : 1760)
        implicitHeight: Math.min(1080, screen ? screen.height - 48 : 1080)
        minimumSize: Qt.size(980, 640)

        Item {
            id: app
            anchors.fill: parent
            focus: true

            property int rightPage: 1
            property var found: null
            property var foundPos: null
            property var bookmarks: []        // علامات الحفظ [{p, s, a}]
            readonly property var loc: (data.ready && rightPage > 0) ? data.locate(rightPage) : null
            readonly property bool bookmarkedNow: isBookmarked() >= 0

            // ---------- مسارات النسختين: تطوير بجانب المشروع / تركيب نظامي ----------
            readonly property string appDir: Quickshell.shellDir
            property string pagesDir: ""          // تُحدَّد بعد فحص المسارات
            property string pagesMode: "?"
            property int dlCount: 604
            property bool pagesReady: true
            property bool fetchFailed: false

            function startFetch() {
                app.fetchFailed = false;
                fetchProc.running = true;
                pollTimer.running = true;
            }

            Data { id: data }

            function clampRight(p) {
                if (p > 603) p = 603;
                if (p < 1) p = 1;
                if (p % 2 === 0) p -= 1;
                return p;
            }
            function goto(page) {
                app.rightPage = clampRight(page);
                app.found = null;
                app.foundPos = null;
                reader.forceActiveFocus();
            }
            function pageMove(d) { app.goto(app.rightPage + d); }

            // ---------- العلامات (موضع الحفظ) ----------
            function isBookmarked() {
                for (var i = 0; i < app.bookmarks.length; i++) {
                    var b = app.bookmarks[i];
                    if (b.p !== app.rightPage) continue;
                    if (app.found === null) { if (!b.a) return i; }
                    else if (b.s === app.found.s && b.a === app.found.a) return i;
                }
                return -1;
            }
            function toggleBookmark() {
                var idx = app.isBookmarked();
                var arr = app.bookmarks.slice();
                if (idx >= 0) {
                    arr.splice(idx, 1);
                    app.bookmarks = arr;
                    toast.show("أُزيلت العلامة من صفحة " + U.ar(app.rightPage));
                } else {
                    arr.push({ p: app.rightPage, s: app.found ? app.found.s : null, a: app.found ? app.found.a : null });
                    arr.sort(function (x, y) { return x.p - y.p; });
                    app.bookmarks = arr;
                    toast.show("تم حفظ العلامة — صفحة " + U.ar(app.rightPage) + (app.found ? " · الآية " + U.ar(app.found.a) : ""));
                }
            }

            // ---------- حفظ/استرجاع آخر صفحة + العلامات ----------
            FileView {
                id: stateFile
                path: Quickshell.stateDir + "/state.json"
                printErrors: false
                onLoaded: {
                    try {
                        var s = JSON.parse(stateFile.text());
                        console.log("MUSHAF state loaded: page=" + (s ? s.page : "?") + " bookmarks=" + JSON.stringify(s ? s.bookmarks : null));
                        if (s && s.page >= 1) app.rightPage = app.clampRight(s.page);
                        if (s && Array.isArray(s.bookmarks))
                            app.bookmarks = s.bookmarks.filter(function (b) { return b && b.p >= 1; });
                    } catch (e) { console.log("state parse:", e); }
                }
            }
            Timer {
                id: saveTimer
                interval: 900
                onTriggered: {
                    try { stateFile.setText(JSON.stringify({ page: app.rightPage, bookmarks: app.bookmarks })); } catch (e) {}
                }
            }
            onRightPageChanged: saveTimer.restart()
            onBookmarksChanged: saveTimer.restart()

            // ---------- فحص مسار الصفحات + تنزيل أول تشغيل ----------
            Process {
                id: pathProbe
                command: ["bash", "-c",
                    'DEV="' + app.appDir + '/pages"; USR="${XDG_DATA_HOME:-$HOME/.local/share}/alquran/pages"; ' +
                    'if [ -f "$DEV/p604.jpg" ]; then echo "DEV|$DEV"; else mkdir -p "$USR"; N=$(ls "$USR"/p*.jpg 2>/dev/null | wc -l); echo "USER|$USR|$N"; fi']
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        var parts = text.trim().split("|");
                        app.pagesMode = parts[0];
                        app.pagesDir = parts[1];
                        var n = parseInt(parts[2] || "604");
                        app.dlCount = (parts[0] === "DEV") ? 604 : n;
                        console.log("MUSHAF pages mode=" + parts[0] + " dir=" + parts[1] + " count=" + app.dlCount);
                        if (app.dlCount < 604) {
                            app.pagesReady = false;
                            app.startFetch();
                        }
                    }
                }
            }
            Process {
                id: fetchProc
                command: ["bash", app.appDir + "/tools/fetch-pages.sh", app.pagesDir]
                onExited: {
                    pollTimer.running = false;
                    pollNow.running = true;
                }
            }
            Process {
                id: pollNow
                command: ["bash", "-c", 'ls "' + app.pagesDir + '"/p*.jpg 2>/dev/null | wc -l']
                stdout: StdioCollector {
                    onStreamFinished: {
                        app.dlCount = parseInt(text.trim() || "0");
                        if (app.dlCount >= 604) {
                            if (!app.pagesReady) reader.reloadTick = reader.reloadTick + 1;
                            app.pagesReady = true;
                            app.fetchFailed = false;
                        } else if (!fetchProc.running && !pollTimer.running) {
                            app.fetchFailed = true;
                        }
                    }
                }
            }
            Timer {
                id: pollTimer
                interval: 1500
                repeat: true
                onTriggered: pollNow.running = true
            }

            Rectangle { anchors.fill: parent; color: T.bg }

            HeaderBar {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                loc: app.loc
                page: app.rightPage
                bookmarked: app.bookmarkedNow
                onOpenMenu: nav.open()
                onOpenSearch: search.open()
                onAddBookmark: app.toggleBookmark()
            }

            ReaderView {
                id: reader
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                rightPage: app.rightPage
                pagesDir: app.pagesDir
                found: app.found
                foundPos: app.foundPos
                bookmarks: app.bookmarks
                onForward: app.pageMove(2)
                onBackward: app.pageMove(-2)
                onJump: function (page) { app.goto(page); }
            }

            NavMenu {
                id: nav
                anchors.fill: parent
                qdata: data
                loc: app.loc
                currentPage: app.rightPage
                bookmarks: app.bookmarks
                onBookmarkRemove: function (bm) {
                    app.bookmarks = app.bookmarks.filter(function (x) {
                        if (x === bm) return false;
                        if (bm && x && x.p === bm.p && x.a === bm.a) return false;
                        return true;
                    });
                }
                onJump: function (page) { app.goto(page); }
                onClosed: reader.forceActiveFocus()
            }

            SearchPanel {
                id: search
                anchors.fill: parent
                qdata: data
                onJump: function (page, info) {
                    app.goto(page);
                    if (info) {
                        app.found = info;
                        app.foundPos = data.posOfAya(info.s, info.a);
                    }
                }
                onClosed: reader.forceActiveFocus()
            }

            // شاشة أول تشغيل: تنزيل صفحات المصحف
            DownloadView {
                id: download
                anchors.fill: parent
                z: 60
                visible: !app.pagesReady
                count: app.dlCount
                failed: app.fetchFailed
                onRetry: app.startFetch()
            }

            // ---------- واجهة IPC (للأتمتة والاختبار) ----------
            // qs ipc call mushaf bookmark | gotoPage 42 | openNav | navTab 5 | closeAll
            IpcHandler {
                target: "mushaf"
                function bookmark() { app.toggleBookmark(); }
                function gotoPage(page: int): void { app.goto(page); }
                function openNav() { nav.open(); }
                function navTab(i: int): void { nav.tab = i; nav.rebuild(); }
                // حالة تنزيل الصفحات (للاختبار)
                function fetchState(): string {
                    return JSON.stringify({ mode: app.pagesMode, dir: app.pagesDir, count: app.dlCount, ready: app.pagesReady, failed: app.fetchFailed });
                }
                function retryFetch(): void { app.startFetch(); }
                // اختبار: إزالة أول علامة عبر نفس مسار زر ✕ في القائمة
                function navRemoveFirst(): void {
                    if (nav.bookmarks.length > 0) nav.bookmarkRemove(nav.bookmarks[0]);
                }
                function closeAll() {
                    if (nav.visible) nav.close();
                    if (search.visible) search.close();
                }
                function activate() {
                    var tops = ToplevelManager.toplevels.values;
                    for (var i = 0; i < tops.length; i++) {
                        if (tops[i].appId === "alquran") { tops[i].activate(); return; }
                    }
                }
                function snap(path: string): void {
                    app.grabToImage(function (result) {
                        var ok = result.saveToFile(path);
                        console.log("MUSHAF snapshot save " + ok + ": " + path);
                    });
                }
            }

            // ---------- إشعار صغير (حفظ/إزالة علامة) ----------
            Rectangle {
                id: toast
                property string msg: ""
                function show(m) { toast.msg = m; toast.opacity = 1; toastTimer.restart(); }
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                width: toastTxt.implicitWidth + 48
                height: 40
                radius: 20
                color: T.panel
                border.color: T.goldSoft
                border.width: 1
                opacity: 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Text {
                    id: toastTxt
                    anchors.centerIn: parent
                    text: toast.msg
                    color: T.ink
                    font.family: T.fontUI
                    font.pixelSize: 15
                }
                Timer { id: toastTimer; interval: 2300; onTriggered: toast.opacity = 0 }
            }

            // ---------- اختصارات ----------
            Shortcut { sequence: "Ctrl+F"; onActivated: search.open() }
            Shortcut { sequence: "Ctrl+G"; onActivated: nav.open() }
            Shortcut { sequence: "Ctrl+B"; onActivated: app.toggleBookmark() }
            Shortcut { sequence: "F11"; onActivated: win.fullscreen = !win.fullscreen }
            Shortcut {
                sequence: "Escape"
                onActivated: {
                    if (search.visible) search.close();
                    else if (nav.visible) nav.close();
                }
            }
        }
    }
}
