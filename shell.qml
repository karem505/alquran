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
                pagesDir: Quickshell.shellDir + "/pages"
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
                    app.bookmarks = app.bookmarks.filter(function (x) { return x !== bm; });
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

            // ---------- واجهة IPC (للأتمتة والاختبار) ----------
            // qs ipc call mushaf bookmark | gotoPage 42 | openNav | navTab 5 | closeAll
            IpcHandler {
                target: "mushaf"
                function bookmark() { app.toggleBookmark(); }
                function gotoPage(page: int): void { app.goto(page); }
                function openNav() { nav.open(); }
                function navTab(i: int): void { nav.tab = i; nav.rebuild(); }
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
