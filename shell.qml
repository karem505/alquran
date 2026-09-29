import QtQuick
import Quickshell
import Quickshell.Io
import "theme.js" as T

ShellRoot {
    FloatingWindow {
        id: win
        title: "مصحفي — القرآن الكريم"
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
            readonly property var loc: (data.ready && rightPage > 0) ? data.locate(rightPage) : null

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

            // ---------- حفظ/استرجاع آخر صفحة ----------
            FileView {
                id: stateFile
                path: Quickshell.stateDir + "/state.json"
                printErrors: false
                onLoaded: {
                    try {
                        var s = JSON.parse(stateFile.text());
                        if (s && s.page >= 1) app.rightPage = app.clampRight(s.page);
                    } catch (e) { console.log("state parse:", e); }
                }
            }
            Timer {
                id: saveTimer
                interval: 900
                onTriggered: {
                    try { stateFile.setText(JSON.stringify({ page: app.rightPage })); } catch (e) {}
                }
            }
            onRightPageChanged: saveTimer.restart()

            Rectangle { anchors.fill: parent; color: T.bg }

            HeaderBar {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                loc: app.loc
                page: app.rightPage
                onOpenMenu: nav.open()
                onOpenSearch: search.open()
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

            // ---------- اختصارات ----------
            Shortcut { sequence: "Ctrl+F"; onActivated: search.open() }
            Shortcut { sequence: "Ctrl+G"; onActivated: nav.open() }
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
