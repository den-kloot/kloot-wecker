// oma_alarm: the Qt Quick app (run by `oma_alarm` through Quickshell).
// OMA_ALARM_MODE=manage: the alarm list and editor; =ring: the ring screen.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("OMA_ALARM_MODE") || "manage"
    readonly property string bin: Quickshell.env("OMA_ALARM_BIN") || "oma_alarm"
    readonly property string conf: Quickshell.env("OMA_ALARM_CONF") || (Quickshell.env("HOME") + "/.config/oma_alarm")
    readonly property string run: Quickshell.env("OMA_ALARM_RUN") || "/tmp/oma_alarm"
    readonly property var dayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    readonly property var dayLetters: ["M", "T", "W", "T", "F", "S", "S"]

    // Colors from the current Omarchy theme (colors.toml), re-read every
    // 2 s so a theme switch shows up right away; square corners, monospace,
    // thin borders like the rest of Omarchy.
    readonly property string themeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
    property color bg: "#101315"
    property color fg: "#cacccc"
    property color accent: "#cacccc"
    property color urgent: "#a55555"
    property color dimFg: "#707880"
    readonly property color fg2: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
    readonly property color card: Qt.rgba(fg.r, fg.g, fg.b, 0.04)
    readonly property color card2: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
    readonly property color pressedFill: Qt.rgba(fg.r, fg.g, fg.b, 0.22)
    readonly property color sep: Qt.rgba(fg.r, fg.g, fg.b, 0.4)
    readonly property color green: accent
    readonly property color red: urgent
    readonly property string mono: "monospace"

    function applyTheme(text) {
        var v = {}
        String(text).split("\n").forEach(function(line) {
            var m = line.match(/^\s*([A-Za-z_]+)\s*=\s*"([^"]*)"/)
            if (m) v[m[1]] = m[2]
        })
        if (v.background) bg = v.background
        if (v.foreground) fg = v.foreground
        if (v.accent) accent = v.accent
        urgent = v.urgent || v.red || urgent
        if (v.dark_foreground) dimFg = v.dark_foreground
    }

    property var alarms: []
    property var sounds: []
    property date now: new Date()
    property string page: mode === "ring" ? "ring" : "list"   // list | edit | sounds | countdown | ring
    property var draft: null
    property bool draftIsNew: false
    property int countdown: 0
    property bool ringSeen: false
    property string playing: ""

    // ------------------------------------------------------------ data

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function parseTime(t) {
        var p = String(t || "08:00:00").split(":").map(function(x) { return parseInt(x) || 0 })
        return [p[0] || 0, p[1] || 0, p[2] || 0]
    }
    function timeText(t, withSec) {
        var p = parseTime(t)
        return pad(p[0]) + ":" + pad(p[1]) + (withSec && p[2] ? ":" + pad(p[2]) : "")
    }
    function daysText(days) {
        if (!days || days.length === 0) return "Once"
        var s = days.slice().sort()
        if (s.length === 7) return "Daily"
        if (s.join() === "0,1,2,3,4") return "Weekdays"
        if (s.join() === "5,6") return "Weekend"
        return s.map(function(d) { return dayNames[d] }).join(" ")
    }
    function soundName(path) {
        if (!path) return "Default"
        var b = path.split("/").pop()
        var i = b.lastIndexOf(".")
        return i > 0 ? b.substring(0, i) : b
    }
    function nextRing(a) {
        if (!a.enabled) return null
        var p = parseTime(a.time)
        for (var add = 0; add < 8; add++) {
            var d = new Date(now.getTime())
            d.setDate(d.getDate() + add)
            d.setHours(p[0], p[1], p[2], 0)
            if (d <= now) continue
            var wd = (d.getDay() + 6) % 7
            if (!a.days || a.days.length === 0 || a.days.indexOf(wd) >= 0) return d
        }
        return null
    }
    function untilText(d) {
        if (!d) return ""
        var mins = Math.floor((d - now) / 60000) + 1
        var h = Math.floor(mins / 60), m = mins % 60
        if (h >= 24) return "in " + Math.floor(h / 24) + " d " + (h % 24) + " h"
        return h > 0 ? "in " + h + " h " + m + " min" : "in " + m + " min"
    }
    function sorted(list) {
        return list.slice().sort(function(a, b) {
            var x = parseTime(a.time), y = parseTime(b.time)
            return (x[0] * 3600 + x[1] * 60 + x[2]) - (y[0] * 3600 + y[1] * 60 + y[2])
        })
    }
    function save() {
        alarmsFile.setText(JSON.stringify(alarms, null, 1) + "\n")
    }
    function setAlarm(id, fields) {
        var list = alarms.slice()
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                var a = Object.assign({}, list[i], fields)
                list[i] = a
            }
        }
        alarms = list
        save()
    }
    function newId() { return Math.random().toString(16).slice(2, 10) }

    function openEditor(a) {
        draftIsNew = !a
        draft = a ? Object.assign({}, a, { days: (a.days || []).slice() })
                  : { id: newId(), time: "08:00:00", days: [], enabled: true, label: "Alarm", sound: "" }
        page = "edit"
    }
    function commitDraft() {
        stopPreview()
        var d = Object.assign({}, draft, { enabled: true })
        var list = alarms.filter(function(x) { return x.id !== d.id })
        list.push(d)
        alarms = list
        save()
        page = "list"
    }
    function deleteDraft() {
        stopPreview()
        alarms = alarms.filter(function(x) { return x.id !== draft.id })
        save()
        page = "list"
    }
    function setDraft(fields) { draft = Object.assign({}, draft, fields) }

    function preview(path) {
        stopPreview()
        if (!path) return
        previewProc.command = ["timeout", "20", "mpv", "--no-video", "--really-quiet", path]
        previewProc.running = true
        playing = path
    }
    function stopPreview() {
        if (previewProc.running) previewProc.running = false
        playing = ""
    }

    function startTest() {
        countdown = 5
        page = "countdown"
    }
    function ringAction(action) {
        Quickshell.execDetached([bin, action])
        if (mode === "ring") Qt.quit()
        else page = "list"
    }

    FileView {
        id: themeFile
        path: root.themeDir + "/colors.toml"
        onLoaded: root.applyTheme(text())
    }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: themeFile.reload() }

    FileView {
        id: alarmsFile
        path: root.conf + "/alarms.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.alarms = JSON.parse(text()) || [] } catch (e) { root.alarms = [] }
        }
        onLoadFailed: root.alarms = []
    }

    FileView {
        id: ringFile
        path: root.page === "ring" ? root.run + "/ringing.json" : ""
        property string label: "Alarm"
        onLoaded: {
            root.ringSeen = true
            try { label = JSON.parse(text()).label || "Alarm" } catch (e) {}
        }
        onLoadFailed: {
            // The ringing ended elsewhere (stop from the CLI, timeout).
            if (root.page === "ring" && root.ringSeen) {
                root.ringSeen = false
                if (root.mode === "ring") Qt.quit()
                else root.page = "list"
            }
        }
    }

    Process {
        id: soundsProc
        command: [root.bin, "sounds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.sounds = JSON.parse(this.text) } catch (e) { root.sounds = [] }
            }
        }
    }

    Process { id: previewProc; onExited: root.playing = "" }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.now = new Date()
            if (root.page === "ring") ringFile.reload()
            if (root.page === "countdown") {
                root.countdown -= 1
                if (root.countdown <= 0) {
                    Quickshell.execDetached([root.bin, "ring", "--no-window", "Test"])
                    root.ringSeen = false
                    root.page = "ring"
                }
            }
        }
    }

    // ------------------------------------------------------------ widgets

    // A bordered, square button; `primary` fills it with the accent.
    component TextButton: Rectangle {
        id: tb
        signal clicked()
        property string text: ""
        property bool bold: false
        property bool primary: false
        property bool danger: false
        property int size: 16
        implicitWidth: tbLabel.implicitWidth + 28
        implicitHeight: 40
        color: primary ? root.accent : (tbArea.pressed ? root.pressedFill : root.card)
        border.width: 1
        border.color: danger ? root.red : (primary ? root.accent : root.sep)
        Text {
            id: tbLabel
            anchors.centerIn: parent
            text: tb.text
            color: tb.primary ? root.bg : (tb.danger ? root.red : root.fg)
            font.family: root.mono
            font.pixelSize: tb.size
            font.bold: tb.bold || tb.primary
        }
        opacity: tbArea.pressed && primary ? 0.7 : 1
        MouseArea { id: tbArea; anchors.fill: parent; anchors.margins: -6; onClicked: tb.clicked() }
    }

    // [ ON ] / [OFF], square like the rest.
    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled()
        width: 64; height: 34
        color: checked ? root.accent : root.card
        border.width: 1
        border.color: checked ? root.accent : root.sep
        Text {
            anchors.centerIn: parent
            text: tg.checked ? "ON" : "OFF"
            color: tg.checked ? root.bg : root.fg2
            font.family: root.mono; font.pixelSize: 15; font.bold: true
        }
        MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: tg.toggled() }
    }

    component Wheel: Tumbler {
        id: wh
        property int n: 60
        property string unit: ""
        model: n
        wrap: true
        visibleItemCount: 5
        width: 78
        height: 5 * 52
        background: Item {}
        delegate: Text {
            required property int index
            readonly property real displacement: Tumbler.displacement
            text: root.pad(index)
            color: Math.abs(displacement) < 0.5 ? root.accent : root.fg
            font.family: root.mono
            font.pixelSize: 32
            font.bold: Math.abs(displacement) < 0.5
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: Math.max(0.15, 1 - Math.abs(displacement) / 2.6)
            scale: 1 - Math.min(0.25, Math.abs(displacement) * 0.09)
        }
        Text {
            anchors.left: parent.right; anchors.leftMargin: -6
            anchors.verticalCenter: parent.verticalCenter
            text: wh.unit; color: root.fg2; font.family: root.mono; font.pixelSize: 14
        }
    }

    // ------------------------------------------------------------ window

    FloatingWindow {
        id: win
        title: "OmaAlarm"
        color: root.bg
        implicitWidth: 412
        implicitHeight: 900

        Component.onCompleted: { soundsProc.running = true }

        // ---------------- list
        Item {
            anchors.fill: parent
            visible: root.page === "list"

            TextButton {
                id: testBtn
                text: "Test"
                anchors.left: parent.left; anchors.leftMargin: 20
                anchors.top: parent.top; anchors.topMargin: 20
                onClicked: root.startTest()
            }
            TextButton {
                text: "+ New"; primary: true
                anchors.right: parent.right; anchors.rightMargin: 20
                anchors.verticalCenter: testBtn.verticalCenter
                onClicked: root.openEditor(null)
            }
            Text {
                id: title
                text: "> OmaAlarm_"
                color: root.accent
                font.family: root.mono; font.pixelSize: 28; font.bold: true
                anchors.left: parent.left; anchors.leftMargin: 20
                anchors.top: testBtn.bottom; anchors.topMargin: 18
            }

            Text {
                visible: root.alarms.length === 0
                anchors.centerIn: parent
                text: "No alarms yet\nTap + New"
                horizontalAlignment: Text.AlignHCenter
                color: root.fg2; font.family: root.mono; font.pixelSize: 20
            }

            ListView {
                id: list
                anchors.top: title.bottom; anchors.topMargin: 12
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                clip: true
                model: root.sorted(root.alarms)
                boundsBehavior: Flickable.DragAndOvershootBounds
                delegate: Item {
                    id: row
                    required property var modelData
                    width: list.width
                    height: 112
                    Rectangle {
                        anchors.fill: parent
                        color: rowArea.pressed ? root.card2 : "transparent"
                    }
                    MouseArea { id: rowArea; anchors.fill: parent; onClicked: root.openEditor(row.modelData) }
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: root.timeText(row.modelData.time, true)
                            color: row.modelData.enabled ? root.fg : root.fg2
                            font.family: root.mono; font.pixelSize: 46; font.bold: row.modelData.enabled
                        }
                        Text {
                            text: (row.modelData.label || "Alarm") + ", " + root.daysText(row.modelData.days)
                                  + (row.modelData.enabled ? "  ·  " + root.untilText(root.nextRing(row.modelData)) : "")
                            color: row.modelData.enabled ? root.fg : root.fg2
                            font.family: root.mono; font.pixelSize: 15
                        }
                    }
                    Toggle {
                        anchors.right: parent.right; anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        checked: !!row.modelData.enabled
                        onToggled: root.setAlarm(row.modelData.id, { enabled: !row.modelData.enabled })
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.leftMargin: 20
                        anchors.right: parent.right; height: 1; color: root.sep
                    }
                }
            }
        }

        // ---------------- editor
        Item {
            id: editor
            anchors.fill: parent
            visible: root.page === "edit"

            onVisibleChanged: {
                if (visible && root.draft) {
                    var p = root.parseTime(root.draft.time)
                    hWheel.currentIndex = p[0]
                    mWheel.currentIndex = p[1]
                    sWheel.currentIndex = p[2]
                    labelField.text = root.draft.label || "Alarm"
                }
            }
            function wheelTime() {
                return root.pad(hWheel.currentIndex) + ":" + root.pad(mWheel.currentIndex) + ":" + root.pad(sWheel.currentIndex)
            }

            TextButton {
                id: cancelBtn
                text: "Cancel"
                anchors.left: parent.left; anchors.leftMargin: 20
                anchors.top: parent.top; anchors.topMargin: 20
                onClicked: { root.stopPreview(); root.page = "list" }
            }
            Text {
                text: root.draftIsNew ? "new alarm" : "edit alarm"
                color: root.fg; font.family: root.mono; font.pixelSize: 18; font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: cancelBtn.verticalCenter
            }
            TextButton {
                text: "Save"; primary: true
                anchors.right: parent.right; anchors.rightMargin: 20
                anchors.verticalCenter: cancelBtn.verticalCenter
                onClicked: {
                    root.setDraft({ time: editor.wheelTime(), label: labelField.text || "Alarm" })
                    root.commitDraft()
                }
            }

            // the wheels
            Item {
                id: wheels
                anchors.top: cancelBtn.bottom; anchors.topMargin: 16
                anchors.left: parent.left; anchors.right: parent.right
                height: 5 * 52
                Rectangle {   // selection band
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    height: 50; color: root.card
                    border.width: 1; border.color: root.accent
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 30
                    Wheel { id: hWheel; n: 24; unit: "hr" }
                    Wheel { id: mWheel; n: 60; unit: "min" }
                    Wheel { id: sWheel; n: 60; unit: "sec" }
                }
            }

            Flickable {
                anchors.top: wheels.bottom; anchors.topMargin: 20
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                contentHeight: form.height + 40
                clip: true
                Column {
                    id: form
                    x: 16; width: parent.width - 32
                    spacing: 18

                    // repeat
                    Rectangle {
                        width: parent.width; height: daysCol.height + 28; color: root.card; border.width: 1; border.color: root.sep
                        Column {
                            id: daysCol
                            x: 14; y: 14; width: parent.width - 28; spacing: 14
                            Row {
                                width: parent.width
                                Text { text: "Repeat"; color: root.fg; font.family: root.mono; font.pixelSize: 17; width: parent.width / 2 }
                                Text {
                                    text: root.draft ? root.daysText(root.draft.days) : ""
                                    color: root.fg2; font.family: root.mono; font.pixelSize: 17
                                    width: parent.width / 2; horizontalAlignment: Text.AlignRight
                                }
                            }
                            Row {
                                spacing: (parent.width - 7 * 40) / 6
                                Repeater {
                                    model: 7
                                    Rectangle {
                                        required property int index
                                        readonly property bool on: !!root.draft && root.draft.days.indexOf(index) >= 0
                                        width: 40; height: 40
                                        color: on ? root.accent : root.card
                                        border.width: 1; border.color: on ? root.accent : root.sep
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            anchors.centerIn: parent; text: root.dayLetters[index]
                                            color: parent.on ? root.bg : root.fg; font.family: root.mono; font.pixelSize: 16; font.weight: Font.DemiBold
                                        }
                                        MouseArea {
                                            anchors.fill: parent; anchors.margins: -4
                                            onClicked: {
                                                var d = root.draft.days.slice()
                                                var i = d.indexOf(index)
                                                if (i >= 0) d.splice(i, 1); else d.push(index)
                                                root.setDraft({ days: d.sort() })
                                            }
                                        }
                                    }
                                }
                            }
                            Flow {
                                width: parent.width
                                spacing: 10
                                Repeater {
                                    model: [["Weekdays", [0, 1, 2, 3, 4]], ["Weekend", [5, 6]], ["Daily", [0, 1, 2, 3, 4, 5, 6]], ["Once", []]]
                                    Rectangle {
                                        required property var modelData
                                        height: 32; width: chip.width + 20
                                        color: chipArea.pressed ? root.pressedFill : root.card
                                        border.width: 1; border.color: root.sep
                                        Text { id: chip; anchors.centerIn: parent; text: parent.modelData[0]; color: root.fg; font.family: root.mono; font.pixelSize: 14 }
                                        MouseArea { id: chipArea; anchors.fill: parent; onClicked: root.setDraft({ days: parent.modelData[1].slice() }) }
                                    }
                                }
                            }
                        }
                    }

                    // label + sound
                    Rectangle {
                        width: parent.width; height: 112; color: root.card; border.width: 1; border.color: root.sep
                        Item {
                            width: parent.width; height: 56
                            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "Label"; color: root.fg; font.family: root.mono; font.pixelSize: 17 }
                            TextField {
                                id: labelField
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.6
                                horizontalAlignment: Text.AlignRight
                                color: root.fg2; font.family: root.mono; font.pixelSize: 17
                                background: Item {}
                            }
                        }
                        Rectangle { x: 14; y: 56; width: parent.width - 14; height: 1; color: root.sep }
                        Item {
                            y: 56; width: parent.width; height: 56
                            Rectangle { anchors.fill: parent; color: soundArea.pressed ? root.pressedFill : "transparent" }
                            MouseArea { id: soundArea; anchors.fill: parent; onClicked: { root.stopPreview(); root.setDraft({ time: editor.wheelTime(), label: labelField.text || "Alarm" }); soundsProc.running = true; root.page = "sounds" } }
                            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "Sound"; color: root.fg; font.family: root.mono; font.pixelSize: 17 }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 34
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.62; elide: Text.ElideLeft; horizontalAlignment: Text.AlignRight
                                text: root.draft ? root.soundName(root.draft.sound) : ""
                                color: root.fg2; font.family: root.mono; font.pixelSize: 17
                            }
                            Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: ">"; color: root.fg2; font.family: root.mono; font.pixelSize: 18 }
                        }
                    }

                    // delete
                    Rectangle {
                        visible: !root.draftIsNew
                        width: parent.width; height: 56
                        color: delArea.pressed ? root.pressedFill : root.card
                        border.width: 1; border.color: root.red
                        Text { anchors.centerIn: parent; text: "Delete alarm"; color: root.red; font.family: root.mono; font.pixelSize: 17 }
                        MouseArea { id: delArea; anchors.fill: parent; onClicked: root.deleteDraft() }
                    }
                }
            }
        }

        // ---------------- sound picker
        Item {
            anchors.fill: parent
            visible: root.page === "sounds"

            TextButton {
                id: backBtn
                text: "< Back"
                anchors.left: parent.left; anchors.leftMargin: 14
                anchors.top: parent.top; anchors.topMargin: 20
                onClicked: { root.stopPreview(); root.page = "edit" }
            }
            Text {
                text: "Sound"; color: root.fg; font.family: root.mono; font.pixelSize: 18; font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: backBtn.verticalCenter
            }
            Text {
                id: hint
                anchors.top: backBtn.bottom; anchors.topMargin: 18
                x: 20; width: parent.width - 40; wrapMode: Text.WordWrap
                text: "Tap a sound to choose it and hear it. Put your own files in your Music folder."
                color: root.fg2; font.family: root.mono; font.pixelSize: 14
            }
            ListView {
                id: soundList
                anchors.top: hint.bottom; anchors.topMargin: 12
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                clip: true
                model: root.sounds
                delegate: Item {
                    id: srow
                    required property var modelData
                    readonly property bool chosen: !!root.draft && (root.draft.sound || "") === modelData.path
                    width: soundList.width; height: 60
                    Rectangle { anchors.fill: parent; color: sArea.pressed ? root.card2 : "transparent" }
                    MouseArea {
                        id: sArea; anchors.fill: parent
                        onClicked: {
                            var p = srow.modelData.play || srow.modelData.path
                            if (srow.chosen && root.playing === p) { root.stopPreview(); return }
                            root.setDraft({ sound: srow.modelData.path })
                            root.preview(p)
                        }
                    }
                    Text {
                        x: 20; width: 34; anchors.verticalCenter: parent.verticalCenter
                        text: srow.chosen ? ">" : ""; color: root.accent; font.family: root.mono; font.pixelSize: 20; font.weight: Font.Bold
                    }
                    Column {
                        x: 54; width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter
                        Text { width: parent.width; elide: Text.ElideRight; text: srow.modelData.name; color: root.fg; font.family: root.mono; font.pixelSize: 17 }
                        Text {
                            visible: !!srow.modelData.dir; width: parent.width; elide: Text.ElideLeft
                            text: srow.modelData.dir || ""; color: root.fg2; font.family: root.mono; font.pixelSize: 12
                        }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
                        visible: root.playing !== "" && root.playing === (srow.modelData.play || srow.modelData.path)
                        text: "[play]"; color: root.accent; font.family: root.mono; font.pixelSize: 20
                    }
                    Rectangle { anchors.bottom: parent.bottom; x: 54; width: parent.width - 54; height: 1; color: root.sep }
                }
            }
        }

        // ---------------- test countdown
        Item {
            anchors.fill: parent
            visible: root.page === "countdown"
            Column {
                anchors.centerIn: parent; spacing: 30
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Test rings in"; color: root.fg2; font.family: root.mono; font.pixelSize: 20 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.countdown; color: root.accent; font.family: root.mono; font.pixelSize: 120; font.bold: true }
                TextButton { anchors.horizontalCenter: parent.horizontalCenter; text: "Cancel"; onClicked: root.page = "list" }
            }
        }

        // ---------------- ringing
        Item {
            anchors.fill: parent
            visible: root.page === "ring"

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.12
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pad(root.now.getHours()) + ":" + root.pad(root.now.getMinutes())
                    color: root.accent; font.family: root.mono; font.pixelSize: 96; font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ringFile.label
                    color: root.fg2; font.family: root.mono; font.pixelSize: 24
                }
            }

            Rectangle {
                id: snoozeBtn
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.48
                width: parent.width - 40; height: 120
                color: snArea.pressed ? Qt.darker(root.accent, 1.3) : root.accent
                Text { anchors.centerIn: parent; text: "[ Snooze 5 min ]"; color: root.bg; font.family: root.mono; font.pixelSize: 24; font.bold: true }
                MouseArea { id: snArea; anchors.fill: parent; onClicked: root.ringAction("snooze") }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: snoozeBtn.bottom; anchors.topMargin: 28
                width: parent.width - 40; height: 100
                color: stArea.pressed ? root.pressedFill : root.card
                border.width: 2; border.color: root.red
                Text { anchors.centerIn: parent; text: "[ Stop ]"; color: root.red; font.family: root.mono; font.pixelSize: 24; font.bold: true }
                MouseArea { id: stArea; anchors.fill: parent; onClicked: root.ringAction("stop") }
            }
        }
    }
}
