import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications

ShellRoot {
    id: root

    // One Quickshell process owns one PanelWindow per monitor. Keep UI state on
    // each PanelWindow, and use this registry only to route external IPC calls.
    property var islandPanels: ({})

    function registerIslandPanel(screenName, panel) {
        let panels = Object.assign({}, root.islandPanels)
        panels[screenName] = panel
        root.islandPanels = panels
    }

    function unregisterIslandPanel(screenName) {
        let panels = Object.assign({}, root.islandPanels)
        delete panels[screenName]
        root.islandPanels = panels
    }

    function panelForScreen(screenName) {
        if (screenName && screenName !== "all")
            return root.islandPanels[screenName] || null
        let names = Object.keys(root.islandPanels)
        return names.length ? root.islandPanels[names[0]] : null
    }

    function setPanelState(screenName, expandedValue, tabValue, subViewValue) {
        let panel = root.panelForScreen(screenName)
        if (!panel) return null
        if (expandedValue === true) {
            // El ipc hide marca la pantalla en hiddenScreens, y el binding de
            // visible de la ventana la apaga entera. Sin quitarlo de ahi, volver
            // a expandir la ventana no dibuja NADA: el estado era correcto y aun
            // asi no se veia. Pasaba con 7 scripts que llaman a hide (menu wifi,
            // menu bluetooth, launcher, powermenu, wallpaper, atajos), y hacia
            // que SUPER+V, es decir open-clipboard, solo abriera la primera vez.
            root.islandVisible = true
            if (screenName && screenName !== "all") {
                let hs = Object.assign({}, root.hiddenScreens)
                delete hs[screenName]
                root.hiddenScreens = hs
            }
        }
        if (expandedValue !== undefined) panel.expanded = expandedValue
        if (tabValue !== undefined) panel.currentTab = tabValue
        if (subViewValue !== undefined) panel.controlSubView = subViewValue
        return panel
    }

    function toggleBluetooth(screenName) {
        let panel = root.panelForScreen(screenName)
        if (panel && panel.expanded && panel.currentTab === 0 && panel.controlSubView === 2) {
            root.setPanelState(screenName, false)
            return "collapsed"
        }
        let p = root.setPanelState(screenName, true, 0, 2)
        if (!p) return "unavailable"
        root.btScanning = true
        btStatusProc.running = true
        root.refreshAllStates()
        return "bluetooth"
    }

    function anyPanelExpanded() {
        return Object.keys(root.islandPanels).some(name => root.islandPanels[name].expanded || root.islandPanels[name].sysMonExpanded)
    }

    function anyPanelSysMon() {
        return Object.keys(root.islandPanels).some(name => root.islandPanels[name].sysMonExpanded)
    }

    function toggleSysMon(screenName) {
        let panel = root.panelForScreen(screenName)
        if (!panel) {
            let names = Object.keys(root.islandPanels)
            if (names.length) panel = root.islandPanels[names[0]]
        }
        if (!panel) return "unavailable"
        root.islandVisible = true
        if (screenName && screenName !== "all") {
            let hs = Object.assign({}, root.hiddenScreens)
            delete hs[screenName]
            root.hiddenScreens = hs
        }
        if (panel.sysMonExpanded) {
            panel.sysMonExpanded = false
            return "collapsed"
        } else {
            panel.expanded = false
            panel.sysMonExpanded = true
            sysMonProc.running = true
            return "sysmon"
        }
    }

    function toggleLanguageInput(screenName) {
        let panel = root.panelForScreen(screenName)
        if (!panel) {
            let names = Object.keys(root.islandPanels)
            if (names.length) panel = root.islandPanels[names[0]]
        }
        if (!panel) return "unavailable"
        root.islandVisible = true
        if (screenName && screenName !== "all") {
            let hs = Object.assign({}, root.hiddenScreens)
            delete hs[screenName]
            root.hiddenScreens = hs
        }
        if (panel.langInputExpanded) {
            panel.langInputExpanded = false
            return "collapsed"
        } else {
            panel.expanded = false
            panel.sysMonExpanded = false
            panel.langInputExpanded = true
            langProc.running = true
            return "opened"
        }
    }

    function openLanguageInput(screenName) {
        let panel = root.panelForScreen(screenName)
        if (!panel) {
            let names = Object.keys(root.islandPanels)
            if (names.length) panel = root.islandPanels[names[0]]
        }
        if (!panel) return "unavailable"
        panel.expanded = false
        panel.sysMonExpanded = false
        panel.langInputExpanded = true
        langProc.running = true
        return "opened"
    }

    property var workspacesData: ({ active_id: 1, next_id: 2, count: 0, workspaces: [] })

    ListModel {
        id: workspacesModel
    }

    function updateWorkspacesModel(newList) {
        if (!newList || !Array.isArray(newList)) return
        let newIds = new Set(newList.map(w => w.id))
        for (let i = workspacesModel.count - 1; i >= 0; i--) {
            if (!newIds.has(workspacesModel.get(i).id)) {
                workspacesModel.remove(i)
            }
        }
        for (let item of newList) {
            let foundIndex = -1
            for (let i = 0; i < workspacesModel.count; i++) {
                if (workspacesModel.get(i).id === item.id) {
                    foundIndex = i
                    break
                }
            }
            if (foundIndex >= 0) {
                let cur = workspacesModel.get(foundIndex)
                if (cur.preview !== item.preview) workspacesModel.setProperty(foundIndex, "preview", item.preview)
                if (cur.is_active !== item.is_active) workspacesModel.setProperty(foundIndex, "is_active", item.is_active)
                if (cur.windows_count !== item.windows_count) workspacesModel.setProperty(foundIndex, "windows_count", item.windows_count)
                if (cur.monitor !== item.monitor) workspacesModel.setProperty(foundIndex, "monitor", item.monitor)
                if (cur.name !== item.name) workspacesModel.setProperty(foundIndex, "name", item.name)
            } else {
                let insertIdx = workspacesModel.count
                for (let i = 0; i < workspacesModel.count; i++) {
                    if (workspacesModel.get(i).id > item.id) {
                        insertIdx = i
                        break
                    }
                }
                workspacesModel.insert(insertIdx, {
                    id: item.id,
                    name: item.name || ("" + item.id),
                    monitor: item.monitor || "",
                    is_active: item.is_active || false,
                    windows_count: item.windows_count || 0,
                    preview: item.preview || ""
                })
            }
        }
    }

    function anyPanelWorkspaces() {
        return Object.keys(root.islandPanels).some(name => root.islandPanels[name].expanded && root.islandPanels[name].currentTab === 4)
    }

    function toggleWorkspaces(screenName) {
        let panel = root.panelForScreen(screenName)
        if (!panel) {
            let names = Object.keys(root.islandPanels)
            if (names.length) {
                screenName = names[0]
                panel = root.islandPanels[screenName]
            }
        }
        if (!panel) return "unavailable"
        if (panel.expanded && panel.currentTab === 4) {
            root.setPanelState(screenName, false)
            return "collapsed"
        } else {
            panel.sysMonExpanded = false
            root.setPanelState(screenName, true, 4, 0)
            workspacesProc.running = true
            return "workspaces"
        }
    }

    function anyPanelSubView(subView) {
        return Object.keys(root.islandPanels).some(name =>
            root.islandPanels[name].expanded && root.islandPanels[name].controlSubView === subView)
    }

    property string activePlayerTitle: ""
    property string activePlayerArtist: ""
    property bool isPlaying: false
    property real volumeLevel: 0.5
    property real brightnessLevel: 0.5

    // Notification state
    property bool notifActive: false
    property string notifAppName: ""
    property string notifSummary: ""
    property string notifBody: ""
    property string notifIcon: ""
    property var currentNotification: null
    property var notifHistory: []
    property int notifUnread: 0

    function notifTime() {
        var d = new Date()
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    }
    // ── Apps silenciadas ──
    function notifMuted(app) {
        let a = (app || "").toLowerCase().trim()
        if (a === "") return false
        return root.mutedApps.some(m => (m || "").toLowerCase() === a)
    }


    function notifToggleMute(app) {
        let a = (app || "").toLowerCase().trim()
        if (a === "") return
        let lista = root.mutedApps.slice()
        let i = lista.findIndex(m => (m || "").toLowerCase() === a)
        if (i >= 0) lista.splice(i, 1)
        else lista.push(a)
        root.mutedApps = lista
        if (i < 0) {
            root.notifHistory = root.notifHistory.filter(n => (n.app || "").toLowerCase() !== a)
        }
        root.notifMuteSave(lista)
    }

    // Guardar la lista. Un app por linea en un fichero de texto plano, no JSON:
    // el JSON exige escapar comillas dentro de la cadena del shell, y los nombres
    // vienen de las notificaciones, o sea que no son datos de los que uno pueda
    // fiarse. Aqui se sanean a [a-z0-9._ -] antes de escribir, asi que el
    // comando no puede salir de los argumentos.
    function notifMuteSave(lista) {
        let limpio = []
        for (let m of lista) {
            let n = (m || "").toLowerCase().replace(/[^a-z0-9._ -]/g, "").trim()
            if (n !== "") limpio.push(n)
        }
        // Cada nombre va entrecomillado: sin comillas, printf '%s\n' battery saver
        // imprime DOS lineas y una app que se llama "Battery Saver" acaba guardada
        // como dos apps distintas: battery y saver.
        let cmd = "mkdir -p $HOME/.config/rhythm && : > $HOME/.config/rhythm/muted-apps.txt"
        for (let n of limpio) cmd += " && printf '%s\\n' '" + n.replace(/'/g, "'\\''") + "' >> $HOME/.config/rhythm/muted-apps.txt"
        root.runCmd(cmd)
    }

    // Apps que ya han hablado alguna vez, mas las silenciadas: asi se puede
    // silenciar una app sin tener que esperar a que notifique otra vez.
    function notifKnownApps() {
        let seen = {}
        for (let n of root.notifHistory) seen[(n.app || "System").toLowerCase()] = n.app || "System"
        for (let m of root.mutedApps) seen[(m || "").toLowerCase()] = m
        return Object.keys(seen).sort()
    }

    // Cargar la lista al arrancar la isla. Un app por linea.
    Process {
        id: muteLoadProc
        running: true
        command: ["bash", "-c", "cat $HOME/.config/rhythm/muted-apps.txt 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lista = []
                for (let linea of text.split("\n")) {
                    let n = linea.trim()
                    if (n !== "") lista.push(n)
                }
                root.mutedApps = lista
            }
        }
    }

    function notifPush(app, summary, body) {
        var h = [{app: app || "System", summary: summary || "", body: body || "", time: root.notifTime()}].concat(root.notifHistory)
        root.notifHistory = h.slice(0, 30)
        root.notifUnread = Math.min(99, root.notifUnread + 1)
    }
    function notifOpenCenter(screenName) {
        if (root.currentNotification) root.currentNotification.dismiss()
        root.currentNotification = null
        root.notifActive = false
        root.notifUnread = 0
        // A pending pairing request has a short lifetime: show it instead of
        // the notification list, otherwise the request is only visible through
        // a notification that leads somewhere else.
        if (root.pairRequest.active && root.pairRequest.state === "pending") {
            root.setPanelState(screenName, true, 0, 6)
            return
        }
        root.setPanelState(screenName, true, 2, 0)
        root.refreshAllStates()
    }
    function notifClear() {
        root.notifHistory = []
        root.notifUnread = 0
    }

    NotificationServer {
        id: notifServer
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true

        onNotification: function(n) {
            // App silenciada: se descarta aqui y no se guarda ni se avisa. Va antes
            // que el filtro de palabras clave y que el DND, porque es una decision
            // del usuario sobre esa app concreta y no sobre el estado global.
            if (root.notifMuted(n.appName)) {
                n.dismiss()
                return
            }

            // Do Not Disturb: suppress banner toast, keep server-side history
            if (root.dndEnabled) {
                n.tracked = true
                root.notifPush(n.appName, n.summary, n.body)
                return
            }
            n.tracked = true
            const app = (n.appName || "").toLowerCase()
            const summary = (n.summary || "").toLowerCase()
            const body = (n.body || "").toLowerCase()
            const full = `${app} ${summary} ${body}`

            // Filtrar y silenciar notificaciones repetitivas de cambio de wallpaper / pywal / sync
            const ignoredKeywords = [
                "pywal", "wallpaper", "sincroniz", "fondo", "sddm", "waybar",
                "oh my posh", "colores", "tema actualizado", "aplicando",
                "nm-applet", "p10k", "recargado", "reiniciado", "mako"
            ]
            const isSpam = ignoredKeywords.some(kw => full.includes(kw))
            if (isSpam) {
                n.dismiss()
                return
            }

            root.notifPush(n.appName, n.summary, n.body)
            root.currentNotification = n
            root.notifAppName = n.appName || "System"
            root.notifSummary = n.summary || ""
            root.notifBody = n.body || ""
            root.notifIcon = n.appIcon || ""
            root.notifActive = true
            notifTimer.restart()
        }
    }

    Timer {
        id: notifTimer
        interval: 4500
        onTriggered: {
            root.notifActive = false
        }
    }

    property bool islandVisible: true
    property var hiddenScreens: ({})

    // Monitores con una ventana a pantalla completa, y por tanto con la isla
    // escondida. La isla vive en la capa Overlay, que Hyprland dibuja POR ENCIMA
    // de las ventanas en pantalla completa, asi que sin esto se ve encima del
    // video. El dock no sufre lo mismo porque usa la capa top.
    // Lo escribe island-fullscreens, que solo cuenta ventanas visibles y mapeadas
    // para no esconder la isla por un fullscreen de otro espacio de trabajo.
    property var fullscreenScreens: ({})

    // OTA System Update state
    property var otaData: ({
        status: "up_to_date",
        status_text: "System is up to date",
        has_updates: false,
        current_version: "v1.0.0",
        latest_version: "v1.0.0",
        dotfiles_branch: "main",
        dotfiles_behind: 0,
        dotfiles_ahead: 0,
        dotfiles_hash: "",
        remote_hash: "",
        pacman_updates: 0,
        pacman_list: [],
        kernel: "",
        last_checked: ""
    })
    property bool otaChecking: false
    property bool otaUpdating: false
    property string otaChangelogText: ""

    // GPU Profile state (Hybrid / Integrated / Dedicated)
    property var gpuData: ({
        has_hybrid: false,
        current_mode: "hybrid",
        active_gpu: "",
        igpu_name: "",
        dgpu_name: "",
        modes: []
    })

    // Hyprland live state
    property bool hyprAnim: true
    property bool hyprBlur: true
    property bool hyprShadow: true
    property int hyprRounding: 10
    property int hyprGaps: 10
    property bool perfMode: false

    // Hardware / Connectivity state
    property string wifiSsid: "Wi-Fi"
    property bool wifiEnabled: true
    property bool btEnabled: false
    property string kbLayout: "US"
    property var clipList: []
    property int clipCount: 0
    property int clipCopiedId: -1
    property string clipToast: ""

    // Resultado del ultimo cambio de limite de carga: sale debajo de los botones
    // de la tarjeta y se borra solo a los 4 s.
    property string battLimitMsg: ""
    property bool isMuted: false

    property var wifiList: []
    property string wifiConnectScreen: ""
    property string wifiConnectSsid: ""
    property string wifiConnectPassword: ""
    property bool wifiConnectRunning: false
    property bool wifiConnectPromptOnError: false

    function startWifiConnect(screenName, ssid, password, promptOnError) {
        let panel = root.panelForScreen(screenName)
        if (!panel) return
        if (root.wifiConnectRunning) {
            panel.wifiConnectState = "error"
            panel.wifiConnectMessage = "Another Wi-Fi connection is already in progress."
            return
        }
        root.wifiConnectScreen = screenName
        root.wifiConnectSsid = ssid
        root.wifiConnectPassword = password || ""
        root.wifiConnectPromptOnError = promptOnError === true
        if (root.wifiConnectPromptOnError) {
            panel.clearWifiPassword()
            panel.selectedWifiSsid = ""
        }
        panel.wifiConnectState = "connecting"
        panel.wifiConnectMessage = "Connecting to " + ssid + "…"
        root.wifiConnectRunning = true
        wifiConnectProc.running = true
    }
    property var btDevices: []
    property var audioSinks: []
    property var audioApps: []
    property string activeSinkName: "Default Output"
    property bool nightLightEnabled: false
    property int nightLightTemperature: 4500
    property int nightLightGamma: 100
    property bool nightLightScheduleEnabled: false
    property string nightLightScheduleStart: ""
    property string nightLightScheduleEnd: ""
    property bool caffeineEnabled: false
    property bool powerSaverEnabled: false
    property bool dndEnabled: false
    property bool dockEnabled: true
    // Active BlueZ pairing request. BlueZ asks the registered agent, never the
    // notification server, so bluetooth-pair-agent forwards it here.
    property var pairRequest: ({ active: false, id: "", kind: "", name: "", device: "", passkey: "", hint: "", state: "pending", pin: "" })

    function showPairingRequest(screenName, requestId, payload) {
        let data
        try {
            data = JSON.parse(payload)
        } catch (e) {
            return "invalid"
        }
        // Only one request can be answered at a time: close the previous one so
        // BlueZ is not left waiting for a reply that will never come.
        if (root.pairRequest.active && root.pairRequest.state === "pending" && root.pairRequest.id !== requestId) {
            root.runCmd("$HOME/.local/bin/bluetooth-pair-agent respond " + root.pairRequest.id + " reject")
        }
        root.pairRequest = {
            active: true,
            id: requestId,
            kind: data.kind || "confirm",
            name: data.name || data.device || "Bluetooth device",
            device: data.device || "",
            passkey: data.passkey || "",
            hint: data.hint || "",
            state: "pending",
            pin: ""
        }
        let panel = root.setPanelState(screenName, true, 0, 6)
        if (!panel) {
            // Unknown or missing monitor: open it everywhere so the request is
            // never invisible.
            Object.keys(root.islandPanels).forEach(name => {
                root.islandPanels[name].expanded = true
                root.islandPanels[name].currentTab = 0
                root.islandPanels[name].controlSubView = 6
            })
        }
        return "pairing"
    }

    function answerPairing(action) {
        if (!root.pairRequest.active || root.pairRequest.state !== "pending") return
        let cmd = "$HOME/.local/bin/bluetooth-pair-agent respond " + root.pairRequest.id + " " + action
        if (action === "accept" && root.pairRequest.kind === "pin" && root.pairRequest.pin.length > 0) {
            cmd += " '" + root.pairRequest.pin + "'"
        }
        root.runCmd(cmd)
        root.pairRequest = Object.assign({}, root.pairRequest, { state: action === "accept" ? "accepted" : "rejected" })
        pairRequestResetTimer.restart()
    }
    property var recState: ({ recording: false, pid: 0, elapsed: 0, elapsed_str: "00:00", file: "" })
    property var privacyState: ({ mic: false, cam: false })
    property var sysStats: ({ cpu_pct: 0, ram_used: "0G", ram_total: "0G", ram_pct: 0, disk_used: "0G", disk_pct: 0 })
    property var sysMonData: null

    // Baterias. battery-info devuelve count 0 y devices vacio si esta maquina no
    // tiene ninguna, y la seccion se oculta con visible en vez de con un texto de
    // "sin baterias": en un escritorio fijo no tiene que aparecer nada.
    property var batt: null

    // Apps silenciadas: sus notificaciones se descartan al llegar, sin banner ni
    // entrada en el historial. Un app por linea en muted-apps.txt.
    property var mutedApps: []
    property bool wifiScanning: false
    property bool btScanning: false
    property bool showUnnamedBtDevices: false
    readonly property var namedBtDevices: (root.btDevices || []).filter(d => d.has_name || d.paired || d.connected)
    readonly property var unnamedBtDevices: (root.btDevices || []).filter(d => !d.has_name && !d.paired && !d.connected)

    function refreshAllStates() {
        volProc.running = true
        briProc.running = true
        wifiProc.running = true
        btStatusProc.running = true
        perfProc.running = true
        battProc.running = true
        kbProc.running = true
        muteProc.running = true
        audioSinksProc.running = true
        audioAppsProc.running = true
        recStatusProc.running = true
        sysStatsProc.running = true
        nightLightCheckProc.running = true
        caffeineCheckProc.running = true
        powerSaveCheckProc.running = true
        dndCheckProc.running = true
        clipCountProc.running = true
        hyprStatusProc.running = true
        clipListProc.running = true
        otaStatusProc.running = true
        otaChangelogProc.running = true
        gpuStatusProc.running = true
        workspacesProc.running = true
        langProc.running = true
    }

    IpcHandler {
        target: "settings"
        function toggle(screenName: string): string {
            let panel = root.panelForScreen(screenName)
            if (!panel) return "unavailable"
            // Pasa por setPanelState y no por panel.expanded a pelo, para que
            // expandir quite la marca de hiddenScreens que deja el ipc hide.
            let abrir = !panel.expanded
            root.setPanelState(screenName, abrir, abrir ? 1 : undefined, abrir ? 0 : undefined)
            if (abrir) root.refreshAllStates()
            return abrir ? "expanded" : "collapsed"
        }
        function open(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 1, 0)
            if (!panel) return "unavailable"
            root.refreshAllStates()
            return "expanded"
        }
        function open_wifi(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 1)
            if (!panel) return "unavailable"
            root.wifiScanning = true
            wifiListProc.running = true
            root.refreshAllStates()
            return "expanded"
        }
        function open_bt(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 2)
            if (!panel) return "unavailable"
            root.btScanning = true
            btStatusProc.running = true
            root.refreshAllStates()
            return "expanded"
        }
        function open_hypr(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 1, 0)
            if (!panel) return "unavailable"
            root.refreshAllStates()
            return "expanded"
        }
        function open_audio(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 3)
            if (!panel) return "unavailable"
            audioSinksProc.running = true
            audioAppsProc.running = true
            root.refreshAllStates()
            return "expanded"
        }
        function close(screenName: string): string {
            let panel = root.setPanelState(screenName, false)
            return panel ? "collapsed" : "unavailable"
        }
    }

    IpcHandler {
        target: "island"
        function toggle(screenName: string): string {
            let panel = root.panelForScreen(screenName)
            if (!panel) return "unavailable"
            panel.expanded = !panel.expanded
            if (panel.expanded) {
                panel.currentTab = 0
                // Abrir la isla con una solicitud pendiente debe llevar al
                // aviso de emparejamiento, no a la vista de control.
                panel.controlSubView = root.pairRequest.active ? 6 : 0
                root.refreshAllStates()
            }
            return panel.expanded ? "expanded" : "collapsed"
        }
        function openWifi(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 1)
            if (!panel) return "unavailable"
            root.wifiScanning = true
            wifiListProc.running = true
            return "wifi"
        }
        function openBluetooth(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 2)
            if (!panel) return "unavailable"
            root.btScanning = true
            btStatusProc.running = true
            return "bluetooth"
        }
        function toggleBluetooth(screenName: string): string {
            return root.toggleBluetooth(screenName)
        }
        function openAudio(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 3)
            if (!panel) return "unavailable"
            audioSinksProc.running = true
            return "audio"
        }
        function openNightLight(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 5)
            if (!panel) return "unavailable"
            nightLightSettingsProc.running = true
            return "night-light"
        }
        function openControl(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 0, 0)
            if (!panel) return "unavailable"
            root.refreshAllStates()
            return "control"
        }
        function showPairingRequest(screenName: string, requestId: string, payload: string): string {
            return root.showPairingRequest(screenName, requestId, payload)
        }
        function openHyprland(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 1, 0)
            if (!panel) return "unavailable"
            root.refreshAllStates()
            return "hyprland"
        }
        // Estado real del panel de una pantalla. Para poder preguntar por que no se
        // ve la isla sin tener que adivinarlo por una captura.
        function state(screenName: string): string {
            let p = root.panelForScreen(screenName)
            if (!p) return "unavailable"
            return JSON.stringify({
                expanded: p.expanded,
                tab: p.currentTab,
                sub: p.controlSubView,
                hidden: root.hiddenScreens[screenName] === true,
                fullscreen: root.fullscreenScreens[screenName] === true,
                visible: p.visible
            })
        }
        function openBatteries(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 1, 7)
            if (!panel) return "unavailable"
            battProc.running = true
            return "batteries"
        }
        function open_gpu(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 1, 0)
            if (!panel) return "unavailable"
            gpuStatusProc.running = true
            return "gpu"
        }
        function openGpu(screenName: string): string {
            return open_gpu(screenName)
        }
        function toggleWorkspaces(screenName: string): string {
            return root.toggleWorkspaces(screenName)
        }
        function openWorkspaces(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 4, 0)
            if (!panel) return "unavailable"
            workspacesProc.running = true
            return "workspaces"
        }
        function openAlerts(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 2, 0)
            if (!panel) return "unavailable"
            root.notifUnread = 0
            return "alerts"
        }
        function openClips(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 3, 0)
            if (!panel) return "unavailable"
            clipListProc.running = true
            return "clips"
        }
        function toggleSysMon(screenName: string): string {
            return root.toggleSysMon(screenName)
        }
        function openSysMon(screenName: string): string {
            let panel = root.panelForScreen(screenName)
            if (!panel) {
                let names = Object.keys(root.islandPanels)
                if (names.length) panel = root.islandPanels[names[0]]
            }
            if (!panel) return "unavailable"
            root.islandVisible = true
            panel.expanded = false
            panel.sysMonExpanded = true
            sysMonProc.running = true
            return "sysmon"
        }
        function closeSysMon(screenName: string): string {
            let panel = root.panelForScreen(screenName)
            if (panel) panel.sysMonExpanded = false
            return "collapsed"
        }
        function toggleLanguageInput(screenName: string): string {
            return root.toggleLanguageInput(screenName)
        }
        function openLanguageInput(screenName: string): string {
            return root.openLanguageInput(screenName)
        }
        function closeLanguageInput(screenName: string): string {
            let panel = root.panelForScreen(screenName)
            if (panel) panel.langInputExpanded = false
            return "collapsed"
        }
        function reloadLanguage(screenName: string): string {
            langProc.running = true
            kbProc.running = true
            return "reloaded"
        }
        function openOta(screenName: string): string {
            let current = root.panelForScreen(screenName)
            if (!current) return "unavailable"
            let panel = root.setPanelState(screenName, true, current.currentTab, 4)
            if (!panel) return "unavailable"
            otaStatusProc.running = true
            otaChangelogProc.running = true
            return "ota"
        }
        function openNotifications(screenName: string): string {
            root.notifOpenCenter(screenName)
            return "notifications"
        }
        function openClipboard(screenName: string): string {
            let panel = root.setPanelState(screenName, true, 3, 0)
            if (!panel) return "unavailable"
            clipListProc.running = true
            return "clipboard"
        }
        function collapse(screenName: string): string {
            if (!screenName || screenName === "" || screenName === "all") {
                Object.keys(root.islandPanels).forEach(name => {
                    root.islandPanels[name].expanded = false
                })
                return "collapsed"
            }
            let panel = root.setPanelState(screenName, false)
            return panel ? "collapsed" : "unavailable"
        }
        function hide(screenName: string): string {
            if (!screenName || screenName === "" || screenName === "all") {
                Object.keys(root.islandPanels).forEach(name => root.islandPanels[name].expanded = false)
                root.islandVisible = false
                root.hiddenScreens = {}
            } else {
                let panel = root.panelForScreen(screenName)
                if (panel) panel.expanded = false
                let hs = Object.assign({}, root.hiddenScreens)
                hs[screenName] = true
                root.hiddenScreens = hs
            }
            return "hidden"
        }
        function reveal(screenName: string): string {
            root.islandVisible = true
            if (!screenName || screenName === "" || screenName === "all") {
                root.hiddenScreens = {}
            } else {
                let hs = Object.assign({}, root.hiddenScreens)
                delete hs[screenName]
                root.hiddenScreens = hs
            }
            return "revealed"
        }
    }

    IpcHandler {
        target: "theme"
        function reload(): string {
            walFile.reload()
            return "reloaded"
        }
    }

    // Live pywal colors
    property int _walReloadCounter: 0

    FileView {
        id: walFile
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"
        watchChanges: true
        onFileChanged: walFile.reload()
        onLoaded: root._walReloadCounter++
    }

    readonly property var walData: {
        const _dep = root._walReloadCounter
        try {
            return JSON.parse(walFile.text())
        } catch(e) {
            return null
        }
    }

    readonly property color colBg: walData?.special?.background ?? "#1e2130"
    readonly property color colFg: walData?.special?.foreground ?? "#dde2ea"
    readonly property color colAccent: walData?.colors?.color4 ?? "#C8B4C7"
    readonly property color colMuted: walData?.colors?.color8 ?? "#9a9ea3"
    readonly property color colSurface: Qt.rgba(colFg.r, colFg.g, colFg.b, 0.08)
    readonly property color colSurfaceHover: Qt.rgba(colFg.r, colFg.g, colFg.b, 0.16)
    readonly property color colBorder: Qt.rgba(colAccent.r, colAccent.g, colAccent.b, 0.25)


    // Current time & date exactly matching Waybar format: {:%H:%M:%S  -  %A, %d}
    property string timeStr: ""
    property string dayStr: ""
    property string clockStr: ""
    property string dateStr: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            
            const dayName = days[now.getDay()]
            const dayNum = now.getDate()
            const monthName = months[now.getMonth()]
            
            const hours = String(now.getHours()).padStart(2, '0')
            const mins = String(now.getMinutes()).padStart(2, '0')
            const secs = String(now.getSeconds()).padStart(2, '0')

            root.timeStr = `${hours}:${mins}:${secs}`
            root.dayStr = `${dayName}, ${dayNum}`
            // Exact Waybar format: {:%H:%M:%S  -  %A, %d}
            root.clockStr = `${root.timeStr}  -  ${root.dayStr}`
            root.dateStr = `${dayName}, ${monthName} ${dayNum}`
        }
    }

    // MPRIS tracking
    readonly property var players: Mpris.players.values
    readonly property var primaryPlayer: players.length > 0 ? players[0] : null

    onPrimaryPlayerChanged: updateMedia()

    Connections {
        target: root.primaryPlayer
        ignoreUnknownSignals: true
        function onPlaybackStateChanged() { root.updateMedia() }
        function onTrackTitleChanged() { root.updateMedia() }
        function onTrackArtistChanged() { root.updateMedia() }
    }

    function updateMedia() {
        if (root.primaryPlayer) {
            root.isPlaying = root.primaryPlayer.playbackState === MprisPlaybackState.Playing
            root.activePlayerTitle = root.primaryPlayer.trackTitle || ""
            root.activePlayerArtist = root.primaryPlayer.trackArtist || ""
        } else {
            root.isPlaying = false
            root.activePlayerTitle = ""
            root.activePlayerArtist = ""
        }
    }

    // Process helper to run quick commands with full environment
    function runCmd(cmd) {
        const envInit = "export XDG_RUNTIME_DIR=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"; " +
                        "[ -z \"$WAYLAND_DISPLAY\" ] && export WAYLAND_DISPLAY=\"wayland-1\"; " +
                        "[ -z \"$HYPRLAND_INSTANCE_SIGNATURE\" ] && export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t \"$XDG_RUNTIME_DIR/hypr/\" 2>/dev/null | grep -v '\\.lock$' | head -n1); "
        Quickshell.execDetached(["bash", "-c", envInit + cmd])
    }

    // Get live volume & brightness
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Read volume
            volProc.running = true
            // Read brightness
            briProc.running = true
        }
    }

    Process {
        id: volProc
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim()
                root.isMuted = raw.includes("[MUTED]")
                const match = raw.match(/Volume:\s+([0-9.]+)/)
                if (match && match[1]) {
                    const val = parseFloat(match[1])
                    if (!isNaN(val)) root.volumeLevel = Math.min(1.0, val)
                }
            }
        }
    }

    Process {
        id: briProc
        command: ["bash", "-c", "out=$(brightnessctl -c backlight -m 2>/dev/null | head -n1); [ -z \"$out\" ] && out=$(brightnessctl -m 2>/dev/null | head -n1); echo \"$out\" | awk -F, '{print $4}' | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = parseFloat(text.trim())
                if (!isNaN(val)) root.brightnessLevel = val / 100.0
            }
        }
    }

    Process {
        id: wifiProc
        command: ["bash", "-c", "nmcli radio wifi && nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2 | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                root.wifiEnabled = (lines[0] || "").trim() === "enabled"
                const ssid = (lines[1] || "").trim()
                if (!root.wifiEnabled) {
                    root.wifiSsid = "Disabled"
                } else if (ssid.length > 0) {
                    root.wifiSsid = ssid
                } else {
                    root.wifiSsid = "Disconnected"
                }
            }
        }
    }

    //  `btProc` estaba aquí para preguntar solo "¿está encendido?", pero
    //  escribía root.btEnabled y eso ya lo hace btStatusProc, que además trae
    //  discovering y la lista de aparatos. Dos procesos escribiendo la misma
    //  propiedad, cada uno con su propio ritmo, es la forma de que el estado
    //  parpadee. Se queda uno solo: el que lo sabe todo.

    Process {
        id: perfProc
        command: ["bash", "-c", "[ -f /tmp/hypr_performance_mode ] && echo 'perf' || echo 'normal'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.perfMode = text.trim() === "perf"
            }
        }
    }

    Process {
        id: clipListProc
        command: ["bash", "-c", "$HOME/.local/bin/clipboard-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.clipList = JSON.parse(text.trim())
                } catch(e) {
                    root.clipList = []
                }
            }
        }
    }

    Process {
        id: kbProc
        // kb-layout devuelve la abreviatura del layout ACTIVO segun lo que el
        // usuario configuro en input.kb_layout ("us,es" -> US / ES).
        //
        // Antes pedia active_keymap, que es el nombre del keymap de XKB:
        // "English (US)" frente a "Spanish". No es lo que el usuario escribe, y
        // como cambia de largo segun el idioma, el chip se redimensionaba en cada
        // cambio y parecia que se colapsaba al pulsarlo.
        command: ["bash", "-c", "$HOME/.local/bin/kb-layout"]
        stdout: StdioCollector {
            onStreamFinished: {
                const val = text.trim()
                root.kbLayout = val.length > 0 && val !== "null" ? val : "US"
            }

        }
    }

    property var langData: ({
        layouts: [
            { id: 0, code: "us", code_upper: "US", label: "English (US)", active: true },
            { id: 1, code: "es", code_upper: "ES", label: "Spanish (Spain)", active: false }
        ],
        active_index: 0,
        active_code: "US",
        active_name: "English (US)",
        current_hotkey: "None",
        current_hotkey_keys: [],
        hotkey_option: "",
        available_hotkeys: [],
        user_locale: "",
        user_locale_label: "",
        system_locale: "",
        system_locale_label: ""
    })

    // ── Internationalization (i18n) Engine ──
    readonly property string currentLangCode: {
        const envLoc = (Quickshell.env("LANG") || Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || "").toLowerCase()
        let loc = (root.langData?.user_locale || root.langData?.system_locale || envLoc || "es_ES.UTF-8").toLowerCase()
        if (loc === "c.utf-8" || loc === "c" || loc === "posix" || !loc) {
            loc = envLoc || "es_ES.UTF-8"
        }
        let code = loc.split("_")[0].split(".")[0].split("-")[0].split("@")[0]
        if (code === "cmn" || code === "yue" || code === "lzh" || code === "hak" || code === "nan" || code === "zh") return "zh"
        if (code === "nb" || code === "nn" || code === "no") return "no"
        if (code === "fil" || code === "tl") return "en"
        if (code === "ast") return "es"
        if (code === "br") return "fr"
        if (code === "cv" || code === "ba" || code === "sah" || code === "tt") return "ru"
        if (root.i18nStrings && root.i18nStrings[code] !== undefined) return code
        if (code === "es") return "es"
        return "en"
    }

    readonly property var i18nStrings: ({
        "es": {
                "nl_candle": "Vela",
                "nl_warm": "Cálido",
                "nl_balanced": "Equilibrado",
                "nl_daylight": "Día",
                "nl_optional_off": "Opcional · Desactivado",
                "ota_last_checked": "Última comprobación:",
                "ota_recently": "recientemente",
                "ota_behind": "atrás",
                "ota_loading_changelog": "Cargando registro de cambios...",
                "audio_active_apps": "app(s) activas",
                "bt_scanning_short": "Buscando cercanos...",
                "bt_devices_avail": "dispositivos disponibles",
                "bt_ready": "Listo para emparejar",
                "bt_hide_unnamed": "Ocultar",
                "bt_show_unnamed": "Mostrar",
                "bt_unnamed_desc": "dispositivos sin nombre (beacons)",
                "bat_devices": "dispositivos",
                "sysmon_threads_active": "Hilos activos",
                "sysmon_uptime": "Tiempo activo",
                "sysmon_processor": "Procesador",
                "sysmon_util": "Uso",
                "mod_media_nothing": "Nada en reproducción",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Activado",
                "mod_wifi_disabled": "Desactivado",
                "mod_wifi_connected": "Conectado",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Solicitud de emparejamiento pendiente",
                "mod_bt_enabled": "Activado",
                "mod_bt_disabled": "Desactivado",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Activado · clic para ocultar",
                "mod_dock_disabled": "Desactivado · clic para mostrar",
                "mod_notif": "Notificaciones",
                "mod_notif_unread": "sin leer",
                "mod_notif_none": "Sin notificaciones pendientes",
                "mod_nl": "Luz nocturna",
                "mod_nl_inactive": "Inactivo",
                "mod_caffeine_awake": "Modo despierto",
                "mod_caffeine_sleep": "Reposo normal",
                "mod_powersave_eco": "Eco activo",
                "mod_powersave_disabled": "Desactivado",
                "mod_perf": "Rendimiento",
                "mod_perf_boost": "Turbo máximo",
                "mod_perf_balanced": "Equilibrado",
                "mod_dnd_silenced": "Silenciado",
                "mod_dnd_sounds": "Sonidos activos",
                "mod_audio_muted": "Silenciado",
                "mod_record": "Grabar",
                "wifi_hide": "Ocultar",
                "wifi_show": "Mostrar",
                "wifi_saved": "Guardada",
                "bt_paired": "Emparejado",
                "bt_available": "Disponible",
                "bt_unnamed_device": "Dispositivo sin nombre",
                "audio_sink_active": "Activo",
                "audio_select": "Seleccionar",
                "hypr_enabled": "Activado",
                "hypr_disabled": "Desactivado",
                "hypr_max_perf": "Máximo rendimiento",
                "hypr_balanced": "Equilibrado",
                "hypr_power_source": "Fuente de alimentación",
                "hypr_batteries": "Baterías",
                "bat_charging": "Cargando",
                "bat_on_battery": "Con batería",
                "bat_ac_online": "Red eléctrica conectada",
                "bat_external_power": "Alimentación externa",
                "ws_active": "Activo",
                "ws_empty": "Espacio vacío",
                "nl_enabled": "Activado",
                "nl_disabled": "Desactivado",
                "nl_active_desc": "Filtro de luz azul activo",
                "nl_off_desc": "Filtro de luz azul apagado",
                "nl_schedule_hint": "Desactivado por defecto. Configura ambas horas (HH:MM 24h) para activarlo.",
                "nl_schedule_update": "Actualizar horario",
                "nl_schedule_enable": "Activar horario",
                "pair_waiting": "Esperando",
                "pair_done": "Completado",
                "pair_closed": "Cerrado",
                "pair_pin": "Introduce el PIN",
                "pair_auth": "Autorización",
                "pair_code": "Código de confirmación",
                "pair_none": "No hay solicitudes de emparejamiento pendientes.",
                "ota_available": "Actualización del sistema disponible",
                "ota_check": "Buscar actualizaciones",
                "ota_install": "Descargar e instalar",
                "ota_installing": "Instalando...",
                "sysmon_title": "Monitor del sistema (htop)",
                "sysmon_cli": "Terminal htop",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Actividad de núcleos CPU",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "Gráficos integrados estándar",
                "sysmon_top_proc": "Procesos principales",
                "sysmon_top_cpu": "Mayor CPU",
                "sysmon_top_mem": "Mayor Memoria",
                "sysmon_pid": "PID",
                "sysmon_user": "USUARIO",
                "sysmon_name": "NOMBRE",
                "sysmon_kill": "MATAR",
                "sysmon_kernel": "Núcleo: Linux ",
                "sysmon_esc_close": "ESC o clic fuera para cerrar",
                "lang_title": "Idioma y Entrada",
                "lang_subtitle": "AJUSTES DE TECLADO E IDIOMA",
                "lang_input_languages": "Distribuciones de teclado",
                "lang_active": "Activo",
                "lang_add_layout": "Añadir distribución de teclado",
                "lang_system_language": "Idioma del sistema",
                "lang_user_language": "Idioma de usuario actual:",
                "lang_change_display": "Cambiar mi idioma de pantalla",
                "lang_change_system": "Cambiar idioma del sistema (localectl)",
                "lang_footer_nav": "↑/↓ Navegar • Enter Seleccionar • Esc Cerrar",
                "lang_add_title": "Añadir distribución de teclado",
                "lang_search_layout": "Buscar idioma o país...",
                "lang_add_btn": "+ Añadir",
                "lang_select_display": "Seleccionar idioma de pantalla",
                "lang_select_system": "Seleccionar idioma del sistema (localectl)",
                "lang_search_locale": "Buscar idioma o localización...",
                "lang_select_btn": "Seleccionar",
                "tab_control": "Control",
                "tab_spaces": "Espacios",
                "tab_hypr": "Hyprland",
                "tab_alerts": "Alertas",
                "tab_clips": "Portapapeles",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Salida de audio",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notificaciones",
                "mod_nightlight": "Luz nocturna",
                "mod_caffeine": "Cafeína",
                "mod_powersave": "Ahorro de energía",
                "mod_performance": "Rendimiento",
                "mod_dnd": "No molestar",
                "mod_volume": "Volumen",
                "mod_brightness": "Brillo",
                "mod_picker": "Color",
                "mod_gallery": "Galería",
                "mod_random": "Aleatorio",
                "mod_tasks": "Tareas",
                "wifi_title": "Redes Wi-Fi disponibles",
                "wifi_back": "Volver",
                "wifi_connecting": "Conectando...",
                "wifi_connected": "Conectado",
                "wifi_disconnect": "Desconectar",
                "wifi_connect": "Conectar",
                "wifi_known": "Conocida",
                "wifi_scanning": "Escaneando redes Wi-Fi...",
                "wifi_none": "No se encontraron redes Wi-Fi.",
                "wifi_settings": "Configuración de red",
                "bt_title": "Dispositivos Bluetooth",
                "bt_back": "Volver",
                "bt_disabled_title": "Bluetooth desactivado",
                "bt_disabled_desc": "Activa Bluetooth para buscar y conectar dispositivos cercanos",
                "bt_turn_on": "Activar Bluetooth",
                "bt_scanning": "Buscando dispositivos Bluetooth cercanos...",
                "bt_none_found": "No se encontraron dispositivos. Haz clic en Buscar arriba.",
                "bt_unnamed": "Dispositivo sin nombre",
                "bt_connected": "Conectado",
                "bt_disconnected": "Desconectado",
                "bt_pair": "Emparejar",
                "bt_disconnect": "Desconectar",
                "bt_connect": "Conectar",
                "bt_remove": "Olvidar",
                "bt_manager": "Gestor de Bluetooth",
                "audio_title": "Dispositivos de salida de audio",
                "audio_back": "Volver",
                "audio_none": "No se detectaron dispositivos de salida.",
                "audio_mixer": "Mezclador de volumen de aplicaciones",
                "audio_no_apps": "No hay aplicaciones reproduciendo audio.",
                "audio_pavucontrol": "Control de volumen (Pavucontrol)",
                "hypr_title": "Ajustes del compositor Hyprland",
                "hypr_animations": "Animaciones",
                "hypr_blur": "Desenfoque",
                "hypr_shadows": "Sombras",
                "hypr_perf": "Modo rendimiento",
                "hypr_gpu_profile": "Perfil gráfico",
                "hypr_gpu_integrated": "Integrada",
                "hypr_gpu_igpu_only": "Solo iGPU",
                "hypr_gpu_hybrid": "Híbrido",
                "hypr_gpu_prime_auto": "PRIME automático",
                "hypr_gpu_dedicated": "Dedicada",
                "hypr_gpu_dgpu_only": "Solo dGPU",
                "hypr_rounding": "Bordes redondeados:",
                "hypr_gaps": "Espaciado (Gaps):",
                "hypr_split": "Dividir división",
                "hypr_reload": "Recargar",
                "bat_ac_active": "Alimentación por CA activa",
                "bat_power": "Potencia",
                "bat_volt": "Voltaje",
                "bat_health": "Salud",
                "bat_full": "Capacidad",
                "bat_cycles": "Ciclos",
                "bat_limit": "Límite",
                "notif_title": "Notificaciones",
                "notif_back": "Volver",
                "notif_clear": "Borrar todo",
                "notif_tap_open": "Toca para abrir la aplicación",
                "notif_muted_apps": "Aplicaciones silenciadas",
                "notif_muted_desc": "Las notificaciones de aplicaciones silenciadas se descartan antes de llegar a la lista.",
                "notif_empty": "No hay notificaciones aún.",
                "clip_title": "Portapapeles",
                "clip_clear": "Borrar todo",
                "clip_empty": "Vacío: copia algo primero",
                "ws_overview": "Vista de espacios de trabajo",
                "ws_space": "Espacio",
                "ws_add": "Añadir espacio",
                "ws_footer": "Super + Tab alterna la vista • Clic para cambiar • 󰅖 elimina el espacio",
                "nl_title": "Luz nocturna",
                "nl_back": "Volver",
                "nl_temp": "Temperatura de color",
                "nl_temp_desc": "Valores bajos son más cálidos; valores altos son más neutros.",
                "nl_gamma": "Gamma de pantalla",
                "nl_gamma_desc": "Menor gamma atenúa la imagen; 100% es brillo normal.",
                "nl_schedule": "Horario automático",
                "nl_start": "Inicio",
                "nl_end": "Fin",
                "nl_disable": "Desactivar",
                "nl_reset": "Restablecer valores · 4500 K · 100%",
                "pair_title": "Solicitud de emparejamiento",
                "pair_back": "Volver",
                "pair_reject": "Rechazar",
                "pair_confirm": "Confirmar",
                "pair_empty": "No hay solicitudes de emparejamiento pendientes.",
                "ota_title": "Actualización del sistema",
                "ota_back": "Volver",
                "ota_uptodate": "El sistema está actualizado",
                "ota_checking": "Buscando actualizaciones...",
                "ota_new": "Nueva actualización",
                "ota_current": "Versión actual",
                "ota_target": "Versión objetivo",
                "ota_kernel": "Núcleo Linux",
                "ota_channel": "Canal de lanzamiento",
                "ota_changelog": "Registro de cambios e historial"
        },
        "en": {
                "nl_candle": "Candle",
                "nl_warm": "Warm",
                "nl_balanced": "Balanced",
                "nl_daylight": "Daylight",
                "nl_optional_off": "Optional · Off",
                "ota_last_checked": "Last checked:",
                "ota_recently": "recently",
                "ota_behind": "behind",
                "ota_loading_changelog": "Loading changelog...",
                "audio_active_apps": "active app(s)",
                "bt_scanning_short": "Scanning nearby...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "devices",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Saved",
                "bt_paired": "Paired",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Charging",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Check for update",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "System Monitor (htop)",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU Cores Activity",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Language & Input",
                "lang_subtitle": "KEYBOARD AND LANGUAGE SETTINGS",
                "lang_input_languages": "Input Languages",
                "lang_active": "Active",
                "lang_add_layout": "Add keyboard layout",
                "lang_system_language": "System Language",
                "lang_user_language": "Current User Language:",
                "lang_change_display": "Change my display language",
                "lang_change_system": "Change system language (localectl)",
                "lang_footer_nav": "↑/↓ Navigate • Enter Select • Esc Close",
                "lang_add_title": "Add Keyboard Layout",
                "lang_search_layout": "Search language or country...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Select Display Language",
                "lang_select_system": "Select System Language (localectl)",
                "lang_search_locale": "Search language or locale...",
                "lang_select_btn": "Select",
                "tab_control": "Control",
                "tab_spaces": "Spaces",
                "tab_hypr": "Hypr",
                "tab_alerts": "Alerts",
                "tab_clips": "Clips",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Available Wi-Fi Networks",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Connected",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Open Network Settings",
                "bt_title": "Bluetooth Devices",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Turn On Bluetooth",
                "bt_scanning": "Scanning nearby Bluetooth devices...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Connected",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Audio Output Devices",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Open Audio Settings (Pavucontrol)",
                "hypr_title": "Real-time Hyprland Compositor Settings",
                "hypr_animations": "Animations",
                "hypr_blur": "Blur Effect",
                "hypr_shadows": "Shadows",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Rounding:",
                "hypr_gaps": "Gaps:",
                "hypr_split": "Split Layout",
                "hypr_reload": "Reload",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Full",
                "bat_cycles": "Cycles",
                "bat_limit": "Limit",
                "notif_title": "Notifications",
                "notif_back": "Back",
                "notif_clear": "Clear all",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "No notifications yet.",
                "clip_title": "Clipboard",
                "clip_clear": "Clear all",
                "clip_empty": "Empty: copy something first",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Night Light",
                "nl_back": "Back",
                "nl_temp": "Color temperature",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Display gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Automatic schedule",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Pairing Request",
                "pair_back": "Back",
                "pair_reject": "Reject",
                "pair_confirm": "Confirm",
                "pair_empty": "No pending pairing request.",
                "ota_title": "System Update",
                "ota_back": "Back",
                "ota_uptodate": "System is up to date",
                "ota_checking": "Checking for updates...",
                "ota_new": "New Update",
                "ota_current": "Current Version",
                "ota_target": "Target Release",
                "ota_kernel": "Linux Kernel",
                "ota_channel": "Release Channel",
                "ota_changelog": "Changelog & History"
        },
        "fr": {
                "nl_candle": "Bougie",
                "nl_warm": "Chaud",
                "nl_balanced": "Équilibré",
                "nl_daylight": "Lumière du jour",
                "nl_optional_off": "Optionnel · Désactivé",
                "ota_last_checked": "Dernière vérification :",
                "ota_recently": "récemment",
                "ota_behind": "en retard",
                "ota_loading_changelog": "Chargement du journal des modifications...",
                "audio_active_apps": "application(s) active(s)",
                "bt_scanning_short": "Recherche à proximité...",
                "bt_devices_avail": "appareils disponibles",
                "bt_ready": "Prêt pour l'appairage",
                "bt_hide_unnamed": "Masquer",
                "bt_show_unnamed": "Afficher",
                "bt_unnamed_desc": "appareils sans nom (balises)",
                "bat_devices": "appareils",
                "sysmon_threads_active": "Threads actifs",
                "sysmon_uptime": "Temps d'activité",
                "sysmon_processor": "Processeur",
                "sysmon_util": "Utilisation",
                "mod_media_nothing": "Aucune lecture",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Activé",
                "mod_wifi_disabled": "Désactivé",
                "mod_wifi_connected": "Connecté",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Demande d'appairage en attente",
                "mod_bt_enabled": "Activé",
                "mod_bt_disabled": "Désactivé",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Activé · cliquer pour masquer",
                "mod_dock_disabled": "Désactivé · cliquer pour afficher",
                "mod_notif": "Notifications",
                "mod_notif_unread": "non lu(s)",
                "mod_notif_none": "Aucune notification",
                "mod_nl": "Éclairage nocturne",
                "mod_nl_inactive": "Inactif",
                "mod_caffeine_awake": "Mode éveillé",
                "mod_caffeine_sleep": "Veille normale",
                "mod_powersave_eco": "Mode Éco",
                "mod_powersave_disabled": "Désactivé",
                "mod_perf": "Performance",
                "mod_perf_boost": "Turbo Max",
                "mod_perf_balanced": "Équilibré",
                "mod_dnd_silenced": "Silencieux",
                "mod_dnd_sounds": "Sons actifs",
                "mod_audio_muted": "Muet",
                "mod_record": "Enregistrer",
                "wifi_hide": "Masquer",
                "wifi_show": "Afficher",
                "wifi_saved": "Enregistré",
                "bt_paired": "Appairé",
                "bt_available": "Disponible",
                "bt_unnamed_device": "Appareil sans nom",
                "audio_sink_active": "Actif",
                "audio_select": "Sélectionner",
                "hypr_enabled": "Activé",
                "hypr_disabled": "Désactivé",
                "hypr_max_perf": "Performance maximale",
                "hypr_balanced": "Équilibré",
                "hypr_power_source": "Source d'alimentation",
                "hypr_batteries": "Batteries",
                "bat_charging": "En charge",
                "bat_on_battery": "Sur batterie",
                "bat_ac_online": "Secteur connecté",
                "bat_external_power": "Alimentation externe",
                "ws_active": "Actif",
                "ws_empty": "Espace vide",
                "nl_enabled": "Activé",
                "nl_disabled": "Désactivé",
                "nl_active_desc": "Le filtre de lumière bleue est actif",
                "nl_off_desc": "Le filtre de lumière bleue est désactivé",
                "nl_schedule_hint": "Désactivé par défaut. Définissez les deux heures (HH:MM 24h) pour l'activer.",
                "nl_schedule_update": "Mettre à jour la planification",
                "nl_schedule_enable": "Activer la planification",
                "pair_waiting": "En attente",
                "pair_done": "Terminé",
                "pair_closed": "Fermé",
                "pair_pin": "Entrez le code PIN",
                "pair_auth": "Autorisation",
                "pair_code": "Code de confirmation",
                "pair_none": "Aucune demande d'appairage en attente.",
                "ota_available": "Mise à jour système disponible",
                "ota_check": "Vérifier les mises à jour",
                "ota_install": "Télécharger et installer",
                "ota_installing": "Installation en cours...",
                "sysmon_title": "Moniteur système (htop)",
                "sysmon_cli": "CLI htop",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Activité des cœurs CPU",
                "sysmon_gpu": "GPU :",
                "sysmon_integrated_gpu": "Carte graphique intégrée standard",
                "sysmon_top_proc": "Top Processus",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Mémoire",
                "sysmon_pid": "PID",
                "sysmon_user": "UTILISATEUR",
                "sysmon_name": "NOM",
                "sysmon_kill": "ARRÊTER",
                "sysmon_kernel": "Noyau : Linux ",
                "sysmon_esc_close": "ÉCHAP ou clic extérieur pour fermer",
                "lang_title": "Langue & Saisie",
                "lang_subtitle": "PARAMÈTRES DE CLAVIER ET LANGUE",
                "lang_input_languages": "Langues de saisie",
                "lang_active": "Actif",
                "lang_add_layout": "Ajouter une disposition",
                "lang_system_language": "Langue du système",
                "lang_user_language": "Langue utilisateur actuelle :",
                "lang_change_display": "Changer ma langue d'affichage",
                "lang_change_system": "Changer la langue du système (localectl)",
                "lang_footer_nav": "↑/↓ Naviguer • Entrée Sélectionner • Échap Fermer",
                "lang_add_title": "Ajouter une disposition de clavier",
                "lang_search_layout": "Rechercher langue ou pays...",
                "lang_add_btn": "+ Ajouter",
                "lang_select_display": "Choisir la langue d'affichage",
                "lang_select_system": "Choisir la langue du système (localectl)",
                "lang_search_locale": "Rechercher une langue ou locale...",
                "lang_select_btn": "Sélectionner",
                "tab_control": "Contrôle",
                "tab_spaces": "Espaces",
                "tab_hypr": "Hypr",
                "tab_alerts": "Alertes",
                "tab_clips": "Clips",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Sortie audio",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Lumière nocturne",
                "mod_caffeine": "Caféine",
                "mod_powersave": "Économie d'énergie",
                "mod_performance": "Performance",
                "mod_dnd": "Ne pas déranger",
                "mod_volume": "Volume",
                "mod_brightness": "Luminosité",
                "mod_picker": "Pipette",
                "mod_gallery": "Galerie",
                "mod_random": "Aléatoire",
                "mod_tasks": "Tâches",
                "wifi_title": "Réseaux Wi-Fi disponibles",
                "wifi_back": "Retour",
                "wifi_connecting": "Connexion en cours...",
                "wifi_connected": "Connecté",
                "wifi_disconnect": "Déconnecter",
                "wifi_connect": "Connecter",
                "wifi_known": "Connu",
                "wifi_scanning": "Recherche de réseaux Wi-Fi...",
                "wifi_none": "Aucun réseau Wi-Fi trouvé.",
                "wifi_settings": "Ouvrir les paramètres réseau",
                "bt_title": "Périphériques Bluetooth",
                "bt_back": "Retour",
                "bt_disabled_title": "Le Bluetooth est désactivé",
                "bt_disabled_desc": "Activez le Bluetooth pour détecter et connecter des appareils",
                "bt_turn_on": "Activer le Bluetooth",
                "bt_scanning": "Recherche d'appareils Bluetooth...",
                "bt_none_found": "Aucun appareil trouvé. Cliquez sur Rechercher ci-dessus.",
                "bt_unnamed": "Appareil sans nom",
                "bt_connected": "Connecté",
                "bt_disconnected": "Déconnecté",
                "bt_pair": "Appairer",
                "bt_disconnect": "Déconnecter",
                "bt_connect": "Connecter",
                "bt_remove": "Supprimer",
                "bt_manager": "Gestionnaire Bluetooth",
                "audio_title": "Périphériques de sortie audio",
                "audio_back": "Retour",
                "audio_none": "Aucun périphérique audio détecté.",
                "audio_mixer": "Mélangeur de volume des applications",
                "audio_no_apps": "Aucun flux audio d'application actif.",
                "audio_pavucontrol": "Paramètres audio (Pavucontrol)",
                "hypr_title": "Paramètres du compositeur Hyprland",
                "hypr_animations": "Animations",
                "hypr_blur": "Effet de flou",
                "hypr_shadows": "Ombres",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Profil graphique",
                "hypr_gpu_integrated": "Intégré",
                "hypr_gpu_igpu_only": "iGPU seul",
                "hypr_gpu_hybrid": "Hybride",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dédié",
                "hypr_gpu_dgpu_only": "dGPU seul",
                "hypr_rounding": "Arrondi :",
                "hypr_gaps": "Espacement :",
                "hypr_split": "Disposition divisée",
                "hypr_reload": "Recharger",
                "bat_ac_active": "Alimentation directe active",
                "bat_power": "Puissance",
                "bat_volt": "Tension",
                "bat_health": "Santé",
                "bat_full": "Plein",
                "bat_cycles": "Cycles",
                "bat_limit": "Limite",
                "notif_title": "Notifications",
                "notif_back": "Retour",
                "notif_clear": "Tout effacer",
                "notif_tap_open": "Appuyez pour ouvrir",
                "notif_muted_apps": "Applications muettes",
                "notif_muted_desc": "Les notifications des apps muettes sont ignorées.",
                "notif_empty": "Aucune notification pour le moment.",
                "clip_title": "Presse-papiers",
                "clip_clear": "Tout effacer",
                "clip_empty": "Vide : copiez quelque chose d'abord",
                "ws_overview": "Aperçu des espaces",
                "ws_space": "Espace",
                "ws_add": "Ajouter un espace",
                "ws_footer": "Super + Tab bascule l'aperçu • Clic pour changer • 󰅖 supprime l'espace",
                "nl_title": "Lumière nocturne",
                "nl_back": "Retour",
                "nl_temp": "Température de couleur",
                "nl_temp_desc": "Les valeurs basses sont plus chaudes ; les plus hautes sont neutres.",
                "nl_gamma": "Gamma de l'affichage",
                "nl_gamma_desc": "Un gamma plus faible assombrit l'image ; 100% est la luminosité normale.",
                "nl_schedule": "Planification automatique",
                "nl_start": "Début",
                "nl_end": "Fin",
                "nl_disable": "Désactiver",
                "nl_reset": "Réinitialiser · 4500 K · 100%",
                "pair_title": "Demande d'appairage",
                "pair_back": "Retour",
                "pair_reject": "Refuser",
                "pair_confirm": "Confirmer",
                "pair_empty": "Aucune demande d'appairage en attente.",
                "ota_title": "Mise à jour système",
                "ota_back": "Retour",
                "ota_uptodate": "Le système est à jour",
                "ota_checking": "Recherche de mises à jour...",
                "ota_new": "Nouvelle mise à jour",
                "ota_current": "Version actuelle",
                "ota_target": "Version cible",
                "ota_kernel": "Noyau Linux",
                "ota_channel": "Canal de sortie",
                "ota_changelog": "Journal des modifications & historique"
        },
        "de": {
                "nl_candle": "Kerze",
                "nl_warm": "Warm",
                "nl_balanced": "Ausgewogen",
                "nl_daylight": "Tageslicht",
                "nl_optional_off": "Optional · Aus",
                "ota_last_checked": "Zuletzt geprüft:",
                "ota_recently": "kürzlich",
                "ota_behind": "hinterher",
                "ota_loading_changelog": "Änderungsprotokoll wird geladen...",
                "audio_active_apps": "aktive App(s)",
                "bt_scanning_short": "Suche in der Nähe...",
                "bt_devices_avail": "Geräte verfügbar",
                "bt_ready": "Bereit zum Koppeln",
                "bt_hide_unnamed": "Ausblenden",
                "bt_show_unnamed": "Anzeigen",
                "bt_unnamed_desc": "unbenannte Geräte (Beacons)",
                "bat_devices": "Geräte",
                "sysmon_threads_active": "Aktive Threads",
                "sysmon_uptime": "Betriebszeit",
                "sysmon_processor": "Prozessor",
                "sysmon_util": "Auslastung",
                "mod_media_nothing": "Keine Wiedergabe",
                "mod_wifi": "WLAN",
                "mod_wifi_enabled": "Aktiviert",
                "mod_wifi_disabled": "Deaktiviert",
                "mod_wifi_connected": "Verbunden",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Ausstehende Kopplungsanfrage",
                "mod_bt_enabled": "Aktiviert",
                "mod_bt_disabled": "Deaktiviert",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Aktiviert · Klick zum Ausblenden",
                "mod_dock_disabled": "Deaktiviert · Klick zum Anzeigen",
                "mod_notif": "Benachrichtigungen",
                "mod_notif_unread": "ungelesen",
                "mod_notif_none": "Keine ungelesenen",
                "mod_nl": "Nachtlicht",
                "mod_nl_inactive": "Inaktiv",
                "mod_caffeine_awake": "Wachmodus",
                "mod_caffeine_sleep": "Normaler Ruhezustand",
                "mod_powersave_eco": "Eco aktiv",
                "mod_powersave_disabled": "Deaktiviert",
                "mod_perf": "Leistung",
                "mod_perf_boost": "Maximaler Turbo",
                "mod_perf_balanced": "Ausgewogen",
                "mod_dnd_silenced": "Stummgeschaltet",
                "mod_dnd_sounds": "Töne aktiv",
                "mod_audio_muted": "Stumm",
                "mod_record": "Aufnehmen",
                "wifi_hide": "Ausblenden",
                "wifi_show": "Anzeigen",
                "wifi_saved": "Gespeichert",
                "bt_paired": "Gekoppelt",
                "bt_available": "Verfügbar",
                "bt_unnamed_device": "Unbenanntes Gerät",
                "audio_sink_active": "Aktiv",
                "audio_select": "Auswählen",
                "hypr_enabled": "Aktiviert",
                "hypr_disabled": "Deaktiviert",
                "hypr_max_perf": "Maximale Leistung",
                "hypr_balanced": "Ausgewogen",
                "hypr_power_source": "Stromquelle",
                "hypr_batteries": "Akkus",
                "bat_charging": "Wird geladen",
                "bat_on_battery": "Akkubetrieb",
                "bat_ac_online": "Netzbetrieb",
                "bat_external_power": "Externe Stromversorgung",
                "ws_active": "Aktiv",
                "ws_empty": "Leerer Bereich",
                "nl_enabled": "Aktiviert",
                "nl_disabled": "Deaktiviert",
                "nl_active_desc": "Blaulichtfilter ist aktiv",
                "nl_off_desc": "Blaulichtfilter ist aus",
                "nl_schedule_hint": "Standardmäßig aus. Beide Zeiten (24h HH:MM) einstellen zum Aktivieren.",
                "nl_schedule_update": "Zeitplan aktualisieren",
                "nl_schedule_enable": "Zeitplan aktivieren",
                "pair_waiting": "Warten",
                "pair_done": "Fertig",
                "pair_closed": "Geschlossen",
                "pair_pin": "PIN eingeben",
                "pair_auth": "Autorisierung",
                "pair_code": "Bestätigungscode",
                "pair_none": "Keine ausstehende Kopplungsanfrage.",
                "ota_available": "Systemaktualisierung verfügbar",
                "ota_check": "Nach Updates suchen",
                "ota_install": "Herunterladen & Installieren",
                "ota_installing": "Wird installiert...",
                "sysmon_title": "Systemmonitor (htop)",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU-Kerne Aktivität",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "Integrierte Standardgrafik",
                "sysmon_top_proc": "Top-Prozesse",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Speicher",
                "sysmon_pid": "PID",
                "sysmon_user": "BENUTZER",
                "sysmon_name": "NAME",
                "sysmon_kill": "BEENDEN",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC oder außen klicken zum Schließen",
                "lang_title": "Sprache & Eingabe",
                "lang_subtitle": "TASTATUR- UND SPRACHEINSTELLUNGEN",
                "lang_input_languages": "Eingabesprachen",
                "lang_active": "Aktiv",
                "lang_add_layout": "Tastaturbelegung hinzufügen",
                "lang_system_language": "Systemsprache",
                "lang_user_language": "Aktuelle Benutzersprache:",
                "lang_change_display": "Anzeigesprache ändern",
                "lang_change_system": "Systemsprache ändern (localectl)",
                "lang_footer_nav": "↑/↓ Navigieren • Enter Auswählen • Esc Schließen",
                "lang_add_title": "Tastaturbelegung hinzufügen",
                "lang_search_layout": "Sprache oder Land suchen...",
                "lang_add_btn": "+ Hinzufügen",
                "lang_select_display": "Anzeigesprache auswählen",
                "lang_select_system": "Systemsprache auswählen (localectl)",
                "lang_search_locale": "Sprache oder Region suchen...",
                "lang_select_btn": "Auswählen",
                "tab_control": "Steuerung",
                "tab_spaces": "Bereiche",
                "tab_hypr": "Hypr",
                "tab_alerts": "Hinweise",
                "tab_clips": "Ablage",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio-Ausgang",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Benachrichtigungen",
                "mod_nightlight": "Nachtlicht",
                "mod_caffeine": "Koffein",
                "mod_powersave": "Energiesparmodus",
                "mod_performance": "Leistung",
                "mod_dnd": "Bitte nicht stören",
                "mod_volume": "Lautstärke",
                "mod_brightness": "Helligkeit",
                "mod_picker": "Pipette",
                "mod_gallery": "Galerie",
                "mod_random": "Zufall",
                "mod_tasks": "Aufgaben",
                "wifi_title": "Verfügbare WLAN-Netzwerke",
                "wifi_back": "Zurück",
                "wifi_connecting": "Verbindung wird hergestellt...",
                "wifi_connected": "Verbunden",
                "wifi_disconnect": "Trennen",
                "wifi_connect": "Verbinden",
                "wifi_known": "Bekannt",
                "wifi_scanning": "WLAN-Netzwerke werden gesucht...",
                "wifi_none": "Keine WLAN-Netzwerke gefunden.",
                "wifi_settings": "Netzwerkeinstellungen öffnen",
                "bt_title": "Bluetooth-Geräte",
                "bt_back": "Zurück",
                "bt_disabled_title": "Bluetooth ist deaktiviert",
                "bt_disabled_desc": "Bluetooth einschalten, um Geräte in der Nähe zu verbinden",
                "bt_turn_on": "Bluetooth einschalten",
                "bt_scanning": "Suche nach Bluetooth-Geräten...",
                "bt_none_found": "Keine Geräte gefunden. Klicke oben auf Suchen.",
                "bt_unnamed": "Unbenanntes Gerät",
                "bt_connected": "Verbunden",
                "bt_disconnected": "Getrennt",
                "bt_pair": "Koppeln",
                "bt_disconnect": "Trennen",
                "bt_connect": "Verbinden",
                "bt_remove": "Entfernen",
                "bt_manager": "Bluetooth-Manager",
                "audio_title": "Audio-Ausgabegeräte",
                "audio_back": "Zurück",
                "audio_none": "Keine Audiogeräte erkannt.",
                "audio_mixer": "Anwendungs-Lautstärkemixer",
                "audio_no_apps": "Keine aktiven Audiostreams.",
                "audio_pavucontrol": "Audioeinstellungen (Pavucontrol)",
                "hypr_title": "Hyprland Compositor Einstellungen",
                "hypr_animations": "Animationen",
                "hypr_blur": "Unschärfeeffekt",
                "hypr_shadows": "Schatten",
                "hypr_perf": "Leistung",
                "hypr_gpu_profile": "Grafikprofil",
                "hypr_gpu_integrated": "Integriert",
                "hypr_gpu_igpu_only": "Nur iGPU",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dediziert",
                "hypr_gpu_dgpu_only": "Nur dGPU",
                "hypr_rounding": "Rundung:",
                "hypr_gaps": "Abstände:",
                "hypr_split": "Geteiltes Layout",
                "hypr_reload": "Neu laden",
                "bat_ac_active": "Direkte Stromversorgung aktiv",
                "bat_power": "Leistung",
                "bat_volt": "Spannung",
                "bat_health": "Zustand",
                "bat_full": "Voll",
                "bat_cycles": "Zyklen",
                "bat_limit": "Limit",
                "notif_title": "Benachrichtigungen",
                "notif_back": "Zurück",
                "notif_clear": "Alle löschen",
                "notif_tap_open": "Tippen zum Öffnen",
                "notif_muted_apps": "Stumme Apps",
                "notif_muted_desc": "Benachrichtigungen von stummen Apps werden verworfen.",
                "notif_empty": "Noch keine Benachrichtigungen.",
                "clip_title": "Zwischenablage",
                "clip_clear": "Alle leeren",
                "clip_empty": "Leer: Zuerst etwas kopieren",
                "ws_overview": "Arbeitsbereichsübersicht",
                "ws_space": "Bereich",
                "ws_add": "Bereich hinzufügen",
                "ws_footer": "Super + Tab schaltet Übersicht um • Klick zum Wechseln • 󰅖 entfernt Bereich",
                "nl_title": "Nachtlicht",
                "nl_back": "Zurück",
                "nl_temp": "Farbtemperatur",
                "nl_temp_desc": "Niedrigere Werte sind wärmer; höhere wirken neutraler.",
                "nl_gamma": "Bildschirm-Gamma",
                "nl_gamma_desc": "Niedrigeres Gamma dunkelt ab; 100% ist normal.",
                "nl_schedule": "Automatischer Zeitplan",
                "nl_start": "Start",
                "nl_end": "Ende",
                "nl_disable": "Deaktivieren",
                "nl_reset": "Standard · 4500 K · 100%",
                "pair_title": "Kopplungsanfrage",
                "pair_back": "Zurück",
                "pair_reject": "Ablehnen",
                "pair_confirm": "Bestätigen",
                "pair_empty": "Keine ausstehende Kopplungsanfrage.",
                "ota_title": "Systemaktualisierung",
                "ota_back": "Zurück",
                "ota_uptodate": "System ist auf dem neuesten Stand",
                "ota_checking": "Nach Updates suchen...",
                "ota_new": "Neues Update",
                "ota_current": "Aktuelle Version",
                "ota_target": "Zielversion",
                "ota_kernel": "Linux-Kernel",
                "ota_channel": "Veröffentlichungskanal",
                "ota_changelog": "Änderungsprotokoll & Verlauf"
        },
        "it": {
                "nl_candle": "Candela",
                "nl_warm": "Caldo",
                "nl_balanced": "Bilanciato",
                "nl_daylight": "Luce del giorno",
                "nl_optional_off": "Opzionale · Spento",
                "ota_last_checked": "Ultimo controllo:",
                "ota_recently": "di recente",
                "ota_behind": "indietro",
                "ota_loading_changelog": "Caricamento registro modifiche...",
                "audio_active_apps": "app attive",
                "bt_scanning_short": "Ricerca nelle vicinanze...",
                "bt_devices_avail": "dispositivi disponibili",
                "bt_ready": "Pronto per l'associazione",
                "bt_hide_unnamed": "Nascondi",
                "bt_show_unnamed": "Mostra",
                "bt_unnamed_desc": "dispositivi senza nome (beacon)",
                "bat_devices": "dispositivi",
                "sysmon_threads_active": "Thread attivi",
                "sysmon_uptime": "Tempo di attività",
                "sysmon_processor": "Processore",
                "sysmon_util": "Utilizzo",
                "mod_media_nothing": "Nessuna riproduzione",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Abilitato",
                "mod_wifi_disabled": "Disabilitato",
                "mod_wifi_connected": "Connesso",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Richiesta di associazione in sospeso",
                "mod_bt_enabled": "Abilitato",
                "mod_bt_disabled": "Disabilitato",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Abilitato · clic per nascondere",
                "mod_dock_disabled": "Disabilitato · clic per mostrare",
                "mod_notif": "Notifiche",
                "mod_notif_unread": "non lette",
                "mod_notif_none": "Nessuna non letta",
                "mod_nl": "Luce notturna",
                "mod_nl_inactive": "Inattivo",
                "mod_caffeine_awake": "Modalità attiva",
                "mod_caffeine_sleep": "Sospensione normale",
                "mod_powersave_eco": "Eco attivo",
                "mod_powersave_disabled": "Disabilitato",
                "mod_perf": "Prestazioni",
                "mod_perf_boost": "Turbo Max",
                "mod_perf_balanced": "Bilanciato",
                "mod_dnd_silenced": "Silenziato",
                "mod_dnd_sounds": "Suoni attivi",
                "mod_audio_muted": "Muto",
                "mod_record": "Registra",
                "wifi_hide": "Nascondi",
                "wifi_show": "Mostra",
                "wifi_saved": "Salvata",
                "bt_paired": "Associato",
                "bt_available": "Disponibile",
                "bt_unnamed_device": "Dispositivo senza nome",
                "audio_sink_active": "Attivo",
                "audio_select": "Seleziona",
                "hypr_enabled": "Abilitato",
                "hypr_disabled": "Disabilitato",
                "hypr_max_perf": "Massime prestazioni",
                "hypr_balanced": "Bilanciato",
                "hypr_power_source": "Fonte di alimentazione",
                "hypr_batteries": "Batterie",
                "bat_charging": "In carica",
                "bat_on_battery": "A batteria",
                "bat_ac_online": "Rete elettrica collegata",
                "bat_external_power": "Alimentazione esterna",
                "ws_active": "Attivo",
                "ws_empty": "Spazio vuoto",
                "nl_enabled": "Abilitato",
                "nl_disabled": "Disabilitato",
                "nl_active_desc": "Il filtro luce blu è attivo",
                "nl_off_desc": "Il filtro luce blu è disattivato",
                "nl_schedule_hint": "Disattivato per impostazione predefinita. Imposta entrambi gli orari per abilitare.",
                "nl_schedule_update": "Aggiorna pianificazione",
                "nl_schedule_enable": "Abilita pianificazione",
                "pair_waiting": "In attesa",
                "pair_done": "Fatto",
                "pair_closed": "Chiuso",
                "pair_pin": "Inserisci il PIN",
                "pair_auth": "Autorizzazione",
                "pair_code": "Codice di conferma",
                "pair_none": "Nessuna richiesta di associazione in sospeso.",
                "ota_available": "Aggiornamento di sistema disponibile",
                "ota_check": "Controlla aggiornamenti",
                "ota_install": "Scarica e installa",
                "ota_installing": "Installazione in corso...",
                "sysmon_title": "Monitor di sistema (htop)",
                "sysmon_cli": "CLI htop",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Attività core CPU",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "Grafica integrata standard",
                "sysmon_top_proc": "Processi principali",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memoria",
                "sysmon_pid": "PID",
                "sysmon_user": "UTENTE",
                "sysmon_name": "NOME",
                "sysmon_kill": "TERMINA",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC o clic esterno per chiudere",
                "lang_title": "Lingua & Input",
                "lang_subtitle": "IMPOSTAZIONI TASTIERA E LINGUA",
                "lang_input_languages": "Lingue di input",
                "lang_active": "Attivo",
                "lang_add_layout": "Aggiungi layout di tastiera",
                "lang_system_language": "Lingua di sistema",
                "lang_user_language": "Lingua utente attuale:",
                "lang_change_display": "Cambia lingua di visualizzazione",
                "lang_change_system": "Cambia lingua di sistema (localectl)",
                "lang_footer_nav": "↑/↓ Naviga • Invio Seleziona • Esc Chiudi",
                "lang_add_title": "Aggiungi layout di tastiera",
                "lang_search_layout": "Cerca lingua o paese...",
                "lang_add_btn": "+ Aggiungi",
                "lang_select_display": "Seleziona lingua di visualizzazione",
                "lang_select_system": "Seleziona lingua di sistema (localectl)",
                "lang_search_locale": "Cerca lingua o impostazione regionale...",
                "lang_select_btn": "Seleziona",
                "tab_control": "Controllo",
                "tab_spaces": "Spazi",
                "tab_hypr": "Hypr",
                "tab_alerts": "Avvisi",
                "tab_clips": "Appunti",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Uscita audio",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifiche",
                "mod_nightlight": "Luce notturna",
                "mod_caffeine": "Caffeina",
                "mod_powersave": "Risparmio energetico",
                "mod_performance": "Prestazioni",
                "mod_dnd": "Non disturbare",
                "mod_volume": "Volume",
                "mod_brightness": "Luminosità",
                "mod_picker": "Contagocce",
                "mod_gallery": "Galleria",
                "mod_random": "Casuale",
                "mod_tasks": "Attività",
                "wifi_title": "Reti Wi-Fi disponibili",
                "wifi_back": "Indietro",
                "wifi_connecting": "Connessione in corso...",
                "wifi_connected": "Connesso",
                "wifi_disconnect": "Disconnetti",
                "wifi_connect": "Connetti",
                "wifi_known": "Nota",
                "wifi_scanning": "Ricerca reti Wi-Fi...",
                "wifi_none": "Nessuna rete Wi-Fi trovata.",
                "wifi_settings": "Apri impostazioni di rete",
                "bt_title": "Dispositivi Bluetooth",
                "bt_back": "Indietro",
                "bt_disabled_title": "Il Bluetooth è disabilitato",
                "bt_disabled_desc": "Attiva il Bluetooth per scoprire e connettere dispositivi",
                "bt_turn_on": "Attiva Bluetooth",
                "bt_scanning": "Ricerca dispositivi Bluetooth...",
                "bt_none_found": "Nessun dispositivo trovato. Clicca su Cerca in alto.",
                "bt_unnamed": "Dispositivo senza nome",
                "bt_connected": "Connesso",
                "bt_disconnected": "Disconnesso",
                "bt_pair": "Associa",
                "bt_disconnect": "Disconnetti",
                "bt_connect": "Connetti",
                "bt_remove": "Rimuovi",
                "bt_manager": "Gestore Bluetooth",
                "audio_title": "Dispositivi di uscita audio",
                "audio_back": "Indietro",
                "audio_none": "Nessun dispositivo audio rilevato.",
                "audio_mixer": "Mixer volume applicazioni",
                "audio_no_apps": "Nessun flusso audio attivo.",
                "audio_pavucontrol": "Impostazioni audio (Pavucontrol)",
                "hypr_title": "Impostazioni compositor Hyprland",
                "hypr_animations": "Animazioni",
                "hypr_blur": "Effetto sfocatura",
                "hypr_shadows": "Ombre",
                "hypr_perf": "Prestazioni",
                "hypr_gpu_profile": "Profilo grafico",
                "hypr_gpu_integrated": "Integrata",
                "hypr_gpu_igpu_only": "Solo iGPU",
                "hypr_gpu_hybrid": "Ibrida",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicata",
                "hypr_gpu_dgpu_only": "Solo dGPU",
                "hypr_rounding": "Arrotondamento:",
                "hypr_gaps": "Spaziatura:",
                "hypr_split": "Layout diviso",
                "hypr_reload": "Ricarica",
                "bat_ac_active": "Alimentazione diretta attiva",
                "bat_power": "Potenza",
                "bat_volt": "Tensione",
                "bat_health": "Salute",
                "bat_full": "Carica",
                "bat_cycles": "Cicli",
                "bat_limit": "Limite",
                "notif_title": "Notifiche",
                "notif_back": "Indietro",
                "notif_clear": "Cancella tutto",
                "notif_tap_open": "Tocca per aprire",
                "notif_muted_apps": "App silenziate",
                "notif_muted_desc": "Le notifiche delle app silenziate vengono ignorate.",
                "notif_empty": "Nessuna notifica presente.",
                "clip_title": "Appunti",
                "clip_clear": "Cancella tutto",
                "clip_empty": "Vuoto: copia qualcosa prima",
                "ws_overview": "Panoramica spazi di lavoro",
                "ws_space": "Spazio",
                "ws_add": "Aggiungi spazio",
                "ws_footer": "Super + Tab commuta la panoramica • Clicca per cambiare • 󰅖 rimuove lo spazio",
                "nl_title": "Luce notturna",
                "nl_back": "Indietro",
                "nl_temp": "Temperatura colore",
                "nl_temp_desc": "Valori più bassi sono più caldi; valori più alti sono neutri.",
                "nl_gamma": "Gamma schermo",
                "nl_gamma_desc": "Un gamma più basso scurisce; 100% è luminosità normale.",
                "nl_schedule": "Pianificazione automatica",
                "nl_start": "Inizio",
                "nl_end": "Fine",
                "nl_disable": "Disabilita",
                "nl_reset": "Ripristina predefiniti · 4500 K · 100%",
                "pair_title": "Richiesta di associazione",
                "pair_back": "Indietro",
                "pair_reject": "Rifiuta",
                "pair_confirm": "Conferma",
                "pair_empty": "Nessuna richiesta di associazione in sospeso.",
                "ota_title": "Aggiornamento di sistema",
                "ota_back": "Indietro",
                "ota_uptodate": "Il sistema è aggiornato",
                "ota_checking": "Controllo aggiornamenti in corso...",
                "ota_new": "Nuovo aggiornamento",
                "ota_current": "Versione attuale",
                "ota_target": "Versione di destinazione",
                "ota_kernel": "Kernel Linux",
                "ota_channel": "Canale di rilascio",
                "ota_changelog": "Cronologia e note di rilascio"
        },
        "pt": {
                "nl_candle": "Vela",
                "nl_warm": "Quente",
                "nl_balanced": "Equilibrado",
                "nl_daylight": "Luz do dia",
                "nl_optional_off": "Opcional · Desligado",
                "ota_last_checked": "Última verificação:",
                "ota_recently": "recentemente",
                "ota_behind": "atrasado",
                "ota_loading_changelog": "Carregando registro de alterações...",
                "audio_active_apps": "aplicativo(s) ativo(s)",
                "bt_scanning_short": "Procurando próximos...",
                "bt_devices_avail": "dispositivos disponíveis",
                "bt_ready": "Pronto para emparelhar",
                "bt_hide_unnamed": "Ocultar",
                "bt_show_unnamed": "Mostrar",
                "bt_unnamed_desc": "dispositivos sem nome (beacons)",
                "bat_devices": "dispositivos",
                "sysmon_threads_active": "Threads ativas",
                "sysmon_uptime": "Tempo de atividade",
                "sysmon_processor": "Processador",
                "sysmon_util": "Uso",
                "mod_media_nothing": "Nada reproduzindo",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Ativado",
                "mod_wifi_disabled": "Desativado",
                "mod_wifi_connected": "Conectado",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Solicitação de emparelhamento pendente",
                "mod_bt_enabled": "Ativado",
                "mod_bt_disabled": "Desativado",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Ativado · clique para ocultar",
                "mod_dock_disabled": "Desativado · clique para mostrar",
                "mod_notif": "Notificações",
                "mod_notif_unread": "não lidas",
                "mod_notif_none": "Nenhuma não lida",
                "mod_nl": "Luz noturna",
                "mod_nl_inactive": "Inativo",
                "mod_caffeine_awake": "Modo acordado",
                "mod_caffeine_sleep": "Suspensão normal",
                "mod_powersave_eco": "Eco ativo",
                "mod_powersave_disabled": "Desativado",
                "mod_perf": "Desempenho",
                "mod_perf_boost": "Turbo Máximo",
                "mod_perf_balanced": "Equilibrado",
                "mod_dnd_silenced": "Silenciado",
                "mod_dnd_sounds": "Sons ativos",
                "mod_audio_muted": "Mudo",
                "mod_record": "Gravar",
                "wifi_hide": "Ocultar",
                "wifi_show": "Mostrar",
                "wifi_saved": "Salva",
                "bt_paired": "Emparelhado",
                "bt_available": "Disponível",
                "bt_unnamed_device": "Dispositivo sem nome",
                "audio_sink_active": "Ativo",
                "audio_select": "Selecionar",
                "hypr_enabled": "Ativado",
                "hypr_disabled": "Desativado",
                "hypr_max_perf": "Desempenho máximo",
                "hypr_balanced": "Equilibrado",
                "hypr_power_source": "Fonte de energia",
                "hypr_batteries": "Baterias",
                "bat_charging": "Carregando",
                "bat_on_battery": "Na bateria",
                "bat_ac_online": "Rede elétrica conectada",
                "bat_external_power": "Alimentação externa",
                "ws_active": "Ativo",
                "ws_empty": "Espaço vazio",
                "nl_enabled": "Ativado",
                "nl_disabled": "Desativado",
                "nl_active_desc": "Filtro de luz azul está ativo",
                "nl_off_desc": "Filtro de luz azul está desligado",
                "nl_schedule_hint": "Desativado por padrão. Defina ambos os horários (24h HH:MM) para ativar.",
                "nl_schedule_update": "Atualizar agendamento",
                "nl_schedule_enable": "Ativar agendamento",
                "pair_waiting": "Aguardando",
                "pair_done": "Concluído",
                "pair_closed": "Fechado",
                "pair_pin": "Insira o PIN",
                "pair_auth": "Autorização",
                "pair_code": "Código de confirmação",
                "pair_none": "Nenhuma solicitação de emparelhamento pendente.",
                "ota_available": "Atualização do sistema disponível",
                "ota_check": "Verificar atualizações",
                "ota_install": "Baixar & Instalar",
                "ota_installing": "Instalando...",
                "sysmon_title": "Monitor do sistema (htop)",
                "sysmon_cli": "CLI htop",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Atividade dos núcleos CPU",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "Gráficos integrados padrão",
                "sysmon_top_proc": "Processos principais",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memória",
                "sysmon_pid": "PID",
                "sysmon_user": "USUÁRIO",
                "sysmon_name": "NOME",
                "sysmon_kill": "FINALIZAR",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC ou clique fora para fechar",
                "lang_title": "Idioma & Entrada",
                "lang_subtitle": "CONFIGURAÇÕES DE TECLADO E IDIOMA",
                "lang_input_languages": "Idiomas de entrada",
                "lang_active": "Ativo",
                "lang_add_layout": "Adicionar layout de teclado",
                "lang_system_language": "Idioma do sistema",
                "lang_user_language": "Idioma do usuário atual:",
                "lang_change_display": "Alterar meu idioma de exibição",
                "lang_change_system": "Alterar idioma do sistema (localectl)",
                "lang_footer_nav": "↑/↓ Navegar • Enter Selecionar • Esc Fechar",
                "lang_add_title": "Adicionar layout de teclado",
                "lang_search_layout": "Pesquisar idioma ou país...",
                "lang_add_btn": "+ Adicionar",
                "lang_select_display": "Selecionar idioma de exibição",
                "lang_select_system": "Selecionar idioma do sistema (localectl)",
                "lang_search_locale": "Pesquisar idioma ou localidade...",
                "lang_select_btn": "Selecionar",
                "tab_control": "Controle",
                "tab_spaces": "Espaços",
                "tab_hypr": "Hypr",
                "tab_alerts": "Alertas",
                "tab_clips": "Clips",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Saída de áudio",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notificações",
                "mod_nightlight": "Luz noturna",
                "mod_caffeine": "Cafeína",
                "mod_powersave": "Economia de energia",
                "mod_performance": "Desempenho",
                "mod_dnd": "Não perturbe",
                "mod_volume": "Volume",
                "mod_brightness": "Brilho",
                "mod_picker": "Conta-gotas",
                "mod_gallery": "Galeria",
                "mod_random": "Aleatório",
                "mod_tasks": "Tarefas",
                "wifi_title": "Redes Wi-Fi disponíveis",
                "wifi_back": "Voltar",
                "wifi_connecting": "Conectando...",
                "wifi_connected": "Conectado",
                "wifi_disconnect": "Desconectar",
                "wifi_connect": "Conectar",
                "wifi_known": "Conhecida",
                "wifi_scanning": "Buscando redes Wi-Fi...",
                "wifi_none": "Nenhuma rede Wi-Fi encontrada.",
                "wifi_settings": "Abrir configurações de rede",
                "bt_title": "Dispositivos Bluetooth",
                "bt_back": "Voltar",
                "bt_disabled_title": "O Bluetooth está desativado",
                "bt_disabled_desc": "Ligue o Bluetooth para descobrir e conectar dispositivos próximos",
                "bt_turn_on": "Ligar Bluetooth",
                "bt_scanning": "Buscando dispositivos Bluetooth...",
                "bt_none_found": "Nenhum dispositivo encontrado. Clique em Buscar acima.",
                "bt_unnamed": "Dispositivo sem nome",
                "bt_connected": "Conectado",
                "bt_disconnected": "Desconectado",
                "bt_pair": "Emparelhar",
                "bt_disconnect": "Desconectar",
                "bt_connect": "Conectar",
                "bt_remove": "Remover",
                "bt_manager": "Gerenciador Bluetooth",
                "audio_title": "Dispositivos de saída de áudio",
                "audio_back": "Voltar",
                "audio_none": "Nenhum dispositivo de áudio detectado.",
                "audio_mixer": "Mixer de volume de aplicativos",
                "audio_no_apps": "Nenhum fluxo de áudio ativo.",
                "audio_pavucontrol": "Configurações de áudio (Pavucontrol)",
                "hypr_title": "Configurações do compositor Hyprland",
                "hypr_animations": "Animações",
                "hypr_blur": "Efeito de desfoque",
                "hypr_shadows": "Sombras",
                "hypr_perf": "Desempenho",
                "hypr_gpu_profile": "Perfil gráfico",
                "hypr_gpu_integrated": "Integrada",
                "hypr_gpu_igpu_only": "Apenas iGPU",
                "hypr_gpu_hybrid": "Híbrida",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicada",
                "hypr_gpu_dgpu_only": "Apenas dGPU",
                "hypr_rounding": "Arredondamento:",
                "hypr_gaps": "Espaçamento:",
                "hypr_split": "Layout dividido",
                "hypr_reload": "Recarregar",
                "bat_ac_active": "Alimentação direta ativa",
                "bat_power": "Potência",
                "bat_volt": "Tensão",
                "bat_health": "Saúde",
                "bat_full": "Cheia",
                "bat_cycles": "Ciclos",
                "bat_limit": "Limite",
                "notif_title": "Notificações",
                "notif_back": "Voltar",
                "notif_clear": "Limpar tudo",
                "notif_tap_open": "Toque para abrir o app",
                "notif_muted_apps": "Apps silenciados",
                "notif_muted_desc": "Notificações de apps silenciados são descartadas.",
                "notif_empty": "Nenhuma notificação por enquanto.",
                "clip_title": "Área de transferência",
                "clip_clear": "Limpar tudo",
                "clip_empty": "Vazio: copie algo primeiro",
                "ws_overview": "Visão geral das áreas",
                "ws_space": "Espaço",
                "ws_add": "Adicionar espaço",
                "ws_footer": "Super + Tab alterna visão geral • Clique para trocar • 󰅖 remove espaço",
                "nl_title": "Luz noturna",
                "nl_back": "Voltar",
                "nl_temp": "Temperatura de cor",
                "nl_temp_desc": "Valores menores são mais quentes; valores maiores são neutros.",
                "nl_gamma": "Gama da tela",
                "nl_gamma_desc": "Gama menor escurece a imagem; 100% é normal.",
                "nl_schedule": "Agendamento automático",
                "nl_start": "Início",
                "nl_end": "Fim",
                "nl_disable": "Desativar",
                "nl_reset": "Restaurar padrões · 4500 K · 100%",
                "pair_title": "Solicitação de emparelhamento",
                "pair_back": "Voltar",
                "pair_reject": "Recusar",
                "pair_confirm": "Confirmar",
                "pair_empty": "Nenhuma solicitação de emparelhamento pendente.",
                "ota_title": "Atualização do sistema",
                "ota_back": "Voltar",
                "ota_uptodate": "O sistema está atualizado",
                "ota_checking": "Verificando atualizações...",
                "ota_new": "Nova atualização",
                "ota_current": "Versão atual",
                "ota_target": "Versão de destino",
                "ota_kernel": "Kernel Linux",
                "ota_channel": "Canal de lançamento",
                "ota_changelog": "Histórico de alterações"
        },
        "ru": {
                "nl_candle": "Свеча",
                "nl_warm": "Тёплый",
                "nl_balanced": "Сбалансированный",
                "nl_daylight": "Дневной свет",
                "nl_optional_off": "Опционально · Выкл",
                "ota_last_checked": "Последняя проверка:",
                "ota_recently": "недавно",
                "ota_behind": "позади",
                "ota_loading_changelog": "Загрузка журнала изменений...",
                "audio_active_apps": "активные приложения",
                "bt_scanning_short": "Поиск поблизости...",
                "bt_devices_avail": "доступные устройства",
                "bt_ready": "Готово к сопряжению",
                "bt_hide_unnamed": "Скрыть",
                "bt_show_unnamed": "Показать",
                "bt_unnamed_desc": "безымянные устройства (маяки)",
                "bat_devices": "устройства",
                "sysmon_threads_active": "Активные потоки",
                "sysmon_uptime": "Время работы",
                "sysmon_processor": "Процессор",
                "sysmon_util": "Нагрузка",
                "mod_media_nothing": "Ничего не воспроизводится",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Включено",
                "mod_wifi_disabled": "Отключено",
                "mod_wifi_connected": "Подключено",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Ожидается запрос на сопряжение",
                "mod_bt_enabled": "Включено",
                "mod_bt_disabled": "Отключено",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Включено · нажать для скрытия",
                "mod_dock_disabled": "Отключено · нажать для показа",
                "mod_notif": "Уведомления",
                "mod_notif_unread": "непрочитанные",
                "mod_notif_none": "Нет непрочитанных",
                "mod_nl": "Ночной свет",
                "mod_nl_inactive": "Неактивно",
                "mod_caffeine_awake": "Бодрствование",
                "mod_caffeine_sleep": "Обычный сон",
                "mod_powersave_eco": "Эко-режим",
                "mod_powersave_disabled": "Отключено",
                "mod_perf": "Производительность",
                "mod_perf_boost": "Турбо-буст",
                "mod_perf_balanced": "Баланс",
                "mod_dnd_silenced": "Без звука",
                "mod_dnd_sounds": "Звуки включены",
                "mod_audio_muted": "Без звука",
                "mod_record": "Запись",
                "wifi_hide": "Скрыть",
                "wifi_show": "Показать",
                "wifi_saved": "Сохранено",
                "bt_paired": "Сопряжено",
                "bt_available": "Доступно",
                "bt_unnamed_device": "Безымянное устройство",
                "audio_sink_active": "Активно",
                "audio_select": "Выбрать",
                "hypr_enabled": "Включено",
                "hypr_disabled": "Отключено",
                "hypr_max_perf": "Максимальная производительность",
                "hypr_balanced": "Баланс",
                "hypr_power_source": "Источник питания",
                "hypr_batteries": "Батареи",
                "bat_charging": "Заряжается",
                "bat_on_battery": "От батареи",
                "bat_ac_online": "Сеть подключена",
                "bat_external_power": "Внешнее питание",
                "ws_active": "Активно",
                "ws_empty": "Пустое пространство",
                "nl_enabled": "Включено",
                "nl_disabled": "Отключено",
                "nl_active_desc": "Фильтр синего света активен",
                "nl_off_desc": "Фильтр синего света отключен",
                "nl_schedule_hint": "По умолчанию выкл. Укажите оба времени (24ч ЧЧ:ММ) для включения.",
                "nl_schedule_update": "Обновить расписание",
                "nl_schedule_enable": "Включить расписание",
                "pair_waiting": "Ожидание",
                "pair_done": "Готово",
                "pair_closed": "Закрыто",
                "pair_pin": "Введите PIN",
                "pair_auth": "Авторизация",
                "pair_code": "Код подтверждения",
                "pair_none": "Нет ожидающих запросов на сопряжение.",
                "ota_available": "Доступно обновление системы",
                "ota_check": "Проверить обновления",
                "ota_install": "Скачать и установить",
                "ota_installing": "Установка...",
                "sysmon_title": "Системный монитор (htop)",
                "sysmon_cli": "CLI htop",
                "sysmon_cpu": "ЦП",
                "sysmon_ram": "ОЗУ",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Активность ядер ЦП",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "Стандартная встроенная графика",
                "sysmon_top_proc": "Топ процессов",
                "sysmon_top_cpu": "Топ ЦП",
                "sysmon_top_mem": "Топ Память",
                "sysmon_pid": "PID",
                "sysmon_user": "ПОЛЬЗОВАТЕЛЬ",
                "sysmon_name": "ИМЯ",
                "sysmon_kill": "ЗАВЕРШИТЬ",
                "sysmon_kernel": "Ядро: Linux ",
                "sysmon_esc_close": "ESC или клик снаружи для закрытия",
                "lang_title": "Язык и ввод",
                "lang_subtitle": "НАСТРОЙКИ КЛАВИАТУРЫ И ЯЗЫКА",
                "lang_input_languages": "Языки ввода",
                "lang_active": "Активно",
                "lang_add_layout": "Добавить раскладку",
                "lang_system_language": "Язык системы",
                "lang_user_language": "Текущий язык пользователя:",
                "lang_change_display": "Изменить язык интерфейса",
                "lang_change_system": "Изменить язык системы (localectl)",
                "lang_footer_nav": "↑/↓ Навигация • Enter Выбрать • Esc Закрыть",
                "lang_add_title": "Добавить раскладку клавиатуры",
                "lang_search_layout": "Поиск языка или страны...",
                "lang_add_btn": "+ Добавить",
                "lang_select_display": "Выбрать язык интерфейса",
                "lang_select_system": "Выбрать системный язык (localectl)",
                "lang_search_locale": "Поиск языка или локали...",
                "lang_select_btn": "Выбрать",
                "tab_control": "Управление",
                "tab_spaces": "Пространства",
                "tab_hypr": "Hypr",
                "tab_alerts": "Оповещения",
                "tab_clips": "Буфер",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Аудиовыход",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Уведомления",
                "mod_nightlight": "Ночной свет",
                "mod_caffeine": "Кофеин",
                "mod_powersave": "Энергосбережение",
                "mod_performance": "Производительность",
                "mod_dnd": "Не беспокоить",
                "mod_volume": "Громкость",
                "mod_brightness": "Яркость",
                "mod_picker": "Пипетка",
                "mod_gallery": "Галерея",
                "mod_random": "Случайно",
                "mod_tasks": "Задачи",
                "wifi_title": "Доступные сети Wi-Fi",
                "wifi_back": "Назад",
                "wifi_connecting": "Подключение...",
                "wifi_connected": "Подключено",
                "wifi_disconnect": "Отключить",
                "wifi_connect": "Подключить",
                "wifi_known": "Известная",
                "wifi_scanning": "Поиск сетей Wi-Fi...",
                "wifi_none": "Сети Wi-Fi не найдены.",
                "wifi_settings": "Открыть настройки сети",
                "bt_title": "Устройства Bluetooth",
                "bt_back": "Назад",
                "bt_disabled_title": "Bluetooth отключен",
                "bt_disabled_desc": "Включите Bluetooth для поиска и подключения устройств",
                "bt_turn_on": "Включить Bluetooth",
                "bt_scanning": "Поиск устройств Bluetooth...",
                "bt_none_found": "Устройства не найдены. Нажмите Сканировать выше.",
                "bt_unnamed": "Безымянное устройство",
                "bt_connected": "Подключено",
                "bt_disconnected": "Отключено",
                "bt_pair": "Сопряжение",
                "bt_disconnect": "Отключить",
                "bt_connect": "Подключить",
                "bt_remove": "Удалить",
                "bt_manager": "Диспетчер Bluetooth",
                "audio_title": "Устройства вывода звука",
                "audio_back": "Назад",
                "audio_none": "Аудиоустройства не обнаружены.",
                "audio_mixer": "Микшер громкости приложений",
                "audio_no_apps": "Нет активных аудиопотоков.",
                "audio_pavucontrol": "Настройки звука (Pavucontrol)",
                "hypr_title": "Параметры композитора Hyprland",
                "hypr_animations": "Анимации",
                "hypr_blur": "Эффект размытия",
                "hypr_shadows": "Тени",
                "hypr_perf": "Производительность",
                "hypr_gpu_profile": "Графический профиль",
                "hypr_gpu_integrated": "Встроенная",
                "hypr_gpu_igpu_only": "Только iGPU",
                "hypr_gpu_hybrid": "Гибридная",
                "hypr_gpu_prime_auto": "PRIME Авто",
                "hypr_gpu_dedicated": "Дискретная",
                "hypr_gpu_dgpu_only": "Только dGPU",
                "hypr_rounding": "Скругление:",
                "hypr_gaps": "Отступы:",
                "hypr_split": "Раздельный макет",
                "hypr_reload": "Перезагрузить",
                "bat_ac_active": "Питание от сети активно",
                "bat_power": "Мощность",
                "bat_volt": "Напряжение",
                "bat_health": "Здоровье",
                "bat_full": "Полный",
                "bat_cycles": "Циклы",
                "bat_limit": "Лимит",
                "notif_title": "Уведомления",
                "notif_back": "Назад",
                "notif_clear": "Очистить все",
                "notif_tap_open": "Нажмите, чтобы открыть",
                "notif_muted_apps": "Заглушенные приложения",
                "notif_muted_desc": "Уведомления от заглушенных приложений отбрасываются.",
                "notif_empty": "Пока нет уведомлений.",
                "clip_title": "Буфер обмена",
                "clip_clear": "Очистить все",
                "clip_empty": "Пусто: сначала скопируйте что-нибудь",
                "ws_overview": "Обзор рабочих пространств",
                "ws_space": "Пространство",
                "ws_add": "Добавить пространство",
                "ws_footer": "Super + Tab обзор • Клик для смены • 󰅖 удалить пространство",
                "nl_title": "Ночной свет",
                "nl_back": "Назад",
                "nl_temp": "Цветовая температура",
                "nl_temp_desc": "Меньшие значения теплее; большие нейтральнее.",
                "nl_gamma": "Гамма экрана",
                "nl_gamma_desc": "Меньшая гамма затемняет экран; 100% — стандарт.",
                "nl_schedule": "Автоматическое расписание",
                "nl_start": "Начало",
                "nl_end": "Конец",
                "nl_disable": "Отключить",
                "nl_reset": "Сброс · 4500 K · 100%",
                "pair_title": "Запрос на сопряжение",
                "pair_back": "Назад",
                "pair_reject": "Отклонить",
                "pair_confirm": "Подтвердить",
                "pair_empty": "Нет ожидающих запросов на сопряжение.",
                "ota_title": "Обновление системы",
                "ota_back": "Назад",
                "ota_uptodate": "Система обновлена",
                "ota_checking": "Проверка обновлений...",
                "ota_new": "Новое обновление",
                "ota_current": "Текущая версия",
                "ota_target": "Новая версия",
                "ota_kernel": "Ядро Linux",
                "ota_channel": "Канал релизов",
                "ota_changelog": "История изменений"
        },
        "ja": {
                "nl_candle": "ろうそく",
                "nl_warm": "ウォーム",
                "nl_balanced": "バランス",
                "nl_daylight": "デイライト",
                "nl_optional_off": "オプション · オフ",
                "ota_last_checked": "最終確認:",
                "ota_recently": "最近",
                "ota_behind": "未更新",
                "ota_loading_changelog": "変更履歴を読み込み中...",
                "audio_active_apps": "個のアクティブアプリ",
                "bt_scanning_short": "周辺をスキャン中...",
                "bt_devices_avail": "台の利用可能なデバイス",
                "bt_ready": "ペアリング準備完了",
                "bt_hide_unnamed": "非表示",
                "bt_show_unnamed": "表示",
                "bt_unnamed_desc": "名前のないデバイス (ビーコン)",
                "bat_devices": "台のデバイス",
                "sysmon_threads_active": "アクティブスレッド",
                "sysmon_uptime": "稼働時間",
                "sysmon_processor": "プロセッサ",
                "sysmon_util": "使用率",
                "mod_media_nothing": "再生停止中",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "有効",
                "mod_wifi_disabled": "無効",
                "mod_wifi_connected": "接続済み",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "ペアリング要求待機中",
                "mod_bt_enabled": "有効",
                "mod_bt_disabled": "無効",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "有効 · クリックで隠す",
                "mod_dock_disabled": "無効 · クリックで表示",
                "mod_notif": "通知",
                "mod_notif_unread": "件の未読",
                "mod_notif_none": "未読なし",
                "mod_nl": "夜間モード",
                "mod_nl_inactive": "オフ",
                "mod_caffeine_awake": "アウェイクモード",
                "mod_caffeine_sleep": "通常スリープ",
                "mod_powersave_eco": "エコ有効",
                "mod_powersave_disabled": "無効",
                "mod_perf": "パフォーマンス",
                "mod_perf_boost": "ターボブースト",
                "mod_perf_balanced": "バランス",
                "mod_dnd_silenced": "消音",
                "mod_dnd_sounds": "サウンドオン",
                "mod_audio_muted": "消音",
                "mod_record": "録画",
                "wifi_hide": "非表示",
                "wifi_show": "表示",
                "wifi_saved": "保存済み",
                "bt_paired": "ペアリング済み",
                "bt_available": "利用可能",
                "bt_unnamed_device": "名称未設定デバイス",
                "audio_sink_active": "アクティブ",
                "audio_select": "選択",
                "hypr_enabled": "有効",
                "hypr_disabled": "無効",
                "hypr_max_perf": "最高パフォーマンス",
                "hypr_balanced": "バランス",
                "hypr_power_source": "電源",
                "hypr_batteries": "バッテリー",
                "bat_charging": "充電中",
                "bat_on_battery": "バッテリー駆動",
                "bat_ac_online": "AC電源接続",
                "bat_external_power": "外部電源",
                "ws_active": "アクティブ",
                "ws_empty": "空のスペース",
                "nl_enabled": "有効",
                "nl_disabled": "無効",
                "nl_active_desc": "ブルーライト低減が有効です",
                "nl_off_desc": "ブルーライト低減はオフです",
                "nl_schedule_hint": "初期設定では無効です。24時間表記の開始と終了時刻を設定してください。",
                "nl_schedule_update": "スケジュールを更新",
                "nl_schedule_enable": "スケジュールを有効化",
                "pair_waiting": "待機中",
                "pair_done": "完了",
                "pair_closed": "終了",
                "pair_pin": "PINコードを入力",
                "pair_auth": "認証",
                "pair_code": "確認コード",
                "pair_none": "保留中のペアリング要求はありません。",
                "ota_available": "システム更新が利用可能です",
                "ota_check": "更新を確認",
                "ota_install": "ダウンロードしてインストール",
                "ota_installing": "インストール中...",
                "sysmon_title": "システムモニター (htop)",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPUコアの稼働状況",
                "sysmon_gpu": "GPU:",
                "sysmon_integrated_gpu": "内蔵グラフィックス",
                "sysmon_top_proc": "主要プロセス",
                "sysmon_top_cpu": "CPU使用率上位",
                "sysmon_top_mem": "メモリ使用率上位",
                "sysmon_pid": "PID",
                "sysmon_user": "ユーザー",
                "sysmon_name": "プロセス名",
                "sysmon_kill": "強制終了",
                "sysmon_kernel": "カーネル: Linux ",
                "sysmon_esc_close": "ESCまたは外側クリックで閉じる",
                "lang_title": "言語と入力",
                "lang_subtitle": "キーボードと言語の設定",
                "lang_input_languages": "入力言語",
                "lang_active": "アクティブ",
                "lang_add_layout": "キーボードレイアウトを追加",
                "lang_system_language": "システム言語",
                "lang_user_language": "現在のユーザー言語:",
                "lang_change_display": "表示言語を変更",
                "lang_change_system": "システム言語を変更 (localectl)",
                "lang_footer_nav": "↑/↓ 移動 • Enter 選択 • Esc 閉じる",
                "lang_add_title": "キーボードレイアウトを追加",
                "lang_search_layout": "言語または国名で検索...",
                "lang_add_btn": "+ 追加",
                "lang_select_display": "表示言語を選択",
                "lang_select_system": "システム言語を選択 (localectl)",
                "lang_search_locale": "言語またはロケールを検索...",
                "lang_select_btn": "選択",
                "tab_control": "コントロール",
                "tab_spaces": "スペース",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "クリップ",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "音声出力",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜間モード",
                "mod_caffeine": "カフェイン",
                "mod_powersave": "省電力",
                "mod_performance": "パフォーマンス",
                "mod_dnd": "おやすみモード",
                "mod_volume": "音量",
                "mod_brightness": "輝度",
                "mod_picker": "スポイト",
                "mod_gallery": "ギャラリー",
                "mod_random": "ランダム",
                "mod_tasks": "タスク",
                "wifi_title": "利用可能な Wi-Fi ネットワーク",
                "wifi_back": "戻る",
                "wifi_connecting": "接続中...",
                "wifi_connected": "接続済み",
                "wifi_disconnect": "切断",
                "wifi_connect": "接続",
                "wifi_known": "登録済み",
                "wifi_scanning": "Wi-Fi ネットワークを検索中...",
                "wifi_none": "利用可能なネットワークがありません。",
                "wifi_settings": "ネットワーク設定を開く",
                "bt_title": "Bluetooth デバイス",
                "bt_back": "戻る",
                "bt_disabled_title": "Bluetooth が無効です",
                "bt_disabled_desc": "デバイスを検出して接続するには Bluetooth をオンにしてください",
                "bt_turn_on": "Bluetooth をオンにする",
                "bt_scanning": "周辺の Bluetooth デバイスを検索中...",
                "bt_none_found": "デバイスが見つかりません。上のスキャンを押してください。",
                "bt_unnamed": "名称未設定デバイス",
                "bt_connected": "接続済み",
                "bt_disconnected": "切断済み",
                "bt_pair": "ペアリング",
                "bt_disconnect": "切断",
                "bt_connect": "接続",
                "bt_remove": "削除",
                "bt_manager": "Bluetooth マネージャー",
                "audio_title": "音声出力デバイス",
                "audio_back": "戻る",
                "audio_none": "オーディオデバイスが見つかりません。",
                "audio_mixer": "アプリ別音量ミキサー",
                "audio_no_apps": "再生中のアプリはありません。",
                "audio_pavucontrol": "オーディオ設定 (Pavucontrol)",
                "hypr_title": "Hyprland コンポジタ設定",
                "hypr_animations": "アニメーション",
                "hypr_blur": "ブラー効果",
                "hypr_shadows": "ウィンドウ影",
                "hypr_perf": "パフォーマンス",
                "hypr_gpu_profile": "グラフィック設定",
                "hypr_gpu_integrated": "内蔵グラフィック",
                "hypr_gpu_igpu_only": "iGPU のみ",
                "hypr_gpu_hybrid": "ハイブリッド",
                "hypr_gpu_prime_auto": "PRIME 自動",
                "hypr_gpu_dedicated": "専用GPU",
                "hypr_gpu_dgpu_only": "dGPU のみ",
                "hypr_rounding": "角の丸み:",
                "hypr_gaps": "ウィンドウ間隔:",
                "hypr_split": "画面分割配置",
                "hypr_reload": "再読み込み",
                "bat_ac_active": "電源アダプタ給電中",
                "bat_power": "消費電力",
                "bat_volt": "電圧",
                "bat_health": "バッテリー状態",
                "bat_full": "満充電",
                "bat_cycles": "サイクル数",
                "bat_limit": "上限値",
                "notif_title": "通知一覧",
                "notif_back": "戻る",
                "notif_clear": "すべて消去",
                "notif_tap_open": "タップして開く",
                "notif_muted_apps": "ミュートされたアプリ",
                "notif_muted_desc": "ミュートされたアプリの通知は一覧に表示されません。",
                "notif_empty": "通知はありません。",
                "clip_title": "クリップボード",
                "clip_clear": "すべて消去",
                "clip_empty": "空です: まず何かをコピーしてください",
                "ws_overview": "ワークスペース一覧",
                "ws_space": "スペース",
                "ws_add": "スペースを追加",
                "ws_footer": "Super + Tab で一覧表示 • カードをクリックして移動 • 󰅖 で削除",
                "nl_title": "夜間モード",
                "nl_back": "戻る",
                "nl_temp": "色温度",
                "nl_temp_desc": "値が小さいほど暖色に、大きいほど自然な色合いになります。",
                "nl_gamma": "画面ガンマ",
                "nl_gamma_desc": "ガンマを下げると暗くなります。100%が標準輝度です。",
                "nl_schedule": "自動スケジュール",
                "nl_start": "開始",
                "nl_end": "終了",
                "nl_disable": "無効にする",
                "nl_reset": "初期状態に戻す · 4500 K · 100%",
                "pair_title": "ペアリング要求",
                "pair_back": "戻る",
                "pair_reject": "拒否",
                "pair_confirm": "確認",
                "pair_empty": "保留中のペアリング要求はありません。",
                "ota_title": "システム更新",
                "ota_back": "戻る",
                "ota_uptodate": "システムは最新です",
                "ota_checking": "更新を確認中...",
                "ota_new": "新しい更新があります",
                "ota_current": "現在のバージョン",
                "ota_target": "対象バージョン",
                "ota_kernel": "Linux カーネル",
                "ota_channel": "リリースチャンネル",
                "ota_changelog": "更新履歴"
        },
        "zh": {
                "nl_candle": "烛光",
                "nl_warm": "暖色",
                "nl_balanced": "平衡",
                "nl_daylight": "日光",
                "nl_optional_off": "可选 · 关闭",
                "ota_last_checked": "上次检查：",
                "ota_recently": "刚刚",
                "ota_behind": "落后",
                "ota_loading_changelog": "正在加载更新日志...",
                "audio_active_apps": "个活动应用",
                "bt_scanning_short": "正在扫描附近...",
                "bt_devices_avail": "个可用设备",
                "bt_ready": "准备配对",
                "bt_hide_unnamed": "隐藏",
                "bt_show_unnamed": "显示",
                "bt_unnamed_desc": "未命名设备 (信标)",
                "bat_devices": "个设备",
                "sysmon_threads_active": "活动线程",
                "sysmon_uptime": "运行时间",
                "sysmon_processor": "处理器",
                "sysmon_util": "利用率",
                "mod_media_nothing": "暂无播放",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "已开启",
                "mod_wifi_disabled": "已关闭",
                "mod_wifi_connected": "已连接",
                "mod_bt": "蓝牙",
                "mod_bt_pairing": "待处理的配对请求",
                "mod_bt_enabled": "已开启",
                "mod_bt_disabled": "已关闭",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "已开启 · 点击隐藏",
                "mod_dock_disabled": "已关闭 · 点击显示",
                "mod_notif": "通知",
                "mod_notif_unread": "条未读",
                "mod_notif_none": "暂无未读",
                "mod_nl": "夜览模式",
                "mod_nl_inactive": "未激活",
                "mod_caffeine_awake": "清醒模式",
                "mod_caffeine_sleep": "正常休眠",
                "mod_powersave_eco": "节能模式",
                "mod_powersave_disabled": "已关闭",
                "mod_perf": "性能",
                "mod_perf_boost": "极致加速",
                "mod_perf_balanced": "平衡",
                "mod_dnd_silenced": "静音",
                "mod_dnd_sounds": "声音开启",
                "mod_audio_muted": "静音",
                "mod_record": "录屏",
                "wifi_hide": "隐藏",
                "wifi_show": "显示",
                "wifi_saved": "已保存",
                "bt_paired": "已配对",
                "bt_available": "可用",
                "bt_unnamed_device": "未命名设备",
                "audio_sink_active": "活动",
                "audio_select": "选择",
                "hypr_enabled": "已开启",
                "hypr_disabled": "已关闭",
                "hypr_max_perf": "极致性能",
                "hypr_balanced": "平衡",
                "hypr_power_source": "电源输入",
                "hypr_batteries": "电池",
                "bat_charging": "正在充电",
                "bat_on_battery": "电池供电",
                "bat_ac_online": "电源适配器已连接",
                "bat_external_power": "外部供电",
                "ws_active": "活动",
                "ws_empty": "空工作区",
                "nl_enabled": "已开启",
                "nl_disabled": "已关闭",
                "nl_active_desc": "蓝光护眼滤镜已生效",
                "nl_off_desc": "蓝光护眼滤镜已关闭",
                "nl_schedule_hint": "默认关闭。请设置 24 小时制起止时间以启用定时。",
                "nl_schedule_update": "更新定时计划",
                "nl_schedule_enable": "启用定时计划",
                "pair_waiting": "等待中",
                "pair_done": "已完成",
                "pair_closed": "已关闭",
                "pair_pin": "输入配对码",
                "pair_auth": "身份验证",
                "pair_code": "确认验证码",
                "pair_none": "没有待处理的配对请求。",
                "ota_available": "系统有新版本可用",
                "ota_check": "检查更新",
                "ota_install": "下载并安装",
                "ota_installing": "正在安装...",
                "sysmon_title": "系统监视器 (htop)",
                "sysmon_cli": "htop 命令行",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "内存",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "固态硬盘 /",
                "sysmon_cores": "CPU 核心活动",
                "sysmon_gpu": "显卡：",
                "sysmon_integrated_gpu": "标准集成显卡",
                "sysmon_top_proc": "主要进程",
                "sysmon_top_cpu": "CPU 占用最高",
                "sysmon_top_mem": "内存占用最高",
                "sysmon_pid": "PID",
                "sysmon_user": "用户",
                "sysmon_name": "名称",
                "sysmon_kill": "结束",
                "sysmon_kernel": "内核：Linux ",
                "sysmon_esc_close": "按 ESC 或点击外部以关闭",
                "lang_title": "语言与输入",
                "lang_subtitle": "键盘与语言设置",
                "lang_input_languages": "输入法布局",
                "lang_active": "当前使用",
                "lang_add_layout": "添加键盘布局",
                "lang_system_language": "系统语言",
                "lang_user_language": "当前用户语言：",
                "lang_change_display": "更改显示语言",
                "lang_change_system": "更改系统全局语言 (localectl)",
                "lang_footer_nav": "↑/↓ 移动 • 回车 选择 • Esc 关闭",
                "lang_add_title": "添加键盘布局",
                "lang_search_layout": "搜索语言或国家/地区...",
                "lang_add_btn": "+ 添加",
                "lang_select_display": "选择显示语言",
                "lang_select_system": "选择系统语言 (localectl)",
                "lang_search_locale": "搜索语言或区域代码...",
                "lang_select_btn": "选择",
                "tab_control": "控制中心",
                "tab_spaces": "工作区",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "剪贴板",
                "mod_bluetooth": "蓝牙",
                "mod_audio": "音频输出",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜览护眼",
                "mod_caffeine": "咖啡因模式",
                "mod_powersave": "省电模式",
                "mod_performance": "性能模式",
                "mod_dnd": "勿扰模式",
                "mod_volume": "音量",
                "mod_brightness": "亮度",
                "mod_picker": "取色器",
                "mod_gallery": "图库壁纸",
                "mod_random": "随机壁纸",
                "mod_tasks": "任务管理",
                "wifi_title": "可用 Wi-Fi 网络",
                "wifi_back": "返回",
                "wifi_connecting": "正在连接...",
                "wifi_connected": "已连接",
                "wifi_disconnect": "断开连接",
                "wifi_connect": "连接",
                "wifi_known": "已知网络",
                "wifi_scanning": "正在扫描无线网络...",
                "wifi_none": "未发现可用网络。",
                "wifi_settings": "打开网络详细设置",
                "bt_title": "蓝牙设备",
                "bt_back": "返回",
                "bt_disabled_title": "蓝牙已关闭",
                "bt_disabled_desc": "开启蓝牙以发现并连接周围设备",
                "bt_turn_on": "开启蓝牙",
                "bt_scanning": "正在搜索蓝牙设备...",
                "bt_none_found": "未找到设备。请点击上方扫描。",
                "bt_unnamed": "未命名设备",
                "bt_connected": "已连接",
                "bt_disconnected": "已断开",
                "bt_pair": "配对",
                "bt_disconnect": "断开",
                "bt_connect": "连接",
                "bt_remove": "移除设备",
                "bt_manager": "蓝牙管理器",
                "audio_title": "音频输出设备",
                "audio_back": "返回",
                "audio_none": "未检测到音频设备。",
                "audio_mixer": "应用音量混音器",
                "audio_no_apps": "暂无播放音频的应用。",
                "audio_pavucontrol": "音频首选项 (Pavucontrol)",
                "hypr_title": "Hyprland 实时配置项",
                "hypr_animations": "窗口动画",
                "hypr_blur": "毛玻璃模糊",
                "hypr_shadows": "窗口阴影",
                "hypr_perf": "性能配置",
                "hypr_gpu_profile": "显卡方案",
                "hypr_gpu_integrated": "核显模式",
                "hypr_gpu_igpu_only": "仅使用核显",
                "hypr_gpu_hybrid": "混合双显卡",
                "hypr_gpu_prime_auto": "PRIME 自动分配",
                "hypr_gpu_dedicated": "独显直连",
                "hypr_gpu_dgpu_only": "仅使用独显",
                "hypr_rounding": "圆角半径：",
                "hypr_gaps": "窗口间距：",
                "hypr_split": "分屏布局模式",
                "hypr_reload": "重新加载",
                "bat_ac_active": "电源适配器供电中",
                "bat_power": "实时功率",
                "bat_volt": "输出电压",
                "bat_health": "健康度",
                "bat_full": "已充饱",
                "bat_cycles": "充电循环",
                "bat_limit": "电量阈值",
                "notif_title": "系统通知",
                "notif_back": "返回",
                "notif_clear": "清除全部",
                "notif_tap_open": "点击打开应用",
                "notif_muted_apps": "静音应用",
                "notif_muted_desc": "来自已静音应用的通知将自动被忽略。",
                "notif_empty": "暂无新通知。",
                "clip_title": "剪贴板记录",
                "clip_clear": "清空记录",
                "clip_empty": "剪贴板为空：复制内容后在此查看",
                "ws_overview": "工作区概览",
                "ws_space": "空间",
                "ws_add": "新增工作区",
                "ws_footer": "Super + Tab 切换概览 • 点击切换工作区 • 󰅖 删除工作区",
                "nl_title": "夜览模式",
                "nl_back": "返回",
                "nl_temp": "屏幕色温",
                "nl_temp_desc": "数值越低偏暖黄，数值越高偏冷白。",
                "nl_gamma": "显示伽马",
                "nl_gamma_desc": "调低伽马可降低显示暗度；100% 为正常发光。",
                "nl_schedule": "定时开启",
                "nl_start": "开启时间",
                "nl_end": "关闭时间",
                "nl_disable": "关闭夜览",
                "nl_reset": "恢复默认 · 4500 K · 100%",
                "pair_title": "配对申请",
                "pair_back": "返回",
                "pair_reject": "拒绝",
                "pair_confirm": "确认配对",
                "pair_empty": "没有待处理的配对申请。",
                "ota_title": "系统升级",
                "ota_back": "返回",
                "ota_uptodate": "系统已是最新状态",
                "ota_checking": "正在检测系统更新...",
                "ota_new": "发现新系统更新",
                "ota_current": "当前安装版本",
                "ota_target": "目标升级版本",
                "ota_kernel": "Linux 内核",
                "ota_channel": "发布通道",
                "ota_changelog": "更新说明与历史日志"
        },
        "cmn": {
                "nl_candle": "烛光",
                "nl_warm": "暖色",
                "nl_balanced": "平衡",
                "nl_daylight": "日光",
                "nl_optional_off": "可选 · 关闭",
                "ota_last_checked": "上次检查：",
                "ota_recently": "刚刚",
                "ota_behind": "落后",
                "ota_loading_changelog": "正在加载更新日志...",
                "audio_active_apps": "个活动应用",
                "bt_scanning_short": "正在扫描附近...",
                "bt_devices_avail": "个可用设备",
                "bt_ready": "准备配对",
                "bt_hide_unnamed": "隐藏",
                "bt_show_unnamed": "显示",
                "bt_unnamed_desc": "未命名设备 (信标)",
                "bat_devices": "个设备",
                "sysmon_threads_active": "活动线程",
                "sysmon_uptime": "运行时间",
                "sysmon_processor": "处理器",
                "sysmon_util": "利用率",
                "mod_media_nothing": "暂无播放",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "已开启",
                "mod_wifi_disabled": "已关闭",
                "mod_wifi_connected": "已连接",
                "mod_bt": "蓝牙",
                "mod_bt_pairing": "待处理的配对请求",
                "mod_bt_enabled": "已开启",
                "mod_bt_disabled": "已关闭",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "已开启 · 点击隐藏",
                "mod_dock_disabled": "已关闭 · 点击显示",
                "mod_notif": "通知",
                "mod_notif_unread": "条未读",
                "mod_notif_none": "暂无未读",
                "mod_nl": "夜览模式",
                "mod_nl_inactive": "未激活",
                "mod_caffeine_awake": "清醒模式",
                "mod_caffeine_sleep": "正常休眠",
                "mod_powersave_eco": "节能模式",
                "mod_powersave_disabled": "已关闭",
                "mod_perf": "性能",
                "mod_perf_boost": "极致加速",
                "mod_perf_balanced": "平衡",
                "mod_dnd_silenced": "静音",
                "mod_dnd_sounds": "声音开启",
                "mod_audio_muted": "静音",
                "mod_record": "录屏",
                "wifi_hide": "隐藏",
                "wifi_show": "显示",
                "wifi_saved": "已保存",
                "bt_paired": "已配对",
                "bt_available": "可用",
                "bt_unnamed_device": "未命名设备",
                "audio_sink_active": "活动",
                "audio_select": "选择",
                "hypr_enabled": "已开启",
                "hypr_disabled": "已关闭",
                "hypr_max_perf": "极致性能",
                "hypr_balanced": "平衡",
                "hypr_power_source": "电源输入",
                "hypr_batteries": "电池",
                "bat_charging": "正在充电",
                "bat_on_battery": "电池供电",
                "bat_ac_online": "电源适配器已连接",
                "bat_external_power": "外部供电",
                "ws_active": "活动",
                "ws_empty": "空工作区",
                "nl_enabled": "已开启",
                "nl_disabled": "已关闭",
                "nl_active_desc": "蓝光护眼滤镜已生效",
                "nl_off_desc": "蓝光护眼滤镜已关闭",
                "nl_schedule_hint": "默认关闭。请设置 24 小时制起止时间以启用定时。",
                "nl_schedule_update": "更新定时计划",
                "nl_schedule_enable": "启用定时计划",
                "pair_waiting": "等待中",
                "pair_done": "已完成",
                "pair_closed": "已关闭",
                "pair_pin": "输入配对码",
                "pair_auth": "身份验证",
                "pair_code": "确认验证码",
                "pair_none": "没有待处理的配对请求。",
                "ota_available": "系统有新版本可用",
                "ota_check": "检查更新",
                "ota_install": "下载并安装",
                "ota_installing": "正在安装...",
                "sysmon_title": "系统监视器 (htop)",
                "sysmon_cli": "htop 命令行",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "内存",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "固态硬盘 /",
                "sysmon_cores": "CPU 核心活动",
                "sysmon_gpu": "显卡：",
                "sysmon_integrated_gpu": "标准集成显卡",
                "sysmon_top_proc": "主要进程",
                "sysmon_top_cpu": "CPU 占用最高",
                "sysmon_top_mem": "内存占用最高",
                "sysmon_pid": "PID",
                "sysmon_user": "用户",
                "sysmon_name": "名称",
                "sysmon_kill": "结束",
                "sysmon_kernel": "内核：Linux ",
                "sysmon_esc_close": "按 ESC 或点击外部以关闭",
                "lang_title": "语言与输入",
                "lang_subtitle": "键盘与语言设置",
                "lang_input_languages": "输入法布局",
                "lang_active": "当前使用",
                "lang_add_layout": "添加键盘布局",
                "lang_system_language": "系统语言",
                "lang_user_language": "当前用户语言：",
                "lang_change_display": "更改显示语言",
                "lang_change_system": "更改系统全局语言 (localectl)",
                "lang_footer_nav": "↑/↓ 移动 • 回车 选择 • Esc 关闭",
                "lang_add_title": "添加键盘布局",
                "lang_search_layout": "搜索语言或国家/地区...",
                "lang_add_btn": "+ 添加",
                "lang_select_display": "选择显示语言",
                "lang_select_system": "选择系统语言 (localectl)",
                "lang_search_locale": "搜索语言或区域代码...",
                "lang_select_btn": "选择",
                "tab_control": "控制中心",
                "tab_spaces": "工作区",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "剪贴板",
                "mod_bluetooth": "蓝牙",
                "mod_audio": "音频输出",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜览护眼",
                "mod_caffeine": "咖啡因模式",
                "mod_powersave": "省电模式",
                "mod_performance": "性能模式",
                "mod_dnd": "勿扰模式",
                "mod_volume": "音量",
                "mod_brightness": "亮度",
                "mod_picker": "取色器",
                "mod_gallery": "图库壁纸",
                "mod_random": "随机壁纸",
                "mod_tasks": "任务管理",
                "wifi_title": "可用 Wi-Fi 网络",
                "wifi_back": "返回",
                "wifi_connecting": "正在连接...",
                "wifi_connected": "已连接",
                "wifi_disconnect": "断开连接",
                "wifi_connect": "连接",
                "wifi_known": "已知网络",
                "wifi_scanning": "正在扫描无线网络...",
                "wifi_none": "未发现可用网络。",
                "wifi_settings": "打开网络详细设置",
                "bt_title": "蓝牙设备",
                "bt_back": "返回",
                "bt_disabled_title": "蓝牙已关闭",
                "bt_disabled_desc": "开启蓝牙以发现并连接周围设备",
                "bt_turn_on": "开启蓝牙",
                "bt_scanning": "正在搜索蓝牙设备...",
                "bt_none_found": "未找到设备。请点击上方扫描。",
                "bt_unnamed": "未命名设备",
                "bt_connected": "已连接",
                "bt_disconnected": "已断开",
                "bt_pair": "配对",
                "bt_disconnect": "断开",
                "bt_connect": "连接",
                "bt_remove": "移除设备",
                "bt_manager": "蓝牙管理器",
                "audio_title": "音频输出设备",
                "audio_back": "返回",
                "audio_none": "未检测到音频设备。",
                "audio_mixer": "应用音量混音器",
                "audio_no_apps": "暂无播放音频的应用。",
                "audio_pavucontrol": "音频首选项 (Pavucontrol)",
                "hypr_title": "Hyprland 实时配置项",
                "hypr_animations": "窗口动画",
                "hypr_blur": "毛玻璃模糊",
                "hypr_shadows": "窗口阴影",
                "hypr_perf": "性能配置",
                "hypr_gpu_profile": "显卡方案",
                "hypr_gpu_integrated": "核显模式",
                "hypr_gpu_igpu_only": "仅使用核显",
                "hypr_gpu_hybrid": "混合双显卡",
                "hypr_gpu_prime_auto": "PRIME 自动分配",
                "hypr_gpu_dedicated": "独显直连",
                "hypr_gpu_dgpu_only": "仅使用独显",
                "hypr_rounding": "圆角半径：",
                "hypr_gaps": "窗口间距：",
                "hypr_split": "分屏布局模式",
                "hypr_reload": "重新加载",
                "bat_ac_active": "电源适配器供电中",
                "bat_power": "实时功率",
                "bat_volt": "输出电压",
                "bat_health": "健康度",
                "bat_full": "已充饱",
                "bat_cycles": "充电循环",
                "bat_limit": "电量阈值",
                "notif_title": "系统通知",
                "notif_back": "返回",
                "notif_clear": "清除全部",
                "notif_tap_open": "点击打开应用",
                "notif_muted_apps": "静音应用",
                "notif_muted_desc": "来自已静音应用的通知将自动被忽略。",
                "notif_empty": "暂无新通知。",
                "clip_title": "剪贴板记录",
                "clip_clear": "清空记录",
                "clip_empty": "剪贴板为空：复制内容后在此查看",
                "ws_overview": "工作区概览",
                "ws_space": "空间",
                "ws_add": "新增工作区",
                "ws_footer": "Super + Tab 切换概览 • 点击切换工作区 • 󰅖 删除工作区",
                "nl_title": "夜览模式",
                "nl_back": "返回",
                "nl_temp": "屏幕色温",
                "nl_temp_desc": "数值越低偏暖黄，数值越高偏冷白。",
                "nl_gamma": "显示伽马",
                "nl_gamma_desc": "调低伽马可降低显示暗度；100% 为正常发光。",
                "nl_schedule": "定时开启",
                "nl_start": "开启时间",
                "nl_end": "关闭时间",
                "nl_disable": "关闭夜览",
                "nl_reset": "恢复默认 · 4500 K · 100%",
                "pair_title": "配对申请",
                "pair_back": "返回",
                "pair_reject": "拒绝",
                "pair_confirm": "确认配对",
                "pair_empty": "没有待处理的配对申请。",
                "ota_title": "系统升级",
                "ota_back": "返回",
                "ota_uptodate": "系统已是最新状态",
                "ota_checking": "正在检测系统更新...",
                "ota_new": "发现新系统更新",
                "ota_current": "当前安装版本",
                "ota_target": "目标升级版本",
                "ota_kernel": "Linux 内核",
                "ota_channel": "发布通道",
                "ota_changelog": "更新说明与历史日志"
        },
        "yue": {
                "nl_candle": "烛光",
                "nl_warm": "暖色",
                "nl_balanced": "平衡",
                "nl_daylight": "日光",
                "nl_optional_off": "可选 · 关闭",
                "ota_last_checked": "上次检查：",
                "ota_recently": "刚刚",
                "ota_behind": "落后",
                "ota_loading_changelog": "正在加载更新日志...",
                "audio_active_apps": "个活动应用",
                "bt_scanning_short": "正在扫描附近...",
                "bt_devices_avail": "个可用设备",
                "bt_ready": "准备配对",
                "bt_hide_unnamed": "隐藏",
                "bt_show_unnamed": "显示",
                "bt_unnamed_desc": "未命名设备 (信标)",
                "bat_devices": "个设备",
                "sysmon_threads_active": "活动线程",
                "sysmon_uptime": "运行时间",
                "sysmon_processor": "处理器",
                "sysmon_util": "利用率",
                "mod_media_nothing": "暂无播放",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "已开启",
                "mod_wifi_disabled": "已关闭",
                "mod_wifi_connected": "已连接",
                "mod_bt": "蓝牙",
                "mod_bt_pairing": "待处理的配对请求",
                "mod_bt_enabled": "已开启",
                "mod_bt_disabled": "已关闭",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "已开启 · 点击隐藏",
                "mod_dock_disabled": "已关闭 · 点击显示",
                "mod_notif": "通知",
                "mod_notif_unread": "条未读",
                "mod_notif_none": "暂无未读",
                "mod_nl": "夜览模式",
                "mod_nl_inactive": "未激活",
                "mod_caffeine_awake": "清醒模式",
                "mod_caffeine_sleep": "正常休眠",
                "mod_powersave_eco": "节能模式",
                "mod_powersave_disabled": "已关闭",
                "mod_perf": "性能",
                "mod_perf_boost": "极致加速",
                "mod_perf_balanced": "平衡",
                "mod_dnd_silenced": "静音",
                "mod_dnd_sounds": "声音开启",
                "mod_audio_muted": "静音",
                "mod_record": "录屏",
                "wifi_hide": "隐藏",
                "wifi_show": "显示",
                "wifi_saved": "已保存",
                "bt_paired": "已配对",
                "bt_available": "可用",
                "bt_unnamed_device": "未命名设备",
                "audio_sink_active": "活动",
                "audio_select": "选择",
                "hypr_enabled": "已开启",
                "hypr_disabled": "已关闭",
                "hypr_max_perf": "极致性能",
                "hypr_balanced": "平衡",
                "hypr_power_source": "电源输入",
                "hypr_batteries": "电池",
                "bat_charging": "正在充电",
                "bat_on_battery": "电池供电",
                "bat_ac_online": "电源适配器已连接",
                "bat_external_power": "外部供电",
                "ws_active": "活动",
                "ws_empty": "空工作区",
                "nl_enabled": "已开启",
                "nl_disabled": "已关闭",
                "nl_active_desc": "蓝光护眼滤镜已生效",
                "nl_off_desc": "蓝光护眼滤镜已关闭",
                "nl_schedule_hint": "默认关闭。请设置 24 小时制起止时间以启用定时。",
                "nl_schedule_update": "更新定时计划",
                "nl_schedule_enable": "启用定时计划",
                "pair_waiting": "等待中",
                "pair_done": "已完成",
                "pair_closed": "已关闭",
                "pair_pin": "输入配对码",
                "pair_auth": "身份验证",
                "pair_code": "确认验证码",
                "pair_none": "没有待处理的配对请求。",
                "ota_available": "系统有新版本可用",
                "ota_check": "检查更新",
                "ota_install": "下载并安装",
                "ota_installing": "正在安装...",
                "sysmon_title": "系统监视器 (htop)",
                "sysmon_cli": "htop 命令行",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "内存",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "固态硬盘 /",
                "sysmon_cores": "CPU 核心活动",
                "sysmon_gpu": "显卡：",
                "sysmon_integrated_gpu": "标准集成显卡",
                "sysmon_top_proc": "主要进程",
                "sysmon_top_cpu": "CPU 占用最高",
                "sysmon_top_mem": "内存占用最高",
                "sysmon_pid": "PID",
                "sysmon_user": "用户",
                "sysmon_name": "名称",
                "sysmon_kill": "结束",
                "sysmon_kernel": "内核：Linux ",
                "sysmon_esc_close": "按 ESC 或点击外部以关闭",
                "lang_title": "语言与输入",
                "lang_subtitle": "键盘与语言设置",
                "lang_input_languages": "输入法布局",
                "lang_active": "当前使用",
                "lang_add_layout": "添加键盘布局",
                "lang_system_language": "系统语言",
                "lang_user_language": "当前用户语言：",
                "lang_change_display": "更改显示语言",
                "lang_change_system": "更改系统全局语言 (localectl)",
                "lang_footer_nav": "↑/↓ 移动 • 回车 选择 • Esc 关闭",
                "lang_add_title": "添加键盘布局",
                "lang_search_layout": "搜索语言或国家/地区...",
                "lang_add_btn": "+ 添加",
                "lang_select_display": "选择显示语言",
                "lang_select_system": "选择系统语言 (localectl)",
                "lang_search_locale": "搜索语言或区域代码...",
                "lang_select_btn": "选择",
                "tab_control": "控制中心",
                "tab_spaces": "工作区",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "剪贴板",
                "mod_bluetooth": "蓝牙",
                "mod_audio": "音频输出",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜览护眼",
                "mod_caffeine": "咖啡因模式",
                "mod_powersave": "省电模式",
                "mod_performance": "性能模式",
                "mod_dnd": "勿扰模式",
                "mod_volume": "音量",
                "mod_brightness": "亮度",
                "mod_picker": "取色器",
                "mod_gallery": "图库壁纸",
                "mod_random": "随机壁纸",
                "mod_tasks": "任务管理",
                "wifi_title": "可用 Wi-Fi 网络",
                "wifi_back": "返回",
                "wifi_connecting": "正在连接...",
                "wifi_connected": "已连接",
                "wifi_disconnect": "断开连接",
                "wifi_connect": "连接",
                "wifi_known": "已知网络",
                "wifi_scanning": "正在扫描无线网络...",
                "wifi_none": "未发现可用网络。",
                "wifi_settings": "打开网络详细设置",
                "bt_title": "蓝牙设备",
                "bt_back": "返回",
                "bt_disabled_title": "蓝牙已关闭",
                "bt_disabled_desc": "开启蓝牙以发现并连接周围设备",
                "bt_turn_on": "开启蓝牙",
                "bt_scanning": "正在搜索蓝牙设备...",
                "bt_none_found": "未找到设备。请点击上方扫描。",
                "bt_unnamed": "未命名设备",
                "bt_connected": "已连接",
                "bt_disconnected": "已断开",
                "bt_pair": "配对",
                "bt_disconnect": "断开",
                "bt_connect": "连接",
                "bt_remove": "移除设备",
                "bt_manager": "蓝牙管理器",
                "audio_title": "音频输出设备",
                "audio_back": "返回",
                "audio_none": "未检测到音频设备。",
                "audio_mixer": "应用音量混音器",
                "audio_no_apps": "暂无播放音频的应用。",
                "audio_pavucontrol": "音频首选项 (Pavucontrol)",
                "hypr_title": "Hyprland 实时配置项",
                "hypr_animations": "窗口动画",
                "hypr_blur": "毛玻璃模糊",
                "hypr_shadows": "窗口阴影",
                "hypr_perf": "性能配置",
                "hypr_gpu_profile": "显卡方案",
                "hypr_gpu_integrated": "核显模式",
                "hypr_gpu_igpu_only": "仅使用核显",
                "hypr_gpu_hybrid": "混合双显卡",
                "hypr_gpu_prime_auto": "PRIME 自动分配",
                "hypr_gpu_dedicated": "独显直连",
                "hypr_gpu_dgpu_only": "仅使用独显",
                "hypr_rounding": "圆角半径：",
                "hypr_gaps": "窗口间距：",
                "hypr_split": "分屏布局模式",
                "hypr_reload": "重新加载",
                "bat_ac_active": "电源适配器供电中",
                "bat_power": "实时功率",
                "bat_volt": "输出电压",
                "bat_health": "健康度",
                "bat_full": "已充饱",
                "bat_cycles": "充电循环",
                "bat_limit": "电量阈值",
                "notif_title": "系统通知",
                "notif_back": "返回",
                "notif_clear": "清除全部",
                "notif_tap_open": "点击打开应用",
                "notif_muted_apps": "静音应用",
                "notif_muted_desc": "来自已静音应用的通知将自动被忽略。",
                "notif_empty": "暂无新通知。",
                "clip_title": "剪贴板记录",
                "clip_clear": "清空记录",
                "clip_empty": "剪贴板为空：复制内容后在此查看",
                "ws_overview": "工作区概览",
                "ws_space": "空间",
                "ws_add": "新增工作区",
                "ws_footer": "Super + Tab 切换概览 • 点击切换工作区 • 󰅖 删除工作区",
                "nl_title": "夜览模式",
                "nl_back": "返回",
                "nl_temp": "屏幕色温",
                "nl_temp_desc": "数值越低偏暖黄，数值越高偏冷白。",
                "nl_gamma": "显示伽马",
                "nl_gamma_desc": "调低伽马可降低显示暗度；100% 为正常发光。",
                "nl_schedule": "定时开启",
                "nl_start": "开启时间",
                "nl_end": "关闭时间",
                "nl_disable": "关闭夜览",
                "nl_reset": "恢复默认 · 4500 K · 100%",
                "pair_title": "配对申请",
                "pair_back": "返回",
                "pair_reject": "拒绝",
                "pair_confirm": "确认配对",
                "pair_empty": "没有待处理的配对申请。",
                "ota_title": "系统升级",
                "ota_back": "返回",
                "ota_uptodate": "系统已是最新状态",
                "ota_checking": "正在检测系统更新...",
                "ota_new": "发现新系统更新",
                "ota_current": "当前安装版本",
                "ota_target": "目标升级版本",
                "ota_kernel": "Linux 内核",
                "ota_channel": "发布通道",
                "ota_changelog": "更新说明与历史日志"
        },
        "lzh": {
                "nl_candle": "烛光",
                "nl_warm": "暖色",
                "nl_balanced": "平衡",
                "nl_daylight": "日光",
                "nl_optional_off": "可选 · 关闭",
                "ota_last_checked": "上次检查：",
                "ota_recently": "刚刚",
                "ota_behind": "落后",
                "ota_loading_changelog": "正在加载更新日志...",
                "audio_active_apps": "个活动应用",
                "bt_scanning_short": "正在扫描附近...",
                "bt_devices_avail": "个可用设备",
                "bt_ready": "准备配对",
                "bt_hide_unnamed": "隐藏",
                "bt_show_unnamed": "显示",
                "bt_unnamed_desc": "未命名设备 (信标)",
                "bat_devices": "个设备",
                "sysmon_threads_active": "活动线程",
                "sysmon_uptime": "运行时间",
                "sysmon_processor": "处理器",
                "sysmon_util": "利用率",
                "mod_media_nothing": "暂无播放",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "已开启",
                "mod_wifi_disabled": "已关闭",
                "mod_wifi_connected": "已连接",
                "mod_bt": "蓝牙",
                "mod_bt_pairing": "待处理的配对请求",
                "mod_bt_enabled": "已开启",
                "mod_bt_disabled": "已关闭",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "已开启 · 点击隐藏",
                "mod_dock_disabled": "已关闭 · 点击显示",
                "mod_notif": "通知",
                "mod_notif_unread": "条未读",
                "mod_notif_none": "暂无未读",
                "mod_nl": "夜览模式",
                "mod_nl_inactive": "未激活",
                "mod_caffeine_awake": "清醒模式",
                "mod_caffeine_sleep": "正常休眠",
                "mod_powersave_eco": "节能模式",
                "mod_powersave_disabled": "已关闭",
                "mod_perf": "性能",
                "mod_perf_boost": "极致加速",
                "mod_perf_balanced": "平衡",
                "mod_dnd_silenced": "静音",
                "mod_dnd_sounds": "声音开启",
                "mod_audio_muted": "静音",
                "mod_record": "录屏",
                "wifi_hide": "隐藏",
                "wifi_show": "显示",
                "wifi_saved": "已保存",
                "bt_paired": "已配对",
                "bt_available": "可用",
                "bt_unnamed_device": "未命名设备",
                "audio_sink_active": "活动",
                "audio_select": "选择",
                "hypr_enabled": "已开启",
                "hypr_disabled": "已关闭",
                "hypr_max_perf": "极致性能",
                "hypr_balanced": "平衡",
                "hypr_power_source": "电源输入",
                "hypr_batteries": "电池",
                "bat_charging": "正在充电",
                "bat_on_battery": "电池供电",
                "bat_ac_online": "电源适配器已连接",
                "bat_external_power": "外部供电",
                "ws_active": "活动",
                "ws_empty": "空工作区",
                "nl_enabled": "已开启",
                "nl_disabled": "已关闭",
                "nl_active_desc": "蓝光护眼滤镜已生效",
                "nl_off_desc": "蓝光护眼滤镜已关闭",
                "nl_schedule_hint": "默认关闭。请设置 24 小时制起止时间以启用定时。",
                "nl_schedule_update": "更新定时计划",
                "nl_schedule_enable": "启用定时计划",
                "pair_waiting": "等待中",
                "pair_done": "已完成",
                "pair_closed": "已关闭",
                "pair_pin": "输入配对码",
                "pair_auth": "身份验证",
                "pair_code": "确认验证码",
                "pair_none": "没有待处理的配对请求。",
                "ota_available": "系统有新版本可用",
                "ota_check": "检查更新",
                "ota_install": "下载并安装",
                "ota_installing": "正在安装...",
                "sysmon_title": "系统监视器 (htop)",
                "sysmon_cli": "htop 命令行",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "内存",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "固态硬盘 /",
                "sysmon_cores": "CPU 核心活动",
                "sysmon_gpu": "显卡：",
                "sysmon_integrated_gpu": "标准集成显卡",
                "sysmon_top_proc": "主要进程",
                "sysmon_top_cpu": "CPU 占用最高",
                "sysmon_top_mem": "内存占用最高",
                "sysmon_pid": "PID",
                "sysmon_user": "用户",
                "sysmon_name": "名称",
                "sysmon_kill": "结束",
                "sysmon_kernel": "内核：Linux ",
                "sysmon_esc_close": "按 ESC 或点击外部以关闭",
                "lang_title": "语言与输入",
                "lang_subtitle": "键盘与语言设置",
                "lang_input_languages": "输入法布局",
                "lang_active": "当前使用",
                "lang_add_layout": "添加键盘布局",
                "lang_system_language": "系统语言",
                "lang_user_language": "当前用户语言：",
                "lang_change_display": "更改显示语言",
                "lang_change_system": "更改系统全局语言 (localectl)",
                "lang_footer_nav": "↑/↓ 移动 • 回车 选择 • Esc 关闭",
                "lang_add_title": "添加键盘布局",
                "lang_search_layout": "搜索语言或国家/地区...",
                "lang_add_btn": "+ 添加",
                "lang_select_display": "选择显示语言",
                "lang_select_system": "选择系统语言 (localectl)",
                "lang_search_locale": "搜索语言或区域代码...",
                "lang_select_btn": "选择",
                "tab_control": "控制中心",
                "tab_spaces": "工作区",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "剪贴板",
                "mod_bluetooth": "蓝牙",
                "mod_audio": "音频输出",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜览护眼",
                "mod_caffeine": "咖啡因模式",
                "mod_powersave": "省电模式",
                "mod_performance": "性能模式",
                "mod_dnd": "勿扰模式",
                "mod_volume": "音量",
                "mod_brightness": "亮度",
                "mod_picker": "取色器",
                "mod_gallery": "图库壁纸",
                "mod_random": "随机壁纸",
                "mod_tasks": "任务管理",
                "wifi_title": "可用 Wi-Fi 网络",
                "wifi_back": "返回",
                "wifi_connecting": "正在连接...",
                "wifi_connected": "已连接",
                "wifi_disconnect": "断开连接",
                "wifi_connect": "连接",
                "wifi_known": "已知网络",
                "wifi_scanning": "正在扫描无线网络...",
                "wifi_none": "未发现可用网络。",
                "wifi_settings": "打开网络详细设置",
                "bt_title": "蓝牙设备",
                "bt_back": "返回",
                "bt_disabled_title": "蓝牙已关闭",
                "bt_disabled_desc": "开启蓝牙以发现并连接周围设备",
                "bt_turn_on": "开启蓝牙",
                "bt_scanning": "正在搜索蓝牙设备...",
                "bt_none_found": "未找到设备。请点击上方扫描。",
                "bt_unnamed": "未命名设备",
                "bt_connected": "已连接",
                "bt_disconnected": "已断开",
                "bt_pair": "配对",
                "bt_disconnect": "断开",
                "bt_connect": "连接",
                "bt_remove": "移除设备",
                "bt_manager": "蓝牙管理器",
                "audio_title": "音频输出设备",
                "audio_back": "返回",
                "audio_none": "未检测到音频设备。",
                "audio_mixer": "应用音量混音器",
                "audio_no_apps": "暂无播放音频的应用。",
                "audio_pavucontrol": "音频首选项 (Pavucontrol)",
                "hypr_title": "Hyprland 实时配置项",
                "hypr_animations": "窗口动画",
                "hypr_blur": "毛玻璃模糊",
                "hypr_shadows": "窗口阴影",
                "hypr_perf": "性能配置",
                "hypr_gpu_profile": "显卡方案",
                "hypr_gpu_integrated": "核显模式",
                "hypr_gpu_igpu_only": "仅使用核显",
                "hypr_gpu_hybrid": "混合双显卡",
                "hypr_gpu_prime_auto": "PRIME 自动分配",
                "hypr_gpu_dedicated": "独显直连",
                "hypr_gpu_dgpu_only": "仅使用独显",
                "hypr_rounding": "圆角半径：",
                "hypr_gaps": "窗口间距：",
                "hypr_split": "分屏布局模式",
                "hypr_reload": "重新加载",
                "bat_ac_active": "电源适配器供电中",
                "bat_power": "实时功率",
                "bat_volt": "输出电压",
                "bat_health": "健康度",
                "bat_full": "已充饱",
                "bat_cycles": "充电循环",
                "bat_limit": "电量阈值",
                "notif_title": "系统通知",
                "notif_back": "返回",
                "notif_clear": "清除全部",
                "notif_tap_open": "点击打开应用",
                "notif_muted_apps": "静音应用",
                "notif_muted_desc": "来自已静音应用的通知将自动被忽略。",
                "notif_empty": "暂无新通知。",
                "clip_title": "剪贴板记录",
                "clip_clear": "清空记录",
                "clip_empty": "剪贴板为空：复制内容后在此查看",
                "ws_overview": "工作区概览",
                "ws_space": "空间",
                "ws_add": "新增工作区",
                "ws_footer": "Super + Tab 切换概览 • 点击切换工作区 • 󰅖 删除工作区",
                "nl_title": "夜览模式",
                "nl_back": "返回",
                "nl_temp": "屏幕色温",
                "nl_temp_desc": "数值越低偏暖黄，数值越高偏冷白。",
                "nl_gamma": "显示伽马",
                "nl_gamma_desc": "调低伽马可降低显示暗度；100% 为正常发光。",
                "nl_schedule": "定时开启",
                "nl_start": "开启时间",
                "nl_end": "关闭时间",
                "nl_disable": "关闭夜览",
                "nl_reset": "恢复默认 · 4500 K · 100%",
                "pair_title": "配对申请",
                "pair_back": "返回",
                "pair_reject": "拒绝",
                "pair_confirm": "确认配对",
                "pair_empty": "没有待处理的配对申请。",
                "ota_title": "系统升级",
                "ota_back": "返回",
                "ota_uptodate": "系统已是最新状态",
                "ota_checking": "正在检测系统更新...",
                "ota_new": "发现新系统更新",
                "ota_current": "当前安装版本",
                "ota_target": "目标升级版本",
                "ota_kernel": "Linux 内核",
                "ota_channel": "发布通道",
                "ota_changelog": "更新说明与历史日志"
        },
        "hak": {
                "nl_candle": "烛光",
                "nl_warm": "暖色",
                "nl_balanced": "平衡",
                "nl_daylight": "日光",
                "nl_optional_off": "可选 · 关闭",
                "ota_last_checked": "上次检查：",
                "ota_recently": "刚刚",
                "ota_behind": "落后",
                "ota_loading_changelog": "正在加载更新日志...",
                "audio_active_apps": "个活动应用",
                "bt_scanning_short": "正在扫描附近...",
                "bt_devices_avail": "个可用设备",
                "bt_ready": "准备配对",
                "bt_hide_unnamed": "隐藏",
                "bt_show_unnamed": "显示",
                "bt_unnamed_desc": "未命名设备 (信标)",
                "bat_devices": "个设备",
                "sysmon_threads_active": "活动线程",
                "sysmon_uptime": "运行时间",
                "sysmon_processor": "处理器",
                "sysmon_util": "利用率",
                "mod_media_nothing": "暂无播放",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "已开启",
                "mod_wifi_disabled": "已关闭",
                "mod_wifi_connected": "已连接",
                "mod_bt": "蓝牙",
                "mod_bt_pairing": "待处理的配对请求",
                "mod_bt_enabled": "已开启",
                "mod_bt_disabled": "已关闭",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "已开启 · 点击隐藏",
                "mod_dock_disabled": "已关闭 · 点击显示",
                "mod_notif": "通知",
                "mod_notif_unread": "条未读",
                "mod_notif_none": "暂无未读",
                "mod_nl": "夜览模式",
                "mod_nl_inactive": "未激活",
                "mod_caffeine_awake": "清醒模式",
                "mod_caffeine_sleep": "正常休眠",
                "mod_powersave_eco": "节能模式",
                "mod_powersave_disabled": "已关闭",
                "mod_perf": "性能",
                "mod_perf_boost": "极致加速",
                "mod_perf_balanced": "平衡",
                "mod_dnd_silenced": "静音",
                "mod_dnd_sounds": "声音开启",
                "mod_audio_muted": "静音",
                "mod_record": "录屏",
                "wifi_hide": "隐藏",
                "wifi_show": "显示",
                "wifi_saved": "已保存",
                "bt_paired": "已配对",
                "bt_available": "可用",
                "bt_unnamed_device": "未命名设备",
                "audio_sink_active": "活动",
                "audio_select": "选择",
                "hypr_enabled": "已开启",
                "hypr_disabled": "已关闭",
                "hypr_max_perf": "极致性能",
                "hypr_balanced": "平衡",
                "hypr_power_source": "电源输入",
                "hypr_batteries": "电池",
                "bat_charging": "正在充电",
                "bat_on_battery": "电池供电",
                "bat_ac_online": "电源适配器已连接",
                "bat_external_power": "外部供电",
                "ws_active": "活动",
                "ws_empty": "空工作区",
                "nl_enabled": "已开启",
                "nl_disabled": "已关闭",
                "nl_active_desc": "蓝光护眼滤镜已生效",
                "nl_off_desc": "蓝光护眼滤镜已关闭",
                "nl_schedule_hint": "默认关闭。请设置 24 小时制起止时间以启用定时。",
                "nl_schedule_update": "更新定时计划",
                "nl_schedule_enable": "启用定时计划",
                "pair_waiting": "等待中",
                "pair_done": "已完成",
                "pair_closed": "已关闭",
                "pair_pin": "输入配对码",
                "pair_auth": "身份验证",
                "pair_code": "确认验证码",
                "pair_none": "没有待处理的配对请求。",
                "ota_available": "系统有新版本可用",
                "ota_check": "检查更新",
                "ota_install": "下载并安装",
                "ota_installing": "正在安装...",
                "sysmon_title": "系统监视器 (htop)",
                "sysmon_cli": "htop 命令行",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "内存",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "固态硬盘 /",
                "sysmon_cores": "CPU 核心活动",
                "sysmon_gpu": "显卡：",
                "sysmon_integrated_gpu": "标准集成显卡",
                "sysmon_top_proc": "主要进程",
                "sysmon_top_cpu": "CPU 占用最高",
                "sysmon_top_mem": "内存占用最高",
                "sysmon_pid": "PID",
                "sysmon_user": "用户",
                "sysmon_name": "名称",
                "sysmon_kill": "结束",
                "sysmon_kernel": "内核：Linux ",
                "sysmon_esc_close": "按 ESC 或点击外部以关闭",
                "lang_title": "语言与输入",
                "lang_subtitle": "键盘与语言设置",
                "lang_input_languages": "输入法布局",
                "lang_active": "当前使用",
                "lang_add_layout": "添加键盘布局",
                "lang_system_language": "系统语言",
                "lang_user_language": "当前用户语言：",
                "lang_change_display": "更改显示语言",
                "lang_change_system": "更改系统全局语言 (localectl)",
                "lang_footer_nav": "↑/↓ 移动 • 回车 选择 • Esc 关闭",
                "lang_add_title": "添加键盘布局",
                "lang_search_layout": "搜索语言或国家/地区...",
                "lang_add_btn": "+ 添加",
                "lang_select_display": "选择显示语言",
                "lang_select_system": "选择系统语言 (localectl)",
                "lang_search_locale": "搜索语言或区域代码...",
                "lang_select_btn": "选择",
                "tab_control": "控制中心",
                "tab_spaces": "工作区",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "剪贴板",
                "mod_bluetooth": "蓝牙",
                "mod_audio": "音频输出",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜览护眼",
                "mod_caffeine": "咖啡因模式",
                "mod_powersave": "省电模式",
                "mod_performance": "性能模式",
                "mod_dnd": "勿扰模式",
                "mod_volume": "音量",
                "mod_brightness": "亮度",
                "mod_picker": "取色器",
                "mod_gallery": "图库壁纸",
                "mod_random": "随机壁纸",
                "mod_tasks": "任务管理",
                "wifi_title": "可用 Wi-Fi 网络",
                "wifi_back": "返回",
                "wifi_connecting": "正在连接...",
                "wifi_connected": "已连接",
                "wifi_disconnect": "断开连接",
                "wifi_connect": "连接",
                "wifi_known": "已知网络",
                "wifi_scanning": "正在扫描无线网络...",
                "wifi_none": "未发现可用网络。",
                "wifi_settings": "打开网络详细设置",
                "bt_title": "蓝牙设备",
                "bt_back": "返回",
                "bt_disabled_title": "蓝牙已关闭",
                "bt_disabled_desc": "开启蓝牙以发现并连接周围设备",
                "bt_turn_on": "开启蓝牙",
                "bt_scanning": "正在搜索蓝牙设备...",
                "bt_none_found": "未找到设备。请点击上方扫描。",
                "bt_unnamed": "未命名设备",
                "bt_connected": "已连接",
                "bt_disconnected": "已断开",
                "bt_pair": "配对",
                "bt_disconnect": "断开",
                "bt_connect": "连接",
                "bt_remove": "移除设备",
                "bt_manager": "蓝牙管理器",
                "audio_title": "音频输出设备",
                "audio_back": "返回",
                "audio_none": "未检测到音频设备。",
                "audio_mixer": "应用音量混音器",
                "audio_no_apps": "暂无播放音频的应用。",
                "audio_pavucontrol": "音频首选项 (Pavucontrol)",
                "hypr_title": "Hyprland 实时配置项",
                "hypr_animations": "窗口动画",
                "hypr_blur": "毛玻璃模糊",
                "hypr_shadows": "窗口阴影",
                "hypr_perf": "性能配置",
                "hypr_gpu_profile": "显卡方案",
                "hypr_gpu_integrated": "核显模式",
                "hypr_gpu_igpu_only": "仅使用核显",
                "hypr_gpu_hybrid": "混合双显卡",
                "hypr_gpu_prime_auto": "PRIME 自动分配",
                "hypr_gpu_dedicated": "独显直连",
                "hypr_gpu_dgpu_only": "仅使用独显",
                "hypr_rounding": "圆角半径：",
                "hypr_gaps": "窗口间距：",
                "hypr_split": "分屏布局模式",
                "hypr_reload": "重新加载",
                "bat_ac_active": "电源适配器供电中",
                "bat_power": "实时功率",
                "bat_volt": "输出电压",
                "bat_health": "健康度",
                "bat_full": "已充饱",
                "bat_cycles": "充电循环",
                "bat_limit": "电量阈值",
                "notif_title": "系统通知",
                "notif_back": "返回",
                "notif_clear": "清除全部",
                "notif_tap_open": "点击打开应用",
                "notif_muted_apps": "静音应用",
                "notif_muted_desc": "来自已静音应用的通知将自动被忽略。",
                "notif_empty": "暂无新通知。",
                "clip_title": "剪贴板记录",
                "clip_clear": "清空记录",
                "clip_empty": "剪贴板为空：复制内容后在此查看",
                "ws_overview": "工作区概览",
                "ws_space": "空间",
                "ws_add": "新增工作区",
                "ws_footer": "Super + Tab 切换概览 • 点击切换工作区 • 󰅖 删除工作区",
                "nl_title": "夜览模式",
                "nl_back": "返回",
                "nl_temp": "屏幕色温",
                "nl_temp_desc": "数值越低偏暖黄，数值越高偏冷白。",
                "nl_gamma": "显示伽马",
                "nl_gamma_desc": "调低伽马可降低显示暗度；100% 为正常发光。",
                "nl_schedule": "定时开启",
                "nl_start": "开启时间",
                "nl_end": "关闭时间",
                "nl_disable": "关闭夜览",
                "nl_reset": "恢复默认 · 4500 K · 100%",
                "pair_title": "配对申请",
                "pair_back": "返回",
                "pair_reject": "拒绝",
                "pair_confirm": "确认配对",
                "pair_empty": "没有待处理的配对申请。",
                "ota_title": "系统升级",
                "ota_back": "返回",
                "ota_uptodate": "系统已是最新状态",
                "ota_checking": "正在检测系统更新...",
                "ota_new": "发现新系统更新",
                "ota_current": "当前安装版本",
                "ota_target": "目标升级版本",
                "ota_kernel": "Linux 内核",
                "ota_channel": "发布通道",
                "ota_changelog": "更新说明与历史日志"
        },
        "nan": {
                "nl_candle": "烛光",
                "nl_warm": "暖色",
                "nl_balanced": "平衡",
                "nl_daylight": "日光",
                "nl_optional_off": "可选 · 关闭",
                "ota_last_checked": "上次检查：",
                "ota_recently": "刚刚",
                "ota_behind": "落后",
                "ota_loading_changelog": "正在加载更新日志...",
                "audio_active_apps": "个活动应用",
                "bt_scanning_short": "正在扫描附近...",
                "bt_devices_avail": "个可用设备",
                "bt_ready": "准备配对",
                "bt_hide_unnamed": "隐藏",
                "bt_show_unnamed": "显示",
                "bt_unnamed_desc": "未命名设备 (信标)",
                "bat_devices": "个设备",
                "sysmon_threads_active": "活动线程",
                "sysmon_uptime": "运行时间",
                "sysmon_processor": "处理器",
                "sysmon_util": "利用率",
                "mod_media_nothing": "暂无播放",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "已开启",
                "mod_wifi_disabled": "已关闭",
                "mod_wifi_connected": "已连接",
                "mod_bt": "蓝牙",
                "mod_bt_pairing": "待处理的配对请求",
                "mod_bt_enabled": "已开启",
                "mod_bt_disabled": "已关闭",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "已开启 · 点击隐藏",
                "mod_dock_disabled": "已关闭 · 点击显示",
                "mod_notif": "通知",
                "mod_notif_unread": "条未读",
                "mod_notif_none": "暂无未读",
                "mod_nl": "夜览模式",
                "mod_nl_inactive": "未激活",
                "mod_caffeine_awake": "清醒模式",
                "mod_caffeine_sleep": "正常休眠",
                "mod_powersave_eco": "节能模式",
                "mod_powersave_disabled": "已关闭",
                "mod_perf": "性能",
                "mod_perf_boost": "极致加速",
                "mod_perf_balanced": "平衡",
                "mod_dnd_silenced": "静音",
                "mod_dnd_sounds": "声音开启",
                "mod_audio_muted": "静音",
                "mod_record": "录屏",
                "wifi_hide": "隐藏",
                "wifi_show": "显示",
                "wifi_saved": "已保存",
                "bt_paired": "已配对",
                "bt_available": "可用",
                "bt_unnamed_device": "未命名设备",
                "audio_sink_active": "活动",
                "audio_select": "选择",
                "hypr_enabled": "已开启",
                "hypr_disabled": "已关闭",
                "hypr_max_perf": "极致性能",
                "hypr_balanced": "平衡",
                "hypr_power_source": "电源输入",
                "hypr_batteries": "电池",
                "bat_charging": "正在充电",
                "bat_on_battery": "电池供电",
                "bat_ac_online": "电源适配器已连接",
                "bat_external_power": "外部供电",
                "ws_active": "活动",
                "ws_empty": "空工作区",
                "nl_enabled": "已开启",
                "nl_disabled": "已关闭",
                "nl_active_desc": "蓝光护眼滤镜已生效",
                "nl_off_desc": "蓝光护眼滤镜已关闭",
                "nl_schedule_hint": "默认关闭。请设置 24 小时制起止时间以启用定时。",
                "nl_schedule_update": "更新定时计划",
                "nl_schedule_enable": "启用定时计划",
                "pair_waiting": "等待中",
                "pair_done": "已完成",
                "pair_closed": "已关闭",
                "pair_pin": "输入配对码",
                "pair_auth": "身份验证",
                "pair_code": "确认验证码",
                "pair_none": "没有待处理的配对请求。",
                "ota_available": "系统有新版本可用",
                "ota_check": "检查更新",
                "ota_install": "下载并安装",
                "ota_installing": "正在安装...",
                "sysmon_title": "系统监视器 (htop)",
                "sysmon_cli": "htop 命令行",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "内存",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "固态硬盘 /",
                "sysmon_cores": "CPU 核心活动",
                "sysmon_gpu": "显卡：",
                "sysmon_integrated_gpu": "标准集成显卡",
                "sysmon_top_proc": "主要进程",
                "sysmon_top_cpu": "CPU 占用最高",
                "sysmon_top_mem": "内存占用最高",
                "sysmon_pid": "PID",
                "sysmon_user": "用户",
                "sysmon_name": "名称",
                "sysmon_kill": "结束",
                "sysmon_kernel": "内核：Linux ",
                "sysmon_esc_close": "按 ESC 或点击外部以关闭",
                "lang_title": "语言与输入",
                "lang_subtitle": "键盘与语言设置",
                "lang_input_languages": "输入法布局",
                "lang_active": "当前使用",
                "lang_add_layout": "添加键盘布局",
                "lang_system_language": "系统语言",
                "lang_user_language": "当前用户语言：",
                "lang_change_display": "更改显示语言",
                "lang_change_system": "更改系统全局语言 (localectl)",
                "lang_footer_nav": "↑/↓ 移动 • 回车 选择 • Esc 关闭",
                "lang_add_title": "添加键盘布局",
                "lang_search_layout": "搜索语言或国家/地区...",
                "lang_add_btn": "+ 添加",
                "lang_select_display": "选择显示语言",
                "lang_select_system": "选择系统语言 (localectl)",
                "lang_search_locale": "搜索语言或区域代码...",
                "lang_select_btn": "选择",
                "tab_control": "控制中心",
                "tab_spaces": "工作区",
                "tab_hypr": "Hypr",
                "tab_alerts": "通知",
                "tab_clips": "剪贴板",
                "mod_bluetooth": "蓝牙",
                "mod_audio": "音频输出",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "通知",
                "mod_nightlight": "夜览护眼",
                "mod_caffeine": "咖啡因模式",
                "mod_powersave": "省电模式",
                "mod_performance": "性能模式",
                "mod_dnd": "勿扰模式",
                "mod_volume": "音量",
                "mod_brightness": "亮度",
                "mod_picker": "取色器",
                "mod_gallery": "图库壁纸",
                "mod_random": "随机壁纸",
                "mod_tasks": "任务管理",
                "wifi_title": "可用 Wi-Fi 网络",
                "wifi_back": "返回",
                "wifi_connecting": "正在连接...",
                "wifi_connected": "已连接",
                "wifi_disconnect": "断开连接",
                "wifi_connect": "连接",
                "wifi_known": "已知网络",
                "wifi_scanning": "正在扫描无线网络...",
                "wifi_none": "未发现可用网络。",
                "wifi_settings": "打开网络详细设置",
                "bt_title": "蓝牙设备",
                "bt_back": "返回",
                "bt_disabled_title": "蓝牙已关闭",
                "bt_disabled_desc": "开启蓝牙以发现并连接周围设备",
                "bt_turn_on": "开启蓝牙",
                "bt_scanning": "正在搜索蓝牙设备...",
                "bt_none_found": "未找到设备。请点击上方扫描。",
                "bt_unnamed": "未命名设备",
                "bt_connected": "已连接",
                "bt_disconnected": "已断开",
                "bt_pair": "配对",
                "bt_disconnect": "断开",
                "bt_connect": "连接",
                "bt_remove": "移除设备",
                "bt_manager": "蓝牙管理器",
                "audio_title": "音频输出设备",
                "audio_back": "返回",
                "audio_none": "未检测到音频设备。",
                "audio_mixer": "应用音量混音器",
                "audio_no_apps": "暂无播放音频的应用。",
                "audio_pavucontrol": "音频首选项 (Pavucontrol)",
                "hypr_title": "Hyprland 实时配置项",
                "hypr_animations": "窗口动画",
                "hypr_blur": "毛玻璃模糊",
                "hypr_shadows": "窗口阴影",
                "hypr_perf": "性能配置",
                "hypr_gpu_profile": "显卡方案",
                "hypr_gpu_integrated": "核显模式",
                "hypr_gpu_igpu_only": "仅使用核显",
                "hypr_gpu_hybrid": "混合双显卡",
                "hypr_gpu_prime_auto": "PRIME 自动分配",
                "hypr_gpu_dedicated": "独显直连",
                "hypr_gpu_dgpu_only": "仅使用独显",
                "hypr_rounding": "圆角半径：",
                "hypr_gaps": "窗口间距：",
                "hypr_split": "分屏布局模式",
                "hypr_reload": "重新加载",
                "bat_ac_active": "电源适配器供电中",
                "bat_power": "实时功率",
                "bat_volt": "输出电压",
                "bat_health": "健康度",
                "bat_full": "已充饱",
                "bat_cycles": "充电循环",
                "bat_limit": "电量阈值",
                "notif_title": "系统通知",
                "notif_back": "返回",
                "notif_clear": "清除全部",
                "notif_tap_open": "点击打开应用",
                "notif_muted_apps": "静音应用",
                "notif_muted_desc": "来自已静音应用的通知将自动被忽略。",
                "notif_empty": "暂无新通知。",
                "clip_title": "剪贴板记录",
                "clip_clear": "清空记录",
                "clip_empty": "剪贴板为空：复制内容后在此查看",
                "ws_overview": "工作区概览",
                "ws_space": "空间",
                "ws_add": "新增工作区",
                "ws_footer": "Super + Tab 切换概览 • 点击切换工作区 • 󰅖 删除工作区",
                "nl_title": "夜览模式",
                "nl_back": "返回",
                "nl_temp": "屏幕色温",
                "nl_temp_desc": "数值越低偏暖黄，数值越高偏冷白。",
                "nl_gamma": "显示伽马",
                "nl_gamma_desc": "调低伽马可降低显示暗度；100% 为正常发光。",
                "nl_schedule": "定时开启",
                "nl_start": "开启时间",
                "nl_end": "关闭时间",
                "nl_disable": "关闭夜览",
                "nl_reset": "恢复默认 · 4500 K · 100%",
                "pair_title": "配对申请",
                "pair_back": "返回",
                "pair_reject": "拒绝",
                "pair_confirm": "确认配对",
                "pair_empty": "没有待处理的配对申请。",
                "ota_title": "系统升级",
                "ota_back": "返回",
                "ota_uptodate": "系统已是最新状态",
                "ota_checking": "正在检测系统更新...",
                "ota_new": "发现新系统更新",
                "ota_current": "当前安装版本",
                "ota_target": "目标升级版本",
                "ota_kernel": "Linux 内核",
                "ota_channel": "发布通道",
                "ota_changelog": "更新说明与历史日志"
        },
        "ca": {
                "nl_candle": "Espelma",
                "nl_warm": "Càlid",
                "nl_balanced": "Equilibrat",
                "nl_daylight": "Llum del dia",
                "nl_optional_off": "Opcional · Desactivat",
                "ota_last_checked": "Darrera comprovació:",
                "ota_recently": "recentment",
                "ota_behind": "enrere",
                "ota_loading_changelog": "Carregant registre de canvis...",
                "audio_active_apps": "app(s) actives",
                "bt_scanning_short": "Cercant propers...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "dispositius",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Desat",
                "bt_paired": "Vinculat",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Carregant",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Comprovar actualitzacions",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Monitor del sistema",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Nuclis CPU",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Llengua i entrada",
                "lang_subtitle": "PARÀMETRES DE TECLAT I LLENGUA",
                "lang_input_languages": "Llengües d'entrada",
                "lang_active": "Actiu",
                "lang_add_layout": "Afegir disposició de teclat",
                "lang_system_language": "Llengua del sistema",
                "lang_user_language": "Llengua d'usuari actual:",
                "lang_change_display": "Canviar llengua d'interfície",
                "lang_change_system": "Canviar llengua del sistema (localectl)",
                "lang_footer_nav": "↑/↓ Navegar • Enter Seleccionar • Esc Tancar",
                "lang_add_title": "Afegir disposició de teclat",
                "lang_search_layout": "Cercar llengua o país...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Seleccionar llengua d'interfície",
                "lang_select_system": "Seleccionar llengua del sistema (localectl)",
                "lang_search_locale": "Cercar llengua o localització...",
                "lang_select_btn": "Seleccionar",
                "tab_control": "Control",
                "tab_spaces": "Espais",
                "tab_hypr": "Hypr",
                "tab_alerts": "Alertes",
                "tab_clips": "Portapapers",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Xarxes Wi-Fi",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Connectat",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Obrir paràmetres de xarxa",
                "bt_title": "Dispositius Bluetooth",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Activar Bluetooth",
                "bt_scanning": "Cercant dispositius...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Connectat",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Control d'àudio",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Obrir paràmetres d'àudio",
                "hypr_title": "Paràmetres de Hyprland en temps real",
                "hypr_animations": "Animacions",
                "hypr_blur": "Efecte desenfocament",
                "hypr_shadows": "Ombres",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Arrodoniment",
                "hypr_gaps": "Espais entre finestres",
                "hypr_split": "Disposició dividida",
                "hypr_reload": "Recarregar",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Completament carregat",
                "bat_cycles": "Cycles",
                "bat_limit": "Límit de càrrega 80%",
                "notif_title": "Centre de notificacions",
                "notif_back": "Back",
                "notif_clear": "Netejar tot",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Sense notificacions",
                "clip_title": "Historial del portapapers",
                "clip_clear": "Netejar tot",
                "clip_empty": "El portapapers està buit",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Llum nocturna",
                "nl_back": "Back",
                "nl_temp": "Temperatura de color",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Brillantor / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Horari programat",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Petició de vinculació",
                "pair_back": "Back",
                "pair_reject": "Rebutjar",
                "pair_confirm": "Confirm",
                "pair_empty": "Sense peticions pendents.",
                "ota_title": "Actualització del sistema",
                "ota_back": "Back",
                "ota_uptodate": "El sistema està actualitzat",
                "ota_checking": "Comprovant actualitzacions...",
                "ota_new": "Nova actualització",
                "ota_current": "Versió actual",
                "ota_target": "Versió destí",
                "ota_kernel": "Kernel Linux",
                "ota_channel": "Canal de llançament",
                "ota_changelog": "Registre de canvis"
        },
        "gl": {
                "nl_candle": "Vela",
                "nl_warm": "Cálido",
                "nl_balanced": "Equilibrado",
                "nl_daylight": "Luz do día",
                "nl_optional_off": "Opcional · Desactivado",
                "ota_last_checked": "Última comprobación:",
                "ota_recently": "recentemente",
                "ota_behind": "atrás",
                "ota_loading_changelog": "Cargando rexistro de cambios...",
                "audio_active_apps": "app(s) activas",
                "bt_scanning_short": "Buscando próximos...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "dispositivos",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Gardado",
                "bt_paired": "Emparellado",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Cargando",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Comprobar actualizacións",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Monitor do sistema",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Núcleos CPU",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Lingua e entrada",
                "lang_subtitle": "AXUSTES DE TECLADO E LINGUA",
                "lang_input_languages": "Linguas de entrada",
                "lang_active": "Activo",
                "lang_add_layout": "Engadir distribución de teclado",
                "lang_system_language": "Lingua do sistema",
                "lang_user_language": "Lingua de usuario actual:",
                "lang_change_display": "Cambiar lingua da interface",
                "lang_change_system": "Cambiar lingua do sistema (localectl)",
                "lang_footer_nav": "↑/↓ Navegar • Enter Seleccionar • Esc Pechar",
                "lang_add_title": "Engadir distribución de teclado",
                "lang_search_layout": "Buscar lingua ou país...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Seleccionar lingua da interface",
                "lang_select_system": "Seleccionar lingua do sistema (localectl)",
                "lang_search_locale": "Buscar lingua ou localización...",
                "lang_select_btn": "Seleccionar",
                "tab_control": "Control",
                "tab_spaces": "Espazos",
                "tab_hypr": "Hypr",
                "tab_alerts": "Alertas",
                "tab_clips": "Portapapeis",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Redes Wi-Fi",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Conectado",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Abrir axustes de rede",
                "bt_title": "Dispositivos Bluetooth",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Activar Bluetooth",
                "bt_scanning": "Buscando dispositivos...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Conectado",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Control de son",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Abrir axustes de son",
                "hypr_title": "Axustes de Hyprland en tempo real",
                "hypr_animations": "Animacións",
                "hypr_blur": "Efecto desenfoque",
                "hypr_shadows": "Sombras",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Redondeo",
                "hypr_gaps": "Espazos entre ventás",
                "hypr_split": "Disposición dividida",
                "hypr_reload": "Recargar",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Totalmente cargado",
                "bat_cycles": "Cycles",
                "bat_limit": "Límite de carga 80%",
                "notif_title": "Centro de notificacións",
                "notif_back": "Back",
                "notif_clear": "Limpar todo",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Sen notificacións",
                "clip_title": "Historial do portapapeis",
                "clip_clear": "Limpar todo",
                "clip_empty": "O portapapeis está baleiro",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Luz nocturna",
                "nl_back": "Back",
                "nl_temp": "Temperatura de cor",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Brillo / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Horario programado",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Solicitude de emparellamento",
                "pair_back": "Back",
                "pair_reject": "Rexeitar",
                "pair_confirm": "Confirm",
                "pair_empty": "Sen solicitudes pendentes.",
                "ota_title": "Actualización do sistema",
                "ota_back": "Back",
                "ota_uptodate": "O sistema está actualizado",
                "ota_checking": "Comprobando actualizacións...",
                "ota_new": "Nova actualización",
                "ota_current": "Versión actual",
                "ota_target": "Versión destino",
                "ota_kernel": "Kernel Linux",
                "ota_channel": "Canle de lanzamento",
                "ota_changelog": "Rexistro de cambios"
        },
        "eu": {
                "nl_candle": "Kandela",
                "nl_warm": "Epela",
                "nl_balanced": "Orekatua",
                "nl_daylight": "Eguneko argia",
                "nl_optional_off": "Aukerakoa · Desaktibatuta",
                "ota_last_checked": "Azken egiaztapena:",
                "ota_recently": "berriki",
                "ota_behind": "atzean",
                "ota_loading_changelog": "Aldaketen erregistroa kargatzen...",
                "audio_active_apps": "aplikazio aktibo",
                "bt_scanning_short": "Gertukoak bilatzen...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "gailu",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Gordeta",
                "bt_paired": "Parekaturik",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Kargatzen",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Egiaztatu eguneraketak",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Sistemaren monitorea",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU nukleoak",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Hizkuntza eta sarrera",
                "lang_subtitle": "TEKLATU ETA HIZKUNTZA EZARPENAK",
                "lang_input_languages": "Sarrerako hizkuntzak",
                "lang_active": "Aktibo",
                "lang_add_layout": "Gehitu teklatu diseinua",
                "lang_system_language": "Sistemaren hizkuntza",
                "lang_user_language": "Uneko erabiltzaile hizkuntza:",
                "lang_change_display": "Aldatu bistaratze hizkuntza",
                "lang_change_system": "Aldatu sistemaren hizkuntza (localectl)",
                "lang_footer_nav": "↑/↓ Nabigatu • Enter Hautatu • Esc Itxi",
                "lang_add_title": "Gehitu teklatu diseinua",
                "lang_search_layout": "Bilatu hizkuntza edo herrialdea...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Hautatu bistaratze hizkuntza",
                "lang_select_system": "Hautatu sistemaren hizkuntza (localectl)",
                "lang_search_locale": "Bilatu hizkuntza edo eskualdea...",
                "lang_select_btn": "Hautatu",
                "tab_control": "Kontrola",
                "tab_spaces": "Guneak",
                "tab_hypr": "Hypr",
                "tab_alerts": "Alertak",
                "tab_clips": "Arbelak",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi Sareak",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Konektatuta",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Ireki sareko ezarpenak",
                "bt_title": "Bluetooth Gailuak",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Bluetooth Aktibatu",
                "bt_scanning": "Gailuak bilatzen...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Konektatuta",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Audio kontrola",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Ireki audio ezarpenak",
                "hypr_title": "Denbora errealeko Hyprland ezarpenak",
                "hypr_animations": "Animazioak",
                "hypr_blur": "Lausotze efektua",
                "hypr_shadows": "Itzalak",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Biribiltzea",
                "hypr_gaps": "Leiho arteko tartea",
                "hypr_split": "Zatitutako diseinua",
                "hypr_reload": "Birkargatu",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Guztiz kargatuta",
                "bat_cycles": "Cycles",
                "bat_limit": "Karga muga %80",
                "notif_title": "Jakinarazpen zentroa",
                "notif_back": "Back",
                "notif_clear": "Garbitu dena",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Jakinarazpenik ez",
                "clip_title": "Arbelaren historia",
                "clip_clear": "Garbitu dena",
                "clip_empty": "Arbela hutsik dago",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Gaueko argia",
                "nl_back": "Back",
                "nl_temp": "Kolore-tenperatura",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Distira / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Ordutegi programatua",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Parekatze eskaera",
                "pair_back": "Back",
                "pair_reject": "Ukatu",
                "pair_confirm": "Confirm",
                "pair_empty": "Ez dago zain dagoen eskaerarik.",
                "ota_title": "Sistemaren eguneraketa",
                "ota_back": "Back",
                "ota_uptodate": "Sistema egunean dago",
                "ota_checking": "Eguneraketak egiaztatzen...",
                "ota_new": "Eguneraketa berria",
                "ota_current": "Uneko bertsioa",
                "ota_target": "Helburu bertsioa",
                "ota_kernel": "Linux Kernel",
                "ota_channel": "Argitalpen kanala",
                "ota_changelog": "Aldaketa erregistroa"
        },
        "ko": {
                "nl_candle": "촛불",
                "nl_warm": "따뜻하게",
                "nl_balanced": "균형",
                "nl_daylight": "주광",
                "nl_optional_off": "선택사항 · 꺼짐",
                "ota_last_checked": "마지막 확인:",
                "ota_recently": "방금 전",
                "ota_behind": "버전 뒤처짐",
                "ota_loading_changelog": "변경 내역 불러오는 중...",
                "audio_active_apps": "개의 활성 앱",
                "bt_scanning_short": "주변 검색 중...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "개 기기",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "저장됨",
                "bt_paired": "페어링됨",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "충전 중",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "업데이트 확인",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "시스템 모니터",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU 코어",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "언어 및 입력",
                "lang_subtitle": "키보드 및 언어 설정",
                "lang_input_languages": "입력 언어",
                "lang_active": "활성",
                "lang_add_layout": "키보드 레이아웃 추가",
                "lang_system_language": "시스템 언어",
                "lang_user_language": "현재 사용자 언어:",
                "lang_change_display": "표시 언어 변경",
                "lang_change_system": "시스템 전역 언어 변경 (localectl)",
                "lang_footer_nav": "↑/↓ 이동 • Enter 선택 • Esc 닫기",
                "lang_add_title": "키보드 레이아웃 추가",
                "lang_search_layout": "언어 또는 국가 검색...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "표시 언어 선택",
                "lang_select_system": "시스템 언어 선택 (localectl)",
                "lang_search_locale": "언어 또는 로캘 검색...",
                "lang_select_btn": "선택",
                "tab_control": "제어",
                "tab_spaces": "공간",
                "tab_hypr": "Hypr",
                "tab_alerts": "알림",
                "tab_clips": "클립보드",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi 네트워크",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "연결됨",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "네트워크 설정 열기",
                "bt_title": "Bluetooth 기기",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Bluetooth 켜기",
                "bt_scanning": "기기 검색 중...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "연결됨",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "오디오 제어",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "오디오 설정 열기",
                "hypr_title": "실시간 Hyprland 설정",
                "hypr_animations": "애니메이션",
                "hypr_blur": "블러 효과",
                "hypr_shadows": "그림자",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "모서리 곡률",
                "hypr_gaps": "창 간격",
                "hypr_split": "분할 레이아웃",
                "hypr_reload": "새로고침",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "완충됨",
                "bat_cycles": "Cycles",
                "bat_limit": "80% 충전 제한",
                "notif_title": "알림 센터",
                "notif_back": "Back",
                "notif_clear": "모두 지우기",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "알림 없음",
                "clip_title": "클립보드 기록",
                "clip_clear": "모두 지우기",
                "clip_empty": "클립보드가 비어 있습니다",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "야간 조명",
                "nl_back": "Back",
                "nl_temp": "색온도",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "밝기 / 감마",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "예약 시간",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "페어링 요청",
                "pair_back": "Back",
                "pair_reject": "거절",
                "pair_confirm": "Confirm",
                "pair_empty": "대기 중인 페어링 요청이 없습니다.",
                "ota_title": "시스템 업데이트",
                "ota_back": "Back",
                "ota_uptodate": "최신 상태입니다",
                "ota_checking": "업데이트 확인 중...",
                "ota_new": "새 업데이트",
                "ota_current": "현재 버전",
                "ota_target": "대상 버전",
                "ota_kernel": "리눅스 커널",
                "ota_channel": "릴리스 채널",
                "ota_changelog": "변경 내역"
        },
        "pl": {
                "nl_candle": "Świeca",
                "nl_warm": "Ciepłe",
                "nl_balanced": "Zrównoważone",
                "nl_daylight": "Dzienne",
                "nl_optional_off": "Opcjonalne · Wyłączone",
                "ota_last_checked": "Ostatnio sprawdzono:",
                "ota_recently": "niedawno",
                "ota_behind": "w tyle",
                "ota_loading_changelog": "Ładowanie zmian...",
                "audio_active_apps": "aktywnych aplikacji",
                "bt_scanning_short": "Szukanie w pobliżu...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "urządzeń",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Zapisano",
                "bt_paired": "Sparowano",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Ładowanie",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Sprawdź aktualizacje",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Monitor systemu",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Rdzenie CPU",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Język i wprowadzanie",
                "lang_subtitle": "USTAWIENIA KLAWIATURY I JĘZYKA",
                "lang_input_languages": "Języki wprowadzania",
                "lang_active": "Aktywny",
                "lang_add_layout": "Dodaj układ klawiatury",
                "lang_system_language": "Język systemowy",
                "lang_user_language": "Bieżący język użytkownika:",
                "lang_change_display": "Zmień język interfejsu",
                "lang_change_system": "Zmień język systemu (localectl)",
                "lang_footer_nav": "↑/↓ Nawigacja • Enter Wybierz • Esc Zamknij",
                "lang_add_title": "Dodaj układ klawiatury",
                "lang_search_layout": "Szukaj języka lub kraju...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Wybierz język interfejsu",
                "lang_select_system": "Wybierz język systemu (localectl)",
                "lang_search_locale": "Szukaj języka lub lokalizacji...",
                "lang_select_btn": "Wybierz",
                "tab_control": "Sterowanie",
                "tab_spaces": "Obszary",
                "tab_hypr": "Hypr",
                "tab_alerts": "Powiadomienia",
                "tab_clips": "Schowek",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Sieci Wi-Fi",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Połączono",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Otwórz ustawienia sieci",
                "bt_title": "Urządzenia Bluetooth",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Włącz Bluetooth",
                "bt_scanning": "Szukanie urządzeń...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Połączono",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Dźwięk",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Ustawienia dźwięku",
                "hypr_title": "Ustawienia Hyprland",
                "hypr_animations": "Animacje",
                "hypr_blur": "Rozmycie",
                "hypr_shadows": "Cienie",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Zaokrąglenie",
                "hypr_gaps": "Odstępy okien",
                "hypr_split": "Układ podzielony",
                "hypr_reload": "Przeładuj",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Naładowano",
                "bat_cycles": "Cycles",
                "bat_limit": "Limit ładowania 80%",
                "notif_title": "Centrum powiadomień",
                "notif_back": "Back",
                "notif_clear": "Wyczyść wszystko",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Brak powiadomień",
                "clip_title": "Historia schowka",
                "clip_clear": "Wyczyść wszystko",
                "clip_empty": "Schowek jest pusty",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Nocne światło",
                "nl_back": "Back",
                "nl_temp": "Temperatura barwowa",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Jasność / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Harmonogram",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Żądanie parowania",
                "pair_back": "Back",
                "pair_reject": "Odrzuć",
                "pair_confirm": "Confirm",
                "pair_empty": "Brak oczekujących żądań.",
                "ota_title": "Aktualizacja systemu",
                "ota_back": "Back",
                "ota_uptodate": "System jest aktualny",
                "ota_checking": "Sprawdzanie aktualizacji...",
                "ota_new": "Nowa aktualizacja",
                "ota_current": "Bieżąca wersja",
                "ota_target": "Wersja docelowa",
                "ota_kernel": "Kernel Linux",
                "ota_channel": "Kanał wydań",
                "ota_changelog": "Dziennik zmian"
        },
        "no": {
                "nl_candle": "Stearinlys",
                "nl_warm": "Varm",
                "nl_balanced": "Balansert",
                "nl_daylight": "Dagslys",
                "nl_optional_off": "Valgfritt · Av",
                "ota_last_checked": "Sist sjekket:",
                "ota_recently": "nylig",
                "ota_behind": "bak",
                "ota_loading_changelog": "Laster endringslogg...",
                "audio_active_apps": "aktive apper",
                "bt_scanning_short": "Søker i nærheten...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "enheter",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Lagret",
                "bt_paired": "Paret",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Lader",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Se etter oppdateringer",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Systemovervåking",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU-kjerner",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Språk og inndata",
                "lang_subtitle": "TASTATUR- OG SPRÅKINNSTILLINGER",
                "lang_input_languages": "Inndataspråk",
                "lang_active": "Aktiv",
                "lang_add_layout": "Legg til tastaturoppsett",
                "lang_system_language": "Systemspråk",
                "lang_user_language": "Gjeldende brukerspråk:",
                "lang_change_display": "Endre visningsspråk",
                "lang_change_system": "Endre systemspråk (localectl)",
                "lang_footer_nav": "↑/↓ Naviger • Enter Velg • Esc Lukk",
                "lang_add_title": "Legg til tastaturoppsett",
                "lang_search_layout": "Søk etter språk eller land...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Velg visningsspråk",
                "lang_select_system": "Velg systemspråk (localectl)",
                "lang_search_locale": "Søk etter språk eller region...",
                "lang_select_btn": "Velg",
                "tab_control": "Kontroll",
                "tab_spaces": "Områder",
                "tab_hypr": "Hypr",
                "tab_alerts": "Varsler",
                "tab_clips": "Utklipp",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi-nettverk",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Tilkoblet",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Åpne nettverksinnstillinger",
                "bt_title": "Bluetooth-enheter",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Slå på Bluetooth",
                "bt_scanning": "Søker etter enheter...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Tilkoblet",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Lydkontroll",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Åpne lydinnstillinger",
                "hypr_title": "Sanntidsinnstillinger for Hyprland",
                "hypr_animations": "Animasjoner",
                "hypr_blur": "Uskarphetseffekt",
                "hypr_shadows": "Skygger",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Avrunding",
                "hypr_gaps": "Vindusavstand",
                "hypr_split": "Delt oppsett",
                "hypr_reload": "Last inn på nytt",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Fulladet",
                "bat_cycles": "Cycles",
                "bat_limit": "80% ladegrense",
                "notif_title": "Varslingssenter",
                "notif_back": "Back",
                "notif_clear": "Tøm alt",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Ingen varsler",
                "clip_title": "Utklippshistorikk",
                "clip_clear": "Tøm alt",
                "clip_empty": "Utklippstavlen er tom",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Nattlys",
                "nl_back": "Back",
                "nl_temp": "Fargetemperatur",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Lysstyrke / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Tidsplan",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Paringsforespørsel",
                "pair_back": "Back",
                "pair_reject": "Avslå",
                "pair_confirm": "Confirm",
                "pair_empty": "Ingen ventende forespørsler.",
                "ota_title": "Systemoppdatering",
                "ota_back": "Back",
                "ota_uptodate": "Systemet er oppdatert",
                "ota_checking": "Søker...",
                "ota_new": "Ny oppdatering",
                "ota_current": "Gjeldende versjon",
                "ota_target": "Målversjon",
                "ota_kernel": "Linux-kjerne",
                "ota_channel": "Utgivelseskanal",
                "ota_changelog": "Endringslogg"
        },
        "nb": {
                "nl_candle": "Stearinlys",
                "nl_warm": "Varm",
                "nl_balanced": "Balansert",
                "nl_daylight": "Dagslys",
                "nl_optional_off": "Valgfritt · Av",
                "ota_last_checked": "Sist sjekket:",
                "ota_recently": "nylig",
                "ota_behind": "bak",
                "ota_loading_changelog": "Laster endringslogg...",
                "audio_active_apps": "aktive apper",
                "bt_scanning_short": "Søker i nærheten...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "enheter",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Lagret",
                "bt_paired": "Paret",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Lader",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Se etter oppdateringer",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Systemovervåking",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU-kjerner",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Språk og inndata",
                "lang_subtitle": "TASTATUR- OG SPRÅKINNSTILLINGER",
                "lang_input_languages": "Inndataspråk",
                "lang_active": "Aktiv",
                "lang_add_layout": "Legg til tastaturoppsett",
                "lang_system_language": "Systemspråk",
                "lang_user_language": "Gjeldende brukerspråk:",
                "lang_change_display": "Endre visningsspråk",
                "lang_change_system": "Endre systemspråk (localectl)",
                "lang_footer_nav": "↑/↓ Naviger • Enter Velg • Esc Lukk",
                "lang_add_title": "Legg til tastaturoppsett",
                "lang_search_layout": "Søk etter språk eller land...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Velg visningsspråk",
                "lang_select_system": "Velg systemspråk (localectl)",
                "lang_search_locale": "Søk etter språk eller region...",
                "lang_select_btn": "Velg",
                "tab_control": "Kontroll",
                "tab_spaces": "Områder",
                "tab_hypr": "Hypr",
                "tab_alerts": "Varsler",
                "tab_clips": "Utklipp",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi-nettverk",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Tilkoblet",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Åpne nettverksinnstillinger",
                "bt_title": "Bluetooth-enheter",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Slå på Bluetooth",
                "bt_scanning": "Søker etter enheter...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Tilkoblet",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Lydkontroll",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Åpne lydinnstillinger",
                "hypr_title": "Sanntidsinnstillinger for Hyprland",
                "hypr_animations": "Animasjoner",
                "hypr_blur": "Uskarphetseffekt",
                "hypr_shadows": "Skygger",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Avrunding",
                "hypr_gaps": "Vindusavstand",
                "hypr_split": "Delt oppsett",
                "hypr_reload": "Last inn på nytt",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Fulladet",
                "bat_cycles": "Cycles",
                "bat_limit": "80% ladegrense",
                "notif_title": "Varslingssenter",
                "notif_back": "Back",
                "notif_clear": "Tøm alt",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Ingen varsler",
                "clip_title": "Utklippshistorikk",
                "clip_clear": "Tøm alt",
                "clip_empty": "Utklippstavlen er tom",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Nattlys",
                "nl_back": "Back",
                "nl_temp": "Fargetemperatur",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Lysstyrke / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Tidsplan",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Paringsforespørsel",
                "pair_back": "Back",
                "pair_reject": "Avslå",
                "pair_confirm": "Confirm",
                "pair_empty": "Ingen ventende forespørsler.",
                "ota_title": "Systemoppdatering",
                "ota_back": "Back",
                "ota_uptodate": "Systemet er oppdatert",
                "ota_checking": "Søker...",
                "ota_new": "Ny oppdatering",
                "ota_current": "Gjeldende versjon",
                "ota_target": "Målversjon",
                "ota_kernel": "Linux-kjerne",
                "ota_channel": "Utgivelseskanal",
                "ota_changelog": "Endringslogg"
        },
        "nn": {
                "nl_candle": "Stearinlys",
                "nl_warm": "Varm",
                "nl_balanced": "Balansert",
                "nl_daylight": "Dagslys",
                "nl_optional_off": "Valgfritt · Av",
                "ota_last_checked": "Sist sjekket:",
                "ota_recently": "nylig",
                "ota_behind": "bak",
                "ota_loading_changelog": "Laster endringslogg...",
                "audio_active_apps": "aktive apper",
                "bt_scanning_short": "Søker i nærheten...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "enheter",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Lagret",
                "bt_paired": "Paret",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Lader",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Se etter oppdateringer",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Systemovervåking",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU-kjerner",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Språk og inndata",
                "lang_subtitle": "TASTATUR- OG SPRÅKINNSTILLINGER",
                "lang_input_languages": "Inndataspråk",
                "lang_active": "Aktiv",
                "lang_add_layout": "Legg til tastaturoppsett",
                "lang_system_language": "Systemspråk",
                "lang_user_language": "Gjeldende brukerspråk:",
                "lang_change_display": "Endre visningsspråk",
                "lang_change_system": "Endre systemspråk (localectl)",
                "lang_footer_nav": "↑/↓ Naviger • Enter Velg • Esc Lukk",
                "lang_add_title": "Legg til tastaturoppsett",
                "lang_search_layout": "Søk etter språk eller land...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Velg visningsspråk",
                "lang_select_system": "Velg systemspråk (localectl)",
                "lang_search_locale": "Søk etter språk eller region...",
                "lang_select_btn": "Velg",
                "tab_control": "Kontroll",
                "tab_spaces": "Områder",
                "tab_hypr": "Hypr",
                "tab_alerts": "Varsler",
                "tab_clips": "Utklipp",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi-nettverk",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Tilkoblet",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Åpne nettverksinnstillinger",
                "bt_title": "Bluetooth-enheter",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Slå på Bluetooth",
                "bt_scanning": "Søker etter enheter...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Tilkoblet",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Lydkontroll",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Åpne lydinnstillinger",
                "hypr_title": "Sanntidsinnstillinger for Hyprland",
                "hypr_animations": "Animasjoner",
                "hypr_blur": "Uskarphetseffekt",
                "hypr_shadows": "Skygger",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Avrunding",
                "hypr_gaps": "Vindusavstand",
                "hypr_split": "Delt oppsett",
                "hypr_reload": "Last inn på nytt",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Fulladet",
                "bat_cycles": "Cycles",
                "bat_limit": "80% ladegrense",
                "notif_title": "Varslingssenter",
                "notif_back": "Back",
                "notif_clear": "Tøm alt",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Ingen varsler",
                "clip_title": "Utklippshistorikk",
                "clip_clear": "Tøm alt",
                "clip_empty": "Utklippstavlen er tom",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Nattlys",
                "nl_back": "Back",
                "nl_temp": "Fargetemperatur",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Lysstyrke / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Tidsplan",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Paringsforespørsel",
                "pair_back": "Back",
                "pair_reject": "Avslå",
                "pair_confirm": "Confirm",
                "pair_empty": "Ingen ventende forespørsler.",
                "ota_title": "Systemoppdatering",
                "ota_back": "Back",
                "ota_uptodate": "Systemet er oppdatert",
                "ota_checking": "Søker...",
                "ota_new": "Ny oppdatering",
                "ota_current": "Gjeldende versjon",
                "ota_target": "Målversjon",
                "ota_kernel": "Linux-kjerne",
                "ota_channel": "Utgivelseskanal",
                "ota_changelog": "Endringslogg"
        },
        "sv": {
                "nl_candle": "Levande ljus",
                "nl_warm": "Varmt",
                "nl_balanced": "Balanserat",
                "nl_daylight": "Dagsljus",
                "nl_optional_off": "Valfritt · Av",
                "ota_last_checked": "Senast kontrollerad:",
                "ota_recently": "nyligen",
                "ota_behind": "efter",
                "ota_loading_changelog": "Laddar ändringslogg...",
                "audio_active_apps": "aktiva appar",
                "bt_scanning_short": "Söker i närheten...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "enheter",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Sparad",
                "bt_paired": "Parkopplad",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Laddar",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Sök uppdateringar",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Systemövervakare",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU-kärnor",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Språk och inmatning",
                "lang_subtitle": "TANGENTBORDS- OCH SPRÅKINSTÄLLNINGAR",
                "lang_input_languages": "Inmatningsspråk",
                "lang_active": "Aktiv",
                "lang_add_layout": "Lägg till tangentbordslayout",
                "lang_system_language": "Systemspråk",
                "lang_user_language": "Aktuellt användarspråk:",
                "lang_change_display": "Ändra visningsspråk",
                "lang_change_system": "Ändra systemspråk (localectl)",
                "lang_footer_nav": "↑/↓ Navigera • Enter Välj • Esc Stäng",
                "lang_add_title": "Lägg till tangentbordslayout",
                "lang_search_layout": "Sök språk eller land...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Välj visningsspråk",
                "lang_select_system": "Välj systemspråk (localectl)",
                "lang_search_locale": "Sök språk eller region...",
                "lang_select_btn": "Välj",
                "tab_control": "Kontroll",
                "tab_spaces": "Ytor",
                "tab_hypr": "Hypr",
                "tab_alerts": "Aviseringar",
                "tab_clips": "Urklipp",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi-nätverk",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Ansluten",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Öppna nätverksinställningar",
                "bt_title": "Bluetooth-enheter",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Slå på Bluetooth",
                "bt_scanning": "Söker enheter...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Ansluten",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Ljudkontroll",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Öppna ljudinställningar",
                "hypr_title": "Realtidsinställningar för Hyprland",
                "hypr_animations": "Animeringar",
                "hypr_blur": "Oskärpa",
                "hypr_shadows": "Skuggor",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Hörnrundning",
                "hypr_gaps": "Fönstermellanrum",
                "hypr_split": "Delad layout",
                "hypr_reload": "Ladda om",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Fulladdat",
                "bat_cycles": "Cycles",
                "bat_limit": "Laddningsgräns 80%",
                "notif_title": "Aviseringscenter",
                "notif_back": "Back",
                "notif_clear": "Rensa allt",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Inga aviseringar",
                "clip_title": "Urklippshistorik",
                "clip_clear": "Rensa allt",
                "clip_empty": "Urklipp är tomt",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Nattljus",
                "nl_back": "Back",
                "nl_temp": "Färgtemperatur",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Ljusstyrka / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Schema",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Parkopplingsförfrågan",
                "pair_back": "Back",
                "pair_reject": "Avvisa",
                "pair_confirm": "Confirm",
                "pair_empty": "Inga väntande förfrågningar.",
                "ota_title": "Systemuppdatering",
                "ota_back": "Back",
                "ota_uptodate": "Systemet är uppdaterat",
                "ota_checking": "Söker...",
                "ota_new": "Ny uppdatering",
                "ota_current": "Aktuell version",
                "ota_target": "Målversion",
                "ota_kernel": "Linux-kärna",
                "ota_channel": "Utgivningskanal",
                "ota_changelog": "Ändringslogg"
        },
        "tr": {
                "nl_candle": "Mum Işığı",
                "nl_warm": "Sıcak",
                "nl_balanced": "Dengeli",
                "nl_daylight": "Gün Işığı",
                "nl_optional_off": "İsteğe Bağlı · Kapalı",
                "ota_last_checked": "Son denetim:",
                "ota_recently": "az önce",
                "ota_behind": "geride",
                "ota_loading_changelog": "Günlük yükleniyor...",
                "audio_active_apps": "aktif uygulama",
                "bt_scanning_short": "Yakındakiler aranıyor...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "cihaz",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Kayıtlı",
                "bt_paired": "Eşlendi",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Şarj Ediliyor",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Güncellemeleri Denetle",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Sistem İzleyici",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "İşlemci",
                "sysmon_ram": "Bellek",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "İşlemci Çekirdekleri",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Dil ve Giriş",
                "lang_subtitle": "KLAVYE VE DİL AYARLARI",
                "lang_input_languages": "Giriş Dilleri",
                "lang_active": "Etkin",
                "lang_add_layout": "Klavye düzeni ekle",
                "lang_system_language": "Sistem Dili",
                "lang_user_language": "Mevcut Kullanıcı Dili:",
                "lang_change_display": "Görüntüleme dilini değiştir",
                "lang_change_system": "Sistem genel dilini değiştir (localectl)",
                "lang_footer_nav": "↑/↓ Gezin • Enter Seç • Esc Kapat",
                "lang_add_title": "Klavye düzeni ekle",
                "lang_search_layout": "Dil veya ülke ara...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Görüntüleme Dili Seç",
                "lang_select_system": "Sistem Dili Seç (localectl)",
                "lang_search_locale": "Dil veya yerel ayar ara...",
                "lang_select_btn": "Seç",
                "tab_control": "Kontrol",
                "tab_spaces": "Alanlar",
                "tab_hypr": "Hypr",
                "tab_alerts": "Bildirimler",
                "tab_clips": "Pano",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi Ağları",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Bağlandı",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Ağ Ayarlarını Aç",
                "bt_title": "Bluetooth Cihazları",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Bluetooth Aç",
                "bt_scanning": "Cihazlar aranıyor...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Bağlandı",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Ses Kontrolü",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Ses Ayarlarını Aç",
                "hypr_title": "Gerçek Zamanlı Hyprland Ayarları",
                "hypr_animations": "Animasyonlar",
                "hypr_blur": "Bulanıklık Efekti",
                "hypr_shadows": "Gölgeler",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Köşe Yuvarlama",
                "hypr_gaps": "Pencere Boşlukları",
                "hypr_split": "Bölünmüş Düzen",
                "hypr_reload": "Yeniden Yükle",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Tam Dolu",
                "bat_cycles": "Cycles",
                "bat_limit": "%80 Şarj Sınırı",
                "notif_title": "Bildirim Merkezi",
                "notif_back": "Back",
                "notif_clear": "Tümünü Temizle",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Bildirim yok",
                "clip_title": "Pano Geçmişi",
                "clip_clear": "Tümünü Temizle",
                "clip_empty": "Pano boş",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Gece Işığı",
                "nl_back": "Back",
                "nl_temp": "Renk Sıcaklığı",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Parlaklık / Gama",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Zaman Çizelgesi",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Eşleme İsteği",
                "pair_back": "Back",
                "pair_reject": "Reddet",
                "pair_confirm": "Confirm",
                "pair_empty": "Bekleyen eşleme isteği yok.",
                "ota_title": "Sistem Güncellemesi",
                "ota_back": "Back",
                "ota_uptodate": "Sistem güncel",
                "ota_checking": "Denetleniyor...",
                "ota_new": "Yeni Güncelleme",
                "ota_current": "Mevcut Sürüm",
                "ota_target": "Hedef Sürüm",
                "ota_kernel": "Linux Çekirdeği",
                "ota_channel": "Sürüm Kanalı",
                "ota_changelog": "Değişiklik Günlüğü"
        },
        "nl": {
                "nl_candle": "Kaars",
                "nl_warm": "Warm",
                "nl_balanced": "Gebalanceerd",
                "nl_daylight": "Daglicht",
                "nl_optional_off": "Optioneel · Uit",
                "ota_last_checked": "Laatst gecontroleerd:",
                "ota_recently": "onlangs",
                "ota_behind": "achter",
                "ota_loading_changelog": "Wijzigingslogboek laden...",
                "audio_active_apps": "actieve app(s)",
                "bt_scanning_short": "In de buurt zoeken...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "apparaten",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Opgeslagen",
                "bt_paired": "Gekoppeld",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Opladen",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Controleren op updates",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Systeemmonitor",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "CPU-kernen",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Taal & Invoer",
                "lang_subtitle": "TOETSENBORD- EN TAALINSTELLINGEN",
                "lang_input_languages": "Invoertalen",
                "lang_active": "Actief",
                "lang_add_layout": "Toetsenbordindeling toevoegen",
                "lang_system_language": "Systeemtaal",
                "lang_user_language": "Huidige gebruikerstaal:",
                "lang_change_display": "Weergavetaal wijzigen",
                "lang_change_system": "Systeemtaal wijzigen (localectl)",
                "lang_footer_nav": "↑/↓ Navigeren • Enter Selecteren • Esc Sluiten",
                "lang_add_title": "Toetsenbordindeling toevoegen",
                "lang_search_layout": "Zoek taal of land...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Selecteer weergavetaal",
                "lang_select_system": "Selecteer systeemtaal (localectl)",
                "lang_search_locale": "Zoek taal of landinstelling...",
                "lang_select_btn": "Selecteren",
                "tab_control": "Bediening",
                "tab_spaces": "Ruimtes",
                "tab_hypr": "Hypr",
                "tab_alerts": "Meldingen",
                "tab_clips": "Klembord",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Wi-Fi netwerken",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Verbonden",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Netwerkinstellingen openen",
                "bt_title": "Bluetooth-apparaten",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Bluetooth inschakelen",
                "bt_scanning": "Apparaten zoeken...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Verbonden",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Geluidsbeheer",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Geluidsinstellingen openen",
                "hypr_title": "Realtime Hyprland-instellingen",
                "hypr_animations": "Animaties",
                "hypr_blur": "Vervagingseffect",
                "hypr_shadows": "Schaduwen",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Afronding",
                "hypr_gaps": "Ruimte tussen vensters",
                "hypr_split": "Gesplitste indeling",
                "hypr_reload": "Herladen",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Volledig opgeladen",
                "bat_cycles": "Cycles",
                "bat_limit": "Oplaadlimiet 80%",
                "notif_title": "Meldingscentrum",
                "notif_back": "Back",
                "notif_clear": "Alles wissen",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Geen meldingen",
                "clip_title": "Klembordgeschiedenis",
                "clip_clear": "Alles wissen",
                "clip_empty": "Klembord is leeg",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Nachtlamp",
                "nl_back": "Back",
                "nl_temp": "Kleurtemperatuur",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Helderheid / Gamma",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Tijdschema",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Koppelingsverzoek",
                "pair_back": "Back",
                "pair_reject": "Weigeren",
                "pair_confirm": "Confirm",
                "pair_empty": "Geen openstaande verzoeken.",
                "ota_title": "Systeemupdate",
                "ota_back": "Back",
                "ota_uptodate": "Systeem is up-to-date",
                "ota_checking": "Controleren...",
                "ota_new": "Nieuwe update",
                "ota_current": "Huidige versie",
                "ota_target": "Doelversie",
                "ota_kernel": "Linux-kernel",
                "ota_channel": "Releasekanaal",
                "ota_changelog": "Wijzigingslogboek"
        },
        "ar": {
                "nl_candle": "ضوء شمعة",
                "nl_warm": "دافئ",
                "nl_balanced": "متوازن",
                "nl_daylight": "ضوء النهار",
                "nl_optional_off": "اختياري · معطل",
                "ota_last_checked": "آخر فحص:",
                "ota_recently": "مؤخرًا",
                "ota_behind": "متأخر",
                "ota_loading_changelog": "جارٍ تحميل سجل التغييرات...",
                "audio_active_apps": "تطبيق نشط",
                "bt_scanning_short": "جارٍ البحث...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "أجهزة",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "محفوظ",
                "bt_paired": "مقترن",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "جارٍ الشحن",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "التحقق من التحديثات",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "مراقب النظام",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "المعالج",
                "sysmon_ram": "الذاكرة",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "أنوية المعالج",
                "sysmon_gpu": "كرت الشاشة",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "اللغة والإدخال",
                "lang_subtitle": "إعدادات لوحة المفاتيح واللغة",
                "lang_input_languages": "لغات الإدخال",
                "lang_active": "نشط",
                "lang_add_layout": "إضافة تخطيط لوحة مفاتيح",
                "lang_system_language": "لغة النظام",
                "lang_user_language": "لغة المستخدم الحالية:",
                "lang_change_display": "تغيير لغة العرض",
                "lang_change_system": "تغيير لغة النظام (localectl)",
                "lang_footer_nav": "↑/↓ تنقل • Enter اختيار • Esc إغلاق",
                "lang_add_title": "إضافة تخطيط لوحة مفاتيح",
                "lang_search_layout": "ابحث عن لغة أو بلد...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "اختر لغة العرض",
                "lang_select_system": "اختر لغة النظام (localectl)",
                "lang_search_locale": "ابحث عن لغة أو إعداد محلي...",
                "lang_select_btn": "اختيار",
                "tab_control": "التحكم",
                "tab_spaces": "المساحات",
                "tab_hypr": "Hypr",
                "tab_alerts": "التنبيهات",
                "tab_clips": "الحافظة",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "شبكات Wi-Fi",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "متصل",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "فتح إعدادات الشبكة",
                "bt_title": "أجهزة بلوتوث",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "تشغيل بلوتوث",
                "bt_scanning": "جارٍ البحث عن أجهزة...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "متصل",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "التحكم بالصوت",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "فتح إعدادات الصوت",
                "hypr_title": "إعدادات Hyprland المباشرة",
                "hypr_animations": "الرسوم المتحركة",
                "hypr_blur": "تأثير الضبابية",
                "hypr_shadows": "الظلال",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "استدارة الحواف",
                "hypr_gaps": "المسافات بين النوافذ",
                "hypr_split": "تقسيم الشاشة",
                "hypr_reload": "إعادة تحميل",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "مشحون بالكامل",
                "bat_cycles": "Cycles",
                "bat_limit": "حد الشحن 80%",
                "notif_title": "مركز الإشعارات",
                "notif_back": "Back",
                "notif_clear": "مسح الكل",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "لا توجد إشعارات",
                "clip_title": "سجل الحافظة",
                "clip_clear": "مسح الكل",
                "clip_empty": "الحافظة فارغة",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "الإضاءة الليلية",
                "nl_back": "Back",
                "nl_temp": "درجة حرارة اللون",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "السطوع / غاما",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "الجدول الزمني",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "طلب اقتران",
                "pair_back": "Back",
                "pair_reject": "رفض",
                "pair_confirm": "Confirm",
                "pair_empty": "لا توجد طلبات معلقة.",
                "ota_title": "تحديث النظام",
                "ota_back": "Back",
                "ota_uptodate": "النظام محدث",
                "ota_checking": "جارٍ التحقق...",
                "ota_new": "تحديث جديد",
                "ota_current": "الإصدار الحالي",
                "ota_target": "الإصدار المستهدف",
                "ota_kernel": "نواة لينكس",
                "ota_channel": "قناة الإصدار",
                "ota_changelog": "سجل التغييرات"
        },
        "uk": {
                "nl_candle": "Свічка",
                "nl_warm": "Тепле",
                "nl_balanced": "Збалансоване",
                "nl_daylight": "Денне світло",
                "nl_optional_off": "Опціонально · Вимкнено",
                "ota_last_checked": "Остання перевірка:",
                "ota_recently": "щойно",
                "ota_behind": "позаду",
                "ota_loading_changelog": "Завантаження змін...",
                "audio_active_apps": "активних додатків",
                "bt_scanning_short": "Пошук поруч...",
                "bt_devices_avail": "devices available",
                "bt_ready": "Ready to pair",
                "bt_hide_unnamed": "Hide",
                "bt_show_unnamed": "Show",
                "bt_unnamed_desc": "unnamed devices (beacons)",
                "bat_devices": "пристроїв",
                "sysmon_threads_active": "Threads Active",
                "sysmon_uptime": "Uptime",
                "sysmon_processor": "Processor",
                "sysmon_util": "Util",
                "mod_media_nothing": "Nothing Playing",
                "mod_wifi": "Wi-Fi",
                "mod_wifi_enabled": "Enabled",
                "mod_wifi_disabled": "Disabled",
                "mod_wifi_connected": "Connected",
                "mod_bt": "Bluetooth",
                "mod_bt_pairing": "Pairing request pending",
                "mod_bt_enabled": "Enabled",
                "mod_bt_disabled": "Disabled",
                "mod_dock": "Rust-Dock",
                "mod_dock_enabled": "Enabled · click to hide",
                "mod_dock_disabled": "Disabled · click to show",
                "mod_notif": "Notifications",
                "mod_notif_unread": "unread",
                "mod_notif_none": "No unread",
                "mod_nl": "Night Light",
                "mod_nl_inactive": "Inactive",
                "mod_caffeine_awake": "Awake Mode",
                "mod_caffeine_sleep": "Normal Sleep",
                "mod_powersave_eco": "Eco Active",
                "mod_powersave_disabled": "Disabled",
                "mod_perf": "Performance",
                "mod_perf_boost": "Max Boost",
                "mod_perf_balanced": "Balanced",
                "mod_dnd_silenced": "Silenced",
                "mod_dnd_sounds": "Sounds On",
                "mod_audio_muted": "Muted",
                "mod_record": "Record",
                "wifi_hide": "Hide",
                "wifi_show": "Show",
                "wifi_saved": "Збережено",
                "bt_paired": "З'єднано",
                "bt_available": "Available",
                "bt_unnamed_device": "Unnamed Device",
                "audio_sink_active": "Active",
                "audio_select": "Select",
                "hypr_enabled": "Enabled",
                "hypr_disabled": "Disabled",
                "hypr_max_perf": "Max Performance",
                "hypr_balanced": "Balanced",
                "hypr_power_source": "Power Source",
                "hypr_batteries": "Batteries",
                "bat_charging": "Заряджається",
                "bat_on_battery": "On battery",
                "bat_ac_online": "AC Mains Online",
                "bat_external_power": "External Power",
                "ws_active": "Active",
                "ws_empty": "Empty Space",
                "nl_enabled": "Enabled",
                "nl_disabled": "Disabled",
                "nl_active_desc": "Blue-light filter is active",
                "nl_off_desc": "Blue-light filter is off",
                "nl_schedule_hint": "Off by default. Set both times (24-hour HH:MM) to enable.",
                "nl_schedule_update": "Update schedule",
                "nl_schedule_enable": "Enable schedule",
                "pair_waiting": "Waiting",
                "pair_done": "Done",
                "pair_closed": "Closed",
                "pair_pin": "Enter the PIN",
                "pair_auth": "Authorization",
                "pair_code": "Confirmation code",
                "pair_none": "No pending pairing request.",
                "ota_available": "System Update Available",
                "ota_check": "Перевірити оновлення",
                "ota_install": "Download & Install",
                "ota_installing": "Installing...",
                "sysmon_title": "Монітор системи",
                "sysmon_cli": "htop CLI",
                "sysmon_cpu": "CPU",
                "sysmon_ram": "RAM",
                "sysmon_swap": "Swap",
                "sysmon_ssd": "SSD /",
                "sysmon_cores": "Ядра CPU",
                "sysmon_gpu": "GPU",
                "sysmon_integrated_gpu": "Standard Integrated Graphics",
                "sysmon_top_proc": "Top Processes",
                "sysmon_top_cpu": "Top CPU",
                "sysmon_top_mem": "Top Memory",
                "sysmon_pid": "PID",
                "sysmon_user": "USER",
                "sysmon_name": "NAME",
                "sysmon_kill": "KILL",
                "sysmon_kernel": "Kernel: Linux ",
                "sysmon_esc_close": "ESC or click outside to close",
                "lang_title": "Мова та введення",
                "lang_subtitle": "НАЛАШТУВАННЯ КЛАВІАТУРИ ТА МОВИ",
                "lang_input_languages": "Мови введення",
                "lang_active": "Активно",
                "lang_add_layout": "Додати розкладку клавіатури",
                "lang_system_language": "Системна мова",
                "lang_user_language": "Поточна мова користувача:",
                "lang_change_display": "Змінити мову інтерфейсу",
                "lang_change_system": "Змінити системну мову (localectl)",
                "lang_footer_nav": "↑/↓ Навігація • Enter Вибрати • Esc Закрити",
                "lang_add_title": "Додати розкладку клавіатури",
                "lang_search_layout": "Пошук мови або країни...",
                "lang_add_btn": "+ Add",
                "lang_select_display": "Вибрати мову інтерфейсу",
                "lang_select_system": "Вибрати системну мову (localectl)",
                "lang_search_locale": "Пошук мови або локалі...",
                "lang_select_btn": "Вибрати",
                "tab_control": "Керування",
                "tab_spaces": "Простори",
                "tab_hypr": "Hypr",
                "tab_alerts": "Сповіщення",
                "tab_clips": "Буфер",
                "mod_bluetooth": "Bluetooth",
                "mod_audio": "Audio Output",
                "mod_rust_dock": "Rust-Dock",
                "mod_notifications": "Notifications",
                "mod_nightlight": "Night Light",
                "mod_caffeine": "Caffeine",
                "mod_powersave": "Power Saver",
                "mod_performance": "Performance",
                "mod_dnd": "Do Not Disturb",
                "mod_volume": "Volume",
                "mod_brightness": "Brightness",
                "mod_picker": "Picker",
                "mod_gallery": "Gallery",
                "mod_random": "Random",
                "mod_tasks": "Tasks",
                "wifi_title": "Мережі Wi-Fi",
                "wifi_back": "Back",
                "wifi_connecting": "Connecting...",
                "wifi_connected": "Підключено",
                "wifi_disconnect": "Disconnect",
                "wifi_connect": "Connect",
                "wifi_known": "Known",
                "wifi_scanning": "Scanning Wi-Fi networks...",
                "wifi_none": "No Wi-Fi networks found.",
                "wifi_settings": "Налаштування мережі",
                "bt_title": "Пристрої Bluetooth",
                "bt_back": "Back",
                "bt_disabled_title": "Bluetooth is Disabled",
                "bt_disabled_desc": "Turn on Bluetooth to discover and connect nearby devices",
                "bt_turn_on": "Увімкнути Bluetooth",
                "bt_scanning": "Пошук пристроїв...",
                "bt_none_found": "No paired or named devices found. Click Scan above.",
                "bt_unnamed": "Unnamed Device",
                "bt_connected": "Підключено",
                "bt_disconnected": "Disconnected",
                "bt_pair": "Pair",
                "bt_disconnect": "Disconnect",
                "bt_connect": "Connect",
                "bt_remove": "Remove",
                "bt_manager": "Open Bluetooth Manager",
                "audio_title": "Керування звуком",
                "audio_back": "Back",
                "audio_none": "No audio output devices detected.",
                "audio_mixer": "Application Volume Mixer",
                "audio_no_apps": "No active application audio streams.",
                "audio_pavucontrol": "Налаштування звуку",
                "hypr_title": "Налаштування Hyprland у реальному часі",
                "hypr_animations": "Анімації",
                "hypr_blur": "Ефект розмиття",
                "hypr_shadows": "Тіні",
                "hypr_perf": "Performance",
                "hypr_gpu_profile": "Graphics Profile",
                "hypr_gpu_integrated": "Integrated",
                "hypr_gpu_igpu_only": "iGPU Only",
                "hypr_gpu_hybrid": "Hybrid",
                "hypr_gpu_prime_auto": "PRIME Auto",
                "hypr_gpu_dedicated": "Dedicated",
                "hypr_gpu_dgpu_only": "dGPU Only",
                "hypr_rounding": "Закруглення",
                "hypr_gaps": "Відступи вікон",
                "hypr_split": "Розділене розташування",
                "hypr_reload": "Перезавантажити",
                "bat_ac_active": "Direct Power Supply Active",
                "bat_power": "Power",
                "bat_volt": "Volt",
                "bat_health": "Health",
                "bat_full": "Повністю заряджено",
                "bat_cycles": "Cycles",
                "bat_limit": "Ліміт заряду 80%",
                "notif_title": "Центр сповіщень",
                "notif_back": "Back",
                "notif_clear": "Очистити все",
                "notif_tap_open": "Tap to open app",
                "notif_muted_apps": "Muted apps",
                "notif_muted_desc": "Notifications from muted apps are discarded before they reach the list.",
                "notif_empty": "Немає сповіщень",
                "clip_title": "Історія буфера обміну",
                "clip_clear": "Очистити все",
                "clip_empty": "Буфер обміну порожній",
                "ws_overview": "Workspaces Overview",
                "ws_space": "Space",
                "ws_add": "Add Space",
                "ws_footer": "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space",
                "nl_title": "Нічне світло",
                "nl_back": "Back",
                "nl_temp": "Колірна температура",
                "nl_temp_desc": "Lower values are warmer; higher values look more neutral.",
                "nl_gamma": "Яскравість / Гама",
                "nl_gamma_desc": "Lower gamma dims the image; 100% is normal brightness.",
                "nl_schedule": "Розклад",
                "nl_start": "Start",
                "nl_end": "End",
                "nl_disable": "Disable",
                "nl_reset": "Reset defaults · 4500 K · 100%",
                "pair_title": "Запит на з'єднання",
                "pair_back": "Back",
                "pair_reject": "Відхилити",
                "pair_confirm": "Confirm",
                "pair_empty": "Немає очікуваних запитів.",
                "ota_title": "Оновлення системи",
                "ota_back": "Back",
                "ota_uptodate": "Система оновлена",
                "ota_checking": "Перевірка оновлень...",
                "ota_new": "Нове оновлення",
                "ota_current": "Поточна версія",
                "ota_target": "Цільова версія",
                "ota_kernel": "Ядро Linux",
                "ota_channel": "Канал випусків",
                "ota_changelog": "Список змін"
        }
})

    function t(key, fallback) {
        if (!key) return fallback !== undefined ? fallback : ""
        const lang = root.currentLangCode
        if (root.i18nStrings && root.i18nStrings[lang] && root.i18nStrings[lang][key] !== undefined) {
            return root.i18nStrings[lang][key]
        }
        if (root.i18nStrings && root.i18nStrings["en"] && root.i18nStrings["en"][key] !== undefined) {
            return root.i18nStrings["en"][key]
        }
        return fallback !== undefined ? fallback : key
    }


    property var allLocalesList: []
    property var allLayoutsList: []

    FileView {
        id: allLocalesFile
        path: Quickshell.env("HOME") + "/.config/quickshell/waybar-island/all_locales.json"
        onLoaded: {
            try {
                const d = JSON.parse(allLocalesFile.text())
                if (Array.isArray(d) && d.length > 0) root.allLocalesList = d
            } catch(e) {}
        }
    }

    FileView {
        id: allLayoutsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/waybar-island/all_layouts.json"
        onLoaded: {
            try {
                const d = JSON.parse(allLayoutsFile.text())
                if (Array.isArray(d) && d.length > 0) root.allLayoutsList = d
            } catch(e) {}
        }
    }

    Process {
        id: fetchAllLocalesProc
        running: true
        command: ["bash", "-c", "$HOME/.local/bin/notch-language-helper available_locales"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (Array.isArray(d) && d.length > 0) root.allLocalesList = d
                } catch(e) {}
            }
        }
    }

    Process {
        id: fetchAllLayoutsProc
        running: true
        command: ["bash", "-c", "$HOME/.local/bin/notch-language-helper available_layouts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    if (Array.isArray(d) && d.length > 0) root.allLayoutsList = d
                } catch(e) {}
            }
        }
    }

    Process {
        id: langProc
        running: true
        command: ["bash", "-c", "$HOME/.local/bin/notch-language-helper status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    if (d && d.layouts) {
                        root.langData = d
                        if (d.active_code) root.kbLayout = d.active_code
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: langRefreshTimer
        interval: 350
        repeat: false
        onTriggered: {
            langProc.running = true
            kbProc.running = true
        }
    }

    // Sondea que monitores tienen algo a pantalla completa, para esconder la isla
    // mientras haya un video en pantalla completa. Un segundo basta: si se pierde
    // uno, la isla reaparece ese instante y se ve el parpadeo, pero con mas la
    // consulta se nota.
    Process {
        id: fullscreenProc
        command: ["bash", "-c", "$HOME/.local/bin/island-fullscreens"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim()
                if (raw.length === 0) return
                try {
                    root.fullscreenScreens = JSON.parse(raw)
                } catch (e) {
                    root.fullscreenScreens = ({})
                }
            }
        }
    }

    Timer {
        id: fullscreenTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: fullscreenProc.running = true
        triggeredOnStart: true
    }

    Process {
        id: clipCountProc
        command: ["bash", "-c", "cliphist list 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10)
                root.clipCount = isNaN(n) ? 0 : n
            }
        }
    }

    Process {
        id: muteProc
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q 'MUTED' && echo true || echo false"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.isMuted = text.trim() === "true"
            }
        }
    }

    Process {
        id: wifiListProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-wifi-helper list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false
                try {
                    root.wifiList = JSON.parse(text.trim())
                } catch(e) {
                    root.wifiList = []
                }
            }
        }
    }

    Process {
        id: wifiConnectProc
        command: [Quickshell.env("HOME") + "/.local/bin/notch-wifi-helper",
                  "connect", root.wifiConnectSsid, root.wifiConnectPassword]
        stdout: StdioCollector {
            onStreamFinished: {
                let result = null
                try { result = JSON.parse(text.trim()) } catch (e) {}
                const panel = root.panelForScreen(root.wifiConnectScreen)
                if (panel) {
                    if (result && result.status === "ok") {
                        panel.finishWifiConnection(root.wifiConnectSsid)
                    } else {
                        if (root.wifiConnectPromptOnError)
                            panel.selectedWifiSsid = root.wifiConnectSsid
                        panel.wifiConnectState = "error"
                        panel.wifiConnectMessage = result && result.message
                            ? "Connection failed: " + result.message
                            : "Connection failed. Check the password and try again."
                    }
                }
            }
        }
        onExited: {
            root.wifiConnectRunning = false
            root.wifiConnectPassword = ""
            root.wifiConnectPromptOnError = false
            wifiListProc.running = true
            wifiProc.running = true
        }
    }

    Process {
        id: wifiRescanProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-wifi-helper rescan"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanning = false
                try {
                    root.wifiList = JSON.parse(text.trim())
                } catch(e) {
                    root.wifiList = []
                }
            }
        }
    }

    Process {
        id: btStatusProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-bt-helper status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    root.btEnabled = data.powered || false
                    root.btScanning = data.discovering || false
                    root.btDevices = data.devices || []
                } catch(e) {
                    root.btDevices = []
                }
            }
        }
    }

    Timer {
        id: btPollTimer
        repeat: true
        //  El estado de bluetooth se mira SIEMPRE, no solo con la lista
        //  abierta. Antes esto solo corría con el subview de BT desplegado, así
        //  que al cerrar la isla la píldora se quedaba con el último
        //  `btDevices` que vio —congelado— mientras waybar, que va por D-Bus,
        //  seguía al día. Esa era la desincronización entre las dos barras.
        running: true
        //  Rápido donde se nota, tranquilo de fondo.
        interval: root.anyPanelSubView(2) ? 1500 : 3000
        onTriggered: {
            if (!btStatusProc.running) {
                btStatusProc.running = true
            }
        }
    }

    Timer {
        id: btDebounceSyncTimer
        interval: 350
        repeat: false
        onTriggered: {
            btStatusProc.running = true
        }
    }

    Process {
        id: audioSinksProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-audio-helper list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text.trim())
                    root.audioSinks = list
                    const active = list.find(s => s.active)
                    if (active) {
                        root.activeSinkName = active.name
                    }
                } catch(e) {
                    root.audioSinks = []
                }
            }
        }
    }

    Process {
        id: audioAppsProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-audio-helper apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.audioApps = JSON.parse(text.trim())
                } catch(e) {
                    root.audioApps = []
                }
            }
        }
    }

    Process {
        id: recStatusProc
        command: ["bash", "-c", "$HOME/.local/bin/screen-recorder-helper status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.recState = JSON.parse(text.trim())
                } catch(e) {}
            }
        }
    }

    Timer {
        id: recPollTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            recStatusProc.running = true
        }
    }

    Process {
        id: privacyStatusProc
        command: ["bash", "-c", "$HOME/.local/bin/privacy-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.privacyState = JSON.parse(text.trim())
                } catch(e) {}
            }
        }
    }

    Timer {
        id: privacyPollTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            privacyStatusProc.running = true
        }
    }

    // Aplicar el limite de carga de una bateria. battery-charge-limit escribe en el
    // charge_control_end_threshold y COMPRUEBA que el valor se quedo puesto: hay
    // controladores que lo ignoran en silencio, y sin comprobarlo la isla diria
    // que el limite esta puesto y no lo esta.
    Process {
        id: battLimitProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.battLimitMsg = text.trim()
                battLimitMsgTimer.restart()
                battProc.running = true
            }
        }
        onExited: (code) => {
            if (code !== 0 && root.battLimitMsg === "") {
                root.battLimitMsg = "Could not set the limit"
                battLimitMsgTimer.restart()
            }
        }
    }

    Timer {
        id: battLimitMsgTimer
        interval: 4000
        repeat: false
        onTriggered: root.battLimitMsg = ""
    }

    Process {
        id: battProc
        command: ["bash", "-c", "$HOME/.local/bin/battery-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.batt = JSON.parse(text.trim())
                } catch(e) {}
            }
        }
    }

    // Solo con la isla abierta: leer sysfs cada 10 s no cuesta (unos 5 ms), pero
    // tampoco tiene sentido pagarlo con la isla cerrada.
    //
    // OJO: aqui no se puede mirar islandWin. Las ventanas de la isla se crean una
    // por monitor dentro de una Repeater, asi que ese id no existe en este ambito
    // y el binding se quedaba en false para siempre: la seccion de baterias se
    // quedaba vacia para siempre y sin ningun error que lo dijera.
    Timer {
        id: battTimer
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: root.anyPanelExpanded()
        onTriggered: battProc.running = true
    }

    Process {
        id: sysStatsProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-sys-stats"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sysStats = JSON.parse(text.trim())
                } catch(e) {}
            }
        }
    }

    Process {
        id: sysMonProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-system-monitor"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    if (d && d.cpu) root.sysMonData = d
                } catch(e) {}
            }
        }
    }

    Timer {
        id: sysMonTimer
        interval: 1500
        repeat: true
        running: root.anyPanelSysMon()
        onTriggered: {
            if (!sysMonProc.running) sysMonProc.running = true
        }
    }

    function refreshWorkspacesNow() {
        if (!workspacesProc.running) workspacesProc.running = true
    }

    Process {
        id: workspacesProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-workspaces-helper refresh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(text.trim())
                    if (d && d.workspaces) {
                        root.workspacesData = d
                        root.updateWorkspacesModel(d.workspaces)
                    }
                } catch(e) {}
            }
        }
    }

    Timer {
        id: workspacesTimer
        interval: 1000
        repeat: true
        running: root.anyPanelWorkspaces()
        onTriggered: {
            if (!workspacesProc.running) workspacesProc.running = true
        }
    }

    Process {
        id: nightLightCheckProc
        command: ["bash", "-c", "$HOME/.local/bin/toggle-nightlight status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.nightLightEnabled = text.trim() === "on"
            }
        }
    }

    Process {
        id: nightLightSettingsProc
        command: [Quickshell.env("HOME") + "/.local/bin/toggle-nightlight", "settings"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const settings = JSON.parse(text.trim())
                    root.nightLightEnabled = settings.enabled === true
                    root.nightLightTemperature = Number(settings.temperature) || 4500
                    root.nightLightGamma = Number(settings.gamma) || 100
                    root.nightLightScheduleEnabled = settings.schedule_enabled === true
                    root.nightLightScheduleStart = settings.schedule_start || ""
                    root.nightLightScheduleEnd = settings.schedule_end || ""
                    Object.keys(root.islandPanels).forEach(name => {
                        const panel = root.islandPanels[name]
                        panel.nightScheduleStartText = root.nightLightScheduleStart
                        panel.nightScheduleEndText = root.nightLightScheduleEnd
                        panel.nightScheduleValidation = ""
                    })
                } catch (e) {}
            }
        }
    }

    Process {
        id: caffeineCheckProc
        command: ["bash", "-c", "$HOME/.local/bin/toggle-caffeine status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.caffeineEnabled = text.trim() === "on"
            }
        }
    }

    Process {
        id: dndCheckProc
        command: ["bash", "-c", "$HOME/.local/bin/toggle-dnd status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.dndEnabled = text.trim() === "on"
            }
        }
    }

    Timer {
        id: togglesPollTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            nightLightCheckProc.running = true
            caffeineCheckProc.running = true
            powerSaveCheckProc.running = true
            dndCheckProc.running = true
            dockStatusProc.running = true
            }
    }

    Process {
        id: dockStatusProc
        command: ["bash", "-c", "$HOME/.local/bin/rust-dock-toggle-all status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.dockEnabled = text.trim() === "on"
            }
        }
    }

    Timer {
        id: dockStatusRefreshTimer
        interval: 500
        repeat: false
        onTriggered: dockStatusProc.running = true
    }

    // Pairing request answered: keep the result visible for a moment, then let
    // the panels return to the regular control view.
    Timer {
        id: pairRequestResetTimer
        interval: 1800
        repeat: false
        onTriggered: {
            root.pairRequest = Object.assign({}, root.pairRequest, { active: false, state: "pending", pin: "" })
            Object.keys(root.islandPanels).forEach(name => {
                if (root.islandPanels[name].controlSubView === 6) root.islandPanels[name].controlSubView = 0
            })
        }
    }

    Process {
        id: powerSaveCheckProc
        command: ["bash", "-c", "$HOME/.local/bin/toggle-powersave status"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.powerSaverEnabled = text.trim() === "on"
            }
        }
    }



    Process {
        id: hyprStatusProc
        command: ["bash", "-c", "$HOME/.local/bin/notch-hypr-helper status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    root.hyprAnim = data.anim
                    root.hyprBlur = data.blur
                    root.hyprShadow = data.shadow
                    root.hyprRounding = data.rounding
                    root.hyprGaps = data.gaps
                    root.perfMode = data.perf
                } catch(e) {}
            }
        }
    }

    Timer {
        id: hyprRefreshTimer
        interval: 350
        repeat: false
        onTriggered: hyprStatusProc.running = true
    }

    Process {
        id: otaStatusProc
        command: ["bash", "-c", "$HOME/.local/bin/system-ota status --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.otaChecking = false
                try {
                    const data = JSON.parse(text.trim())
                    root.otaData = data
                } catch(e) {}
            }
        }
    }

    Process {
        id: otaCheckProc
        command: ["bash", "-c", "$HOME/.local/bin/system-ota check --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.otaChecking = false
                try {
                    const data = JSON.parse(text.trim())
                    root.otaData = data
                } catch(e) {}
            }
        }
    }

    Process {
        id: otaChangelogProc
        command: ["bash", "-c", "$HOME/.local/bin/system-ota changelog"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.otaChangelogText = text.trim()
            }
        }
    }

    Process {
        id: otaUpdateProc
        command: ["bash", "-c", "$HOME/.local/bin/system-ota update"]
        onExited: {
            root.otaUpdating = false
            otaStatusProc.running = true
        }
    }

    Process {
        id: gpuStatusProc
        running: true
        command: ["bash", "-c", "$HOME/.local/bin/gpu-profile status --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim())
                    root.gpuData = data
                } catch(e) {}
            }
        }
    }

    Timer {
        id: gpuRefreshTimer
        interval: 350
        repeat: false
        onTriggered: gpuStatusProc.running = true
    }

    Timer {
        id: statsTimer
        interval: 3000
        repeat: true
        running: root.anyPanelExpanded()
        onTriggered: {
            sysStatsProc.running = true
        }
    }

    // Barra nativa de Quickshell equivalente a Waybar (workspaces, sys-info, cava, language, status)
    property bool enableQuickshellWaybar: true

    Variants {
        id: waybarVariants
        model: Quickshell.screens

        BarraWaybar {
            required property var modelData
            screen: modelData
            islandRoot: root
        }
    }

    // Main Dynamic Island Windows (Multi-monitor support via Variants)
    Variants {
        id: islandVariants
        model: Quickshell.screens

        PanelWindow {
            id: islandWin
            required property var modelData

            property bool expanded: false
            property bool sysMonExpanded: false
            property bool langInputExpanded: false
            property string sysMonProcTab: "cpu"
            property int currentTab: 0
            property int controlSubView: 0
            property real tabFade: 1.0
            property string selectedWifiSsid: ""
            property string wifiConnectState: "idle"
            property string wifiConnectMessage: ""
            property bool wifiPasswordVisible: false
            property string nightScheduleStartText: ""
            property string nightScheduleEndText: ""
            property string nightScheduleValidation: ""
            function finishWifiConnection(ssid) {
                clearWifiPassword()
                selectedWifiSsid = ""
                wifiConnectState = "connected"
                wifiConnectMessage = "Connected to " + ssid + "."
                wifiConnectStatusTimer.restart()
            }
            function clearWifiPassword() {
                wifiPasswordVisible = false
                wifiPassInput.text = ""
            }
            Behavior on tabFade { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            Timer {
                id: wsLiveStreamTimer
                interval: 200
                repeat: false
                running: false
                onTriggered: {
                    root.refreshWorkspacesNow()
                }
            }

            Component.onCompleted: root.registerIslandPanel(modelData.name, islandWin)
            Component.onDestruction: root.unregisterIslandPanel(modelData.name)

            onCurrentTabChanged: {
                if (islandWin.controlSubView !== 4 && !(root.pairRequest.active && islandWin.currentTab === 0)) islandWin.controlSubView = 0
                if (islandWin.currentTab === 1) hyprStatusProc.running = true
                if (islandWin.currentTab === 4) workspacesProc.running = true
                islandWin.tabFade = 0.0
                tabFadeReset.restart()
            }
            onExpandedChanged: {
                if (islandWin.expanded) {
                    islandWin.sysMonExpanded = false
                    root.refreshAllStates()
                    if (islandWin.currentTab === 4) workspacesProc.running = true
                }
                else if (!root.anyPanelExpanded()) root.runCmd("$HOME/.local/bin/notch-bt-helper stop_scan")
            }
            onSysMonExpandedChanged: {
                if (islandWin.sysMonExpanded) {
                    islandWin.expanded = false
                    sysMonProc.running = true
                }
            }
            onControlSubViewChanged: {
                if (islandWin.controlSubView === 1) wifiListProc.running = true
                if (islandWin.controlSubView === 2) {
                    btStatusProc.running = true
                    if (root.btEnabled) root.runCmd("$HOME/.local/bin/notch-bt-helper scan")
                } else if (!Object.keys(root.islandPanels).some(name => root.islandPanels[name] !== islandWin && root.islandPanels[name].controlSubView === 2)) {
                    root.runCmd("$HOME/.local/bin/notch-bt-helper stop_scan")
                }
                if (islandWin.controlSubView === 3) {
                    audioSinksProc.running = true
                    audioAppsProc.running = true
                }
                if (islandWin.controlSubView === 4) {
                    otaStatusProc.running = true
                    otaChangelogProc.running = true
                }
                if (islandWin.controlSubView === 5) nightLightSettingsProc.running = true
            }

            Timer { id: tabFadeReset; interval: 40; repeat: false; onTriggered: islandWin.tabFade = 1.0 }
            Timer {
                id: nightTemperatureApplyTimer
                interval: 180
                repeat: false
                onTriggered: root.runCmd("~/.local/bin/toggle-nightlight temperature " + root.nightLightTemperature)
            }
            Timer {
                id: nightGammaApplyTimer
                interval: 180
                repeat: false
                onTriggered: root.runCmd("~/.local/bin/toggle-nightlight gamma " + root.nightLightGamma)
            }
            Timer {
                id: nightLightSettingsRefreshTimer
                interval: 500
                repeat: false
                onTriggered: nightLightSettingsProc.running = true
            }
            Timer {
                id: wifiConnectStatusTimer
                interval: 4000
                repeat: false
                onTriggered: {
                    if (islandWin.wifiConnectState === "connected") {
                        islandWin.wifiConnectState = "idle"
                        islandWin.wifiConnectMessage = ""
                    }
                }
            }
            Timer { id: hoverCollapseGrace; interval: 500; repeat: false; onTriggered: { if (islandWin.expanded && !root.notifActive && islandWin.currentTab !== 4) islandWin.expanded = false } }
            Timer { id: hoverExpandTimer; interval: 150; repeat: false; onTriggered: { if (!islandWin.expanded && !root.notifActive) { islandWin.expanded = true; if (!root.pairRequest.active) islandWin.controlSubView = 0; root.refreshAllStates() } } }

            screen: modelData
            visible: root.islandVisible && !root.hiddenScreens[modelData.name] && !root.fullscreenScreens[modelData.name]

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        implicitWidth: screen.width
        implicitHeight: screen.height
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        aboveWindows: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: islandWin.langInputExpanded ? WlrKeyboardFocus.Exclusive : ((islandWin.expanded || islandWin.sysMonExpanded) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

        mask: Region {
            item: capsule

            Region {
                item: (islandWin.expanded || islandWin.sysMonExpanded || islandWin.langInputExpanded) ? cazaClics : null
                intersection: Intersection.Combine
            }

            Region {
                item: (islandWin.sysMonExpanded || sysMonCapsule.opacity > 0) ? sysMonCapsule : null
                intersection: Intersection.Combine
            }

            Region {
                item: (islandWin.langInputExpanded || langInputPanel.opacity > 0) ? langInputPanel : null
                intersection: Intersection.Combine
            }
        }

        // Dimmer background when expanded
        Rectangle {
            id: dimmer
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
            opacity: (islandWin.expanded || islandWin.sysMonExpanded || islandWin.langInputExpanded) ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }

        // Background click catcher to close
        Item {
            id: cazaClics
            anchors.fill: parent
            enabled: islandWin.expanded || islandWin.sysMonExpanded || islandWin.langInputExpanded

            FocusScope {
                anchors.fill: parent
                focus: islandWin.expanded || islandWin.sysMonExpanded || islandWin.langInputExpanded
                Keys.onEscapePressed: {
                    islandWin.expanded = false
                    islandWin.sysMonExpanded = false
                    islandWin.langInputExpanded = false
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    islandWin.expanded = false
                    islandWin.sysMonExpanded = false
                    islandWin.langInputExpanded = false
                }
            }
        }

        // Corner Dynamic Island: Real-Time System Monitor (htop style)
        Item {
            id: sysMonCapsule
            anchors.top: parent.top
            anchors.left: parent.left
            width: islandWin.sysMonExpanded ? 600 : 200
            height: islandWin.sysMonExpanded ? 670 : 0
            clip: true

            opacity: islandWin.sysMonExpanded ? 1.0 : 0.0
            visible: opacity > 0

            Behavior on width {
                NumberAnimation {
                    duration: islandWin.sysMonExpanded ? 340 : 220
                    easing.type: islandWin.sysMonExpanded ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 1.07
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: islandWin.sysMonExpanded ? 360 : 220
                    easing.type: islandWin.sysMonExpanded ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: 1.05
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: islandWin.sysMonExpanded ? 240 : 180
                    easing.type: Easing.OutCubic
                }
            }

            // Apple Dynamic Island corner silhouette fused to top-left screen edge
            SiluetaEsquina {
                anchors.fill: parent
                ala: islandWin.sysMonExpanded ? 18 : 6
                cuerpoRadio: islandWin.sysMonExpanded ? 24 : 10
                relleno: root.colBg
                bordeColor: "transparent"
                bordeAncho: 0

                Behavior on ala {
                    NumberAnimation {
                        duration: islandWin.sysMonExpanded ? 320 : 200
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on cuerpoRadio {
                    NumberAnimation {
                        duration: islandWin.sysMonExpanded ? 320 : 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Intercept clicks inside the capsule so they do not hit cazaClics
            MouseArea {
                anchors.fill: parent
            }

            // Inner content with coordinated slide, scale, and fade choreography
            Item {
                id: sysMonContentArea
                anchors.fill: parent
                anchors.topMargin: 12
                anchors.leftMargin: 14
                anchors.rightMargin: 24
                anchors.bottomMargin: 24

                opacity: islandWin.sysMonExpanded ? 1.0 : 0.0
                transform: [
                    Translate {
                        y: islandWin.sysMonExpanded ? 0 : -22
                        Behavior on y {
                            NumberAnimation {
                                duration: islandWin.sysMonExpanded ? 320 : 180
                                easing.type: Easing.OutCubic
                            }
                        }
                    },
                    Scale {
                        origin.x: 0
                        origin.y: 0
                        xScale: islandWin.sysMonExpanded ? 1.0 : 0.94
                        yScale: islandWin.sysMonExpanded ? 1.0 : 0.94
                        Behavior on xScale {
                            NumberAnimation {
                                duration: islandWin.sysMonExpanded ? 320 : 180
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on yScale {
                            NumberAnimation {
                                duration: islandWin.sysMonExpanded ? 320 : 180
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]
                Behavior on opacity {
                    NumberAnimation {
                        duration: islandWin.sysMonExpanded ? 240 : 160
                        easing.type: Easing.OutCubic
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                // 1. Header (Icon, Title, Subtitle, htop button, Refresh, Close)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 36; height: 36; radius: 18
                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                        Text {
                            anchors.centerIn: parent
                            text: "󰻠"
                            color: root.colAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.t("sysmon_title", "System Monitor (htop)")
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: (root.sysMonData?.cpu?.model || root.t("sysmon_processor", "Processor")) + " · " + root.t("sysmon_uptime", "Uptime") + ": " + (root.sysMonData?.system?.uptime || "0m")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Boton lanzar htop en terminal
                    Rectangle {
                        height: 28
                        implicitWidth: htopRow.implicitWidth + 16
                        radius: 14
                        color: htopHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.width: 1

                        RowLayout {
                            id: htopRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "󰆍"
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                            Text {
                                text: root.t("sysmon_cli", "htop CLI")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: htopHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                islandWin.sysMonExpanded = false
                                root.runCmd("kitty -e htop")
                            }
                        }
                    }

                    // Boton Refrescar
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: sysMonRefHover.containsMouse ? root.colSurfaceHover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰑐"
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: sysMonRefHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sysMonProc.running = true
                        }
                    }

                    // Boton Cerrar
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: sysMonCloseHover.containsMouse ? Qt.rgba(224/255, 108/255, 117/255, 0.2) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: sysMonCloseHover.containsMouse ? "#e06c75" : root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: sysMonCloseHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: islandWin.sysMonExpanded = false
                        }
                    }
                }

                // 2. Cuadrícula de 4 Tarjetas de Métricas (CPU, RAM, Swap, Disk)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // CPU Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 64
                        radius: 12
                        color: root.colSurface
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "󰻠"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                                Text { text: "CPU"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (root.sysMonData?.cpu?.total_pct ?? 0) + "%"
                                    color: (root.sysMonData?.cpu?.total_pct ?? 0) > 80 ? "#e06c75" : ((root.sysMonData?.cpu?.total_pct ?? 0) > 50 ? "#e5c07b" : root.colAccent)
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysMonData?.cpu?.total_pct ?? 0) / 100.0)))
                                    radius: 2
                                    color: (root.sysMonData?.cpu?.total_pct ?? 0) > 80 ? "#e06c75" : ((root.sysMonData?.cpu?.total_pct ?? 0) > 50 ? "#e5c07b" : root.colAccent)
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }

                            Text {
                                text: ((root.sysMonData?.cpu?.freq_ghz ?? 0) > 0 ? (root.sysMonData.cpu.freq_ghz + "GHz · ") : "") + (root.sysMonData?.cpu?.temp_c ?? 0) + "°C"
                                color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; elide: Text.ElideRight
                            }
                        }
                    }

                    // RAM Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 64
                        radius: 12
                        color: root.colSurface
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "󰘚"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                                Text { text: "RAM"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (root.sysMonData?.ram?.pct ?? 0) + "%"
                                    color: (root.sysMonData?.ram?.pct ?? 0) > 85 ? "#e06c75" : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysMonData?.ram?.pct ?? 0) / 100.0)))
                                    radius: 2; color: root.colAccent
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }

                            Text {
                                text: root.sysMonData?.ram?.str || "0G / 0G"
                                color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; elide: Text.ElideRight
                            }
                        }
                    }

                    // SWAP Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 64
                        radius: 12
                        color: root.colSurface
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "󰾴"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                                Text { text: "Swap"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (root.sysMonData?.swap?.pct ?? 0) + "%"
                                    color: root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysMonData?.swap?.pct ?? 0) / 100.0)))
                                    radius: 2; color: root.colAccent
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }

                            Text {
                                text: root.sysMonData?.swap?.str || "0G / 0G"
                                color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; elide: Text.ElideRight
                            }
                        }
                    }

                    // Disk Metric Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 64
                        radius: 12
                        color: root.colSurface
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "󰋊"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                                Text { text: "SSD /"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: (root.sysMonData?.disk?.pct ?? 0) + "%"
                                    color: root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysMonData?.disk?.pct ?? 0) / 100.0)))
                                    radius: 2; color: root.colAccent
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }

                            Text {
                                text: (root.sysMonData?.disk?.used_gb ?? 0) + "G / " + (root.sysMonData?.disk?.total_gb ?? 0) + "G"
                                color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; elide: Text.ElideRight
                            }
                        }
                    }
                }

                // 3. Matriz de Núcleos CPU (Se adapta a cualquier cantidad de núcleos/hilos)
                Rectangle {
                    Layout.fillWidth: true
                    height: {
                        const count = root.sysMonData?.cpu?.cores_count ?? 16
                        const cols = count > 16 ? 6 : (count <= 4 ? 2 : 4)
                        const rows = Math.ceil(count / cols)
                        return Math.max(52, Math.min(100, 28 + rows * 13))
                    }
                    radius: 12
                    color: root.colSurface
                    border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: root.t("sysmon_cores", "CPU Cores Activity")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (root.sysMonData?.cpu?.cores_count ?? 16) + " " + root.t("sysmon_threads_active", "Threads Active")
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                            }
                        }

                        // Matriz adaptativa según cantidad de núcleos
                        GridLayout {
                            Layout.fillWidth: true
                            columns: (root.sysMonData?.cpu?.cores_count ?? 16) > 16 ? 6 : ((root.sysMonData?.cpu?.cores_count ?? 16) <= 4 ? 2 : 4)
                            rowSpacing: 3
                            columnSpacing: 8

                            Repeater {
                                model: root.sysMonData?.cpu?.cores || []
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: (modelData.id + 1).toString().padStart(2, '0')
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        Layout.preferredWidth: 14
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 5
                                        radius: 2.5
                                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)

                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: Math.max(0, Math.min(parent.width, parent.width * (modelData.pct / 100.0)))
                                            radius: 2.5
                                            color: modelData.pct > 80 ? "#e06c75" : (modelData.pct > 50 ? "#e5c07b" : root.colAccent)
                                            Behavior on width { NumberAnimation { duration: 150 } }
                                        }
                                    }

                                    Text {
                                        text: modelData.pct + "%"
                                        color: modelData.pct > 50 ? root.colFg : root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 7
                                        Layout.preferredWidth: 22
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }
                }

                // 4. Barra de GPU Dinámica (Se adapta a cualquier GPU: NVIDIA, AMD, Intel, integrada o dedicada)
                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    radius: 10
                    color: root.colSurface
                    border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text { text: "󰢮"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                        Text {
                            text: root.t("sysmon_gpu", "GPU:")
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }

                        Repeater {
                            model: root.sysMonData?.gpu?.devices || []
                            delegate: RowLayout {
                                spacing: 4
                                Rectangle {
                                    height: 22
                                    implicitWidth: gpuPillRow.implicitWidth + 14
                                    radius: 11
                                    color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                                    border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                    border.width: 1

                                    RowLayout {
                                        id: gpuPillRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Text {
                                            text: modelData.short_name || modelData.name || "GPU"
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            font.weight: Font.Bold
                                        }

                                        Text {
                                            visible: (modelData.temp_c ?? 0) > 0
                                            text: "· " + modelData.temp_c + "°C"
                                            color: (modelData.temp_c ?? 0) > 80 ? "#e06c75" : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }

                                        Text {
                                            visible: (modelData.util_pct ?? 0) > 0 || modelData.has_util
                                            text: "· " + modelData.util_pct + "% " + root.t("sysmon_util", "Util")
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }

                                        Text {
                                            visible: !!modelData.vram_str
                                            text: "· " + modelData.vram_str
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: (root.sysMonData?.gpu?.devices?.length ?? 0) === 0
                            text: root.t("sysmon_integrated_gpu", "Standard Integrated Graphics")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // 5. Procesos en Tiempo Real (htop table)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    // Cabecera de Procesos + Selector de Pestañas (CPU / RAM)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.t("sysmon_top_proc", "Top Processes")
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }

                        Item { Layout.fillWidth: true }

                        // Pill Top CPU
                        Rectangle {
                            height: 22
                            implicitWidth: 64
                            radius: 11
                            color: islandWin.sysMonProcTab === "cpu" ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: root.t("sysmon_top_cpu", "Top CPU")
                                color: islandWin.sysMonProcTab === "cpu" ? root.colBg : root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandWin.sysMonProcTab = "cpu"
                            }
                        }

                        // Pill Top Memory
                        Rectangle {
                            height: 22
                            implicitWidth: 68
                            radius: 11
                            color: islandWin.sysMonProcTab === "mem" ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: root.t("sysmon_top_mem", "Top Memory")
                                color: islandWin.sysMonProcTab === "mem" ? root.colBg : root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandWin.sysMonProcTab = "mem"
                            }
                        }
                    }

                    // Encabezados de columnas
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        Text { text: root.t("sysmon_pid", "PID"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 48 }
                        Text { text: root.t("sysmon_user", "USER"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 50 }
                        Text { text: root.t("sysmon_name", "NAME"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; Layout.fillWidth: true }
                        Text { text: "CPU"; color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight }
                        Text { text: "RAM"; color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                        Text { text: root.t("sysmon_kill", "KILL"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 28; horizontalAlignment: Text.AlignCenter }
                    }

                    // Lista de 6 Procesos
                    Repeater {
                        model: (islandWin.sysMonProcTab === "cpu" ? root.sysMonData?.procs_cpu : root.sysMonData?.procs_mem) || []
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 28
                            radius: 7
                            color: procRowHover.containsMouse ? root.colSurfaceHover : root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.04)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 8

                                // PID
                                Text {
                                    text: modelData.pid
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    Layout.preferredWidth: 48
                                }

                                // USER
                                Text {
                                    text: modelData.user || "user"
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: 50
                                }

                                // Process Name
                                Text {
                                    text: modelData.name
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                // CPU %
                                Text {
                                    text: modelData.cpu + "%"
                                    color: modelData.cpu > 25 ? "#e06c75" : (modelData.cpu > 10 ? "#e5c07b" : root.colAccent)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    Layout.preferredWidth: 42
                                    horizontalAlignment: Text.AlignRight
                                }

                                // RAM (MB/GB)
                                Text {
                                    text: modelData.mem_str || (modelData.mem + "%")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    Layout.preferredWidth: 70
                                    horizontalAlignment: Text.AlignRight
                                }

                                // Botón Kill
                                Rectangle {
                                    Layout.preferredWidth: 22
                                    height: 22
                                    radius: 11
                                    color: killBtnHover.containsMouse ? Qt.rgba(224/255, 108/255, 117/255, 0.25) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        color: killBtnHover.containsMouse ? "#e06c75" : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.3)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }

                                    MouseArea {
                                        id: killBtnHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.runCmd("kill -15 " + modelData.pid)
                                            sysMonProc.running = true
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: procRowHover
                                anchors.fill: parent
                                hoverEnabled: true
                                propagateComposedEvents: true
                            }
                        }
                    }
                }

                // 6. Pie de página (Kernel + Tip para cerrar)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: root.t("sysmon_kernel", "Kernel: Linux") + " " + (root.sysMonData?.system?.kernel || "")
                        color: root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.t("sysmon_esc_close", "ESC or click outside to close")
                        color: Qt.rgba(root.colMuted.r, root.colMuted.g, root.colMuted.b, 0.6)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                    }
                }
            }
        }
    }

        // ─────────────────────────────────────────────────────────────
        // LANGUAGE & INPUT SETTINGS PANEL (Xarishark / Omarchy Style)
        // ─────────────────────────────────────────────────────────────
        Rectangle {
            id: langInputPanel
            anchors.centerIn: parent
            width: 560
            height: Math.min(modelData.height - 80, langInputCol.implicitHeight + 44)
            radius: 16
            color: root.colBg
            border.color: root.colAccent
            border.width: 1
            clip: true

            scale: islandWin.langInputExpanded ? 1.0 : 0.94
            opacity: islandWin.langInputExpanded ? 1.0 : 0.0
            visible: opacity > 0

            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
            }
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // Intercept mouse clicks inside the panel so they don't trigger cazaClics
            MouseArea {
                anchors.fill: parent
            }

            property int subView: 0 // 0: Overview, 1: Add Layout, 2: Select Display Language
            property int localeTarget: 0 // 0: User display language, 1: System language (localectl)
            property string layoutSearch: ""
            property string localeSearch: ""

            readonly property var popularLayoutsList: [
                { code: "us", label: "English (US)" },
                { code: "es", label: "Spanish (Spain)" },
                { code: "latam", label: "Spanish (Latin America)" },
                { code: "gb", label: "English (UK)" },
                { code: "de", label: "German" },
                { code: "fr", label: "French" },
                { code: "it", label: "Italian" },
                { code: "pt", label: "Portuguese (Portugal)" },
                { code: "br", label: "Portuguese (Brazil)" },
                { code: "ru", label: "Russian" },
                { code: "jp", label: "Japanese" },
                { code: "kr", label: "Korean" },
                { code: "cn", label: "Chinese" },
                { code: "ara", label: "Arabic" },
                { code: "tr", label: "Turkish" },
                { code: "pl", label: "Polish" },
                { code: "nl", label: "Dutch" },
                { code: "se", label: "Swedish" },
                { code: "no", label: "Norwegian" },
                { code: "dk", label: "Danish" },
                { code: "fi", label: "Finnish" },
                { code: "gr", label: "Greek" },
                { code: "ua", label: "Ukrainian" },
                { code: "cz", label: "Czech" },
                { code: "ro", label: "Romanian" },
                { code: "hu", label: "Hungarian" }
            ]

            readonly property var popularLocalesList: [
                { locale: "en_US.UTF-8", label: "English (United States)" },
                { locale: "es_ES.UTF-8", label: "Español (España)" },
                { locale: "es_MX.UTF-8", label: "Español (México)" },
                { locale: "en_GB.UTF-8", label: "English (United Kingdom)" },
                { locale: "fr_FR.UTF-8", label: "Français (France)" },
                { locale: "de_DE.UTF-8", label: "Deutsch (Deutschland)" },
                { locale: "it_IT.UTF-8", label: "Italiano (Italia)" },
                { locale: "pt_BR.UTF-8", label: "Português (Brasil)" },
                { locale: "pt_PT.UTF-8", label: "Português (Portugal)" },
                { locale: "ru_RU.UTF-8", label: "Русский (Россия)" },
                { locale: "ja_JP.UTF-8", label: "日本語 (日本)" },
                { locale: "zh_CN.UTF-8", label: "中文 (简体)" },
                { locale: "C.UTF-8", label: "English (Portable Unicode)" }
            ]

            focus: true
            property int navIndex: 0
            property int pickerNavIndex: 0
            readonly property var effectiveLayoutsList: (root.allLayoutsList && root.allLayoutsList.length > 0) ? root.allLayoutsList : popularLayoutsList
            readonly property var effectiveLocalesList: (root.allLocalesList && root.allLocalesList.length > 0) ? root.allLocalesList : popularLocalesList

            readonly property var filteredLayouts: {
                let q = layoutSearch.toLowerCase().trim()
                let list = effectiveLayoutsList.filter(l => !q || (l.label && l.label.toLowerCase().includes(q)) || (l.code && l.code.toLowerCase().includes(q)))
                return list.slice(0, 80)
            }

            readonly property var filteredLocales: {
                let q = localeSearch.toLowerCase().trim()
                let list = effectiveLocalesList.filter(l => !q || (l.label && l.label.toLowerCase().includes(q)) || (l.locale && l.locale.toLowerCase().includes(q)))
                return list.slice(0, 80)
            }

            function onArrowDown() {
                if (subView === 0) {
                    const total = (root.langData.layouts ? root.langData.layouts.length : 0) + 3
                    navIndex = (navIndex + 1) % Math.max(1, total)
                } else if (subView === 1) {
                    const count = filteredLayouts.length
                    if (count > 0) pickerNavIndex = (pickerNavIndex + 1) % count
                } else if (subView === 2) {
                    const count = filteredLocales.length
                    if (count > 0) pickerNavIndex = (pickerNavIndex + 1) % count
                }
            }

            function onArrowUp() {
                if (subView === 0) {
                    const total = (root.langData.layouts ? root.langData.layouts.length : 0) + 3
                    navIndex = (navIndex - 1 + total) % Math.max(1, total)
                } else if (subView === 1) {
                    const count = filteredLayouts.length
                    if (count > 0) pickerNavIndex = (pickerNavIndex - 1 + count) % count
                } else if (subView === 2) {
                    const count = filteredLocales.length
                    if (count > 0) pickerNavIndex = (pickerNavIndex - 1 + count) % count
                }
            }

            function onEnter() {
                if (subView === 0) {
                    const layouts = root.langData.layouts || []
                    if (navIndex < layouts.length) {
                        root.runCmd("$HOME/.local/bin/notch-language-helper switch " + layouts[navIndex].id)
                        langRefreshTimer.restart()
                    } else if (navIndex === layouts.length) {
                        subView = 1
                        layoutSearch = ""
                        pickerNavIndex = 0
                        layoutSearchInput.forceActiveFocus()
                    } else if (navIndex === layouts.length + 1) {
                        localeTarget = 0
                        subView = 2
                        localeSearch = ""
                        pickerNavIndex = 0
                        localeSearchInput.forceActiveFocus()
                    } else if (navIndex === layouts.length + 2) {
                        localeTarget = 1
                        subView = 2
                        localeSearch = ""
                        pickerNavIndex = 0
                        localeSearchInput.forceActiveFocus()
                    }
                } else if (subView === 1) {
                    if (filteredLayouts.length > 0 && pickerNavIndex >= 0 && pickerNavIndex < filteredLayouts.length) {
                        const item = filteredLayouts[pickerNavIndex]
                        root.runCmd("$HOME/.local/bin/notch-language-helper add " + item.code)
                        subView = 0
                        langRefreshTimer.restart()
                        forceActiveFocus()
                    }
                } else if (subView === 2) {
                    if (filteredLocales.length > 0 && pickerNavIndex >= 0 && pickerNavIndex < filteredLocales.length) {
                        const item = filteredLocales[pickerNavIndex]
                        if (localeTarget === 1) {
                            root.runCmd("$HOME/.local/bin/notch-language-helper set_system_locale '" + item.locale + "'")
                        } else {
                            root.runCmd("$HOME/.local/bin/notch-language-helper set_user_locale '" + item.locale + "'")
                        }
                        subView = 0
                        langRefreshTimer.restart()
                        forceActiveFocus()
                    }
                }
            }

            Keys.onDownPressed: event => { onArrowDown(); event.accepted = true; }
            Keys.onUpPressed: event => { onArrowUp(); event.accepted = true; }
            Keys.onReturnPressed: event => { onEnter(); event.accepted = true; }
            Keys.onEnterPressed: event => { onEnter(); event.accepted = true; }
            Keys.onEscapePressed: event => {
                if (subView !== 0) {
                    subView = 0
                    forceActiveFocus()
                } else {
                    islandWin.langInputExpanded = false
                }
                event.accepted = true
            }



            Connections {
                target: islandWin
                function onLangInputExpandedChanged() {
                    if (islandWin.langInputExpanded) {
                        langInputPanel.navIndex = 0
                        langInputPanel.pickerNavIndex = 0
                        langInputPanel.subView = 0
                        langInputPanel.forceActiveFocus()
                        if (!root.allLocalesList || root.allLocalesList.length === 0) {
                            try {
                                const d = JSON.parse(allLocalesFile.text())
                                if (Array.isArray(d) && d.length > 0) root.allLocalesList = d
                            } catch(e) {}
                            fetchAllLocalesProc.running = true
                        }
                        if (!root.allLayoutsList || root.allLayoutsList.length === 0) {
                            try {
                                const d = JSON.parse(allLayoutsFile.text())
                                if (Array.isArray(d) && d.length > 0) root.allLayoutsList = d
                            } catch(e) {}
                            fetchAllLayoutsProc.running = true
                        }
                    }
                }
            }

            ColumnLayout {
                id: langInputCol
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12

                // ── SUBVIEW 0: MAIN LANGUAGE & INPUT VIEW ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: langInputPanel.subView === 0

                    // 1. Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "󰗊"
                            color: root.colAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 22
                        }

                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: root.t("lang_title_main", "Language & Input")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            Text {
                                text: root.t("lang_title", "DISPLAY LANGUAGE AND KEYBOARDS")
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.Medium
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: closeLangHover.containsMouse ? Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.15) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: closeLangHover.containsMouse ? "#ff5555" : root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: closeLangHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandWin.langInputExpanded = false
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                    }

                    // 2. DISPLAY LANGUAGE SECTION
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: root.t("lang_display_language_section", "Display Language (Interfaz)")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "328 /etc/locale.gen"
                            color: root.colAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }

                    // Current Active Language Display Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        radius: 8
                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                        border.color: root.colAccent
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Text {
                                text: "󰗊"
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 15
                            }

                            ColumnLayout {
                                spacing: 1
                                Layout.fillWidth: true
                                Text {
                                    text: root.langData.user_locale_label || root.langData.user_locale || "Español (España) - es_ES.UTF-8"
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: (root.langData.user_locale || "es_ES.UTF-8")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }
                            }

                            Rectangle {
                                height: 18
                                implicitWidth: 54
                                radius: 9
                                color: root.colAccent
                                Text {
                                    anchors.centerIn: parent
                                    text: root.t("lang_active", "Activo")
                                    color: root.colBg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }
                        }
                    }

                    // Quick Language Chips Grid (Top 10 languages for instant 1-click switching)
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: [
                                { locale: "es_ES.UTF-8", code: "es", label: "Español", flag: "🇪🇸" },
                                { locale: "en_US.UTF-8", code: "en", label: "English", flag: "🇬🇧" },
                                { locale: "fr_FR.UTF-8", code: "fr", label: "Français", flag: "🇫🇷" },
                                { locale: "de_DE.UTF-8", code: "de", label: "Deutsch", flag: "🇩🇪" },
                                { locale: "it_IT.UTF-8", code: "it", label: "Italiano", flag: "🇮🇹" },
                                { locale: "pt_PT.UTF-8", code: "pt", label: "Português", flag: "🇵🇹" },
                                { locale: "ru_RU.UTF-8", code: "ru", label: "Русский", flag: "🇷🇺" },
                                { locale: "ja_JP.UTF-8", code: "ja", label: "日本語", flag: "🇯🇵" },
                                { locale: "zh_CN.UTF-8", code: "zh", label: "中文", flag: "🇨🇳" },
                                { locale: "ko_KR.UTF-8", code: "ko", label: "한국어", flag: "🇰🇷" }
                            ]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 30
                                radius: 6
                                readonly property bool isCurrent: {
                                    let cur = (root.langData?.user_locale || "").toLowerCase()
                                    return cur.startsWith(modelData.code) || cur === modelData.locale.toLowerCase()
                                }
                                color: isCurrent ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.25) : (chipHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05))
                                border.color: isCurrent ? root.colAccent : "transparent"
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: modelData.flag
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: modelData.label
                                        color: isCurrent ? root.colAccent : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        font.weight: isCurrent ? Font.Bold : Font.Normal
                                    }
                                }

                                MouseArea {
                                    id: chipHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runCmd("$HOME/.local/bin/notch-language-helper set_user_locale '" + modelData.locale + "'")
                                        langRefreshTimer.restart()
                                    }
                                }
                            }
                        }
                    }

                    // Button to explore all 328 locales
                    Rectangle {
                        id: chgDisplayBtn
                        Layout.fillWidth: true
                        height: 34
                        radius: 8
                        color: chgLangHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            Text {
                                text: "󰗊"
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }
                            Text {
                                text: root.t("lang_change_display", "Ver todos los idiomas de /etc/locale.gen (328 disponibles)")
                                color: chgLangHover.containsMouse ? root.colAccent : root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "󰁔"
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: chgLangHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                langInputPanel.localeTarget = 0
                                langInputPanel.subView = 2
                                langInputPanel.localeSearch = ""
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                    }

                    // 3. KEYBOARD LAYOUTS SECTION
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: root.t("lang_input_languages", "Distribución de teclado")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            Layout.fillWidth: true
                        }
                        Text {
                            text: (root.langData.current_hotkey ? "Atajo: " + root.langData.current_hotkey : "Win + K")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.langData.layouts || []
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 36
                                radius: 8
                                color: modelData.active ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15) : (rowHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.04))
                                border.color: modelData.active ? root.colAccent : "transparent"
                                border.width: 1

                                MouseArea {
                                    id: rowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runCmd("$HOME/.local/bin/notch-language-helper switch " + modelData.id)
                                        langRefreshTimer.restart()
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: (index + 1) + "."
                                        color: modelData.active ? root.colAccent : root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }

                                    Text {
                                        text: modelData.label || modelData.code
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: modelData.active ? Font.Bold : Font.Normal
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        visible: modelData.active
                                        height: 18
                                        implicitWidth: 50
                                        radius: 9
                                        color: root.colAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.t("lang_active", "Activo")
                                            color: root.colBg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Rectangle {
                                        visible: (root.langData.layouts?.length || 1) > 1
                                        width: 22; height: 22; radius: 11
                                        color: delHover.containsMouse ? "#ff5555" : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: delHover.containsMouse ? "#ffffff" : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: delHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.runCmd("$HOME/.local/bin/notch-language-helper remove " + modelData.code)
                                                langRefreshTimer.restart()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: addLayoutBtn
                            Layout.fillWidth: true
                            height: 32
                            radius: 8
                            color: addLayoutHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8
                                Text {
                                    text: "󰐕"
                                    color: root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: root.t("lang_add_layout", "Añadir distribución de teclado (99 disponibles)")
                                    color: addLayoutHover.containsMouse ? root.colAccent : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "󰁔"
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: addLayoutHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    langInputPanel.subView = 1
                                    langInputPanel.layoutSearch = ""
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                    }

                    // Secondary action: System language (localectl)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: root.t("lang_change_system", "Idioma global de Linux (localectl):")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                        Text {
                            text: root.langData.system_locale_label || root.langData.system_locale || "es_ES.UTF-8"
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "Cambiar 󰁔"
                            color: sysChgHover.containsMouse ? root.colAccent : root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            MouseArea {
                                id: sysChgHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    langInputPanel.localeTarget = 1
                                    langInputPanel.subView = 2
                                    langInputPanel.localeSearch = ""
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                    }

                    // Footer Shortcuts
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.t("lang_footer_nav", "↑/↓ Navegar • Enter Seleccionar • Esc Cerrar")
                        color: root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }

                // ── SUBVIEW 1: ADD KEYBOARD LAYOUT PICKER ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: langInputPanel.subView === 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: backLayoutHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "󰁍"
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: backLayoutHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: langInputPanel.subView = 0
                            }
                        }

                        Text {
                            text: root.t("lang_add_title", "Add Keyboard Layout")
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            Layout.fillWidth: true
                        }
                    }

                    // Search input box
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 8
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.06)
                        border.color: layoutSearchInput.activeFocus ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.15)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "󰍉"
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }

                            TextInput {
                                id: layoutSearchInput
                                Layout.fillWidth: true
                                text: langInputPanel.layoutSearch
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                clip: true
                                onTextChanged: {
                                    langInputPanel.layoutSearch = text
                                    langInputPanel.pickerNavIndex = 0
                                }
                                Keys.onDownPressed: event => { langInputPanel.onArrowDown(); event.accepted = true; }
                                Keys.onUpPressed: event => { langInputPanel.onArrowUp(); event.accepted = true; }
                                Keys.onReturnPressed: event => { langInputPanel.onEnter(); event.accepted = true; }
                                Keys.onEnterPressed: event => { langInputPanel.onEnter(); event.accepted = true; }
                                Keys.onEscapePressed: event => {
                                    langInputPanel.subView = 0
                                    langInputPanel.forceActiveFocus()
                                    event.accepted = true
                                }

                                Text {
                                    visible: !layoutSearchInput.text && !layoutSearchInput.activeFocus
                                    text: root.t("lang_search_layout", "Search language or country...")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    // Layouts List
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 300
                        contentHeight: layoutsCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: layoutsCol
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: langInputPanel.filteredLayouts
                                delegate: Rectangle {
                                    readonly property bool isNavFocus: (langInputPanel.subView === 1 && langInputPanel.pickerNavIndex === index)
                                    Layout.fillWidth: true
                                    height: 36
                                    radius: 6
                                    color: isNavFocus ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.22) : (pickLayoutHover.containsMouse ? root.colSurfaceHover : "transparent")
                                    border.color: isNavFocus ? root.colAccent : "transparent"
                                    border.width: isNavFocus ? 2 : 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: modelData.flag ? modelData.flag : "⌨️"
                                            font.pixelSize: 13
                                        }

                                        Rectangle {
                                            height: 20
                                            implicitWidth: 40
                                            radius: 4
                                            color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2)
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.code.toUpperCase()
                                                color: root.colAccent
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }
                                        }

                                        Text {
                                            text: modelData.label
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: root.t("lang_add_btn", "+ Add")
                                            color: pickLayoutHover.containsMouse ? root.colAccent : "transparent"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }

                                    MouseArea {
                                        id: pickLayoutHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.runCmd("$HOME/.local/bin/notch-language-helper add " + modelData.code)
                                            langInputPanel.subView = 0
                                            langRefreshTimer.restart()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── SUBVIEW 2: CHANGE DISPLAY LANGUAGE PICKER ──
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: langInputPanel.subView === 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: backLocaleHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            Text {
                                anchors.centerIn: parent
                                text: "󰁍"
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: backLocaleHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: langInputPanel.subView = 0
                            }
                        }

                        Text {
                            text: langInputPanel.localeTarget === 1 ? root.t("lang_select_system", "Select System Language (localectl)") : root.t("lang_select_display", "Select Display Language")
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            Layout.fillWidth: true
                        }
                    }

                    // Search input box
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 8
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.06)
                        border.color: localeSearchInput.activeFocus ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.15)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "󰍉"
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }

                            TextInput {
                                id: localeSearchInput
                                Layout.fillWidth: true
                                text: langInputPanel.localeSearch
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                clip: true
                                onTextChanged: {
                                    langInputPanel.localeSearch = text
                                    langInputPanel.pickerNavIndex = 0
                                }
                                Keys.onDownPressed: event => { langInputPanel.onArrowDown(); event.accepted = true; }
                                Keys.onUpPressed: event => { langInputPanel.onArrowUp(); event.accepted = true; }
                                Keys.onReturnPressed: event => { langInputPanel.onEnter(); event.accepted = true; }
                                Keys.onEnterPressed: event => { langInputPanel.onEnter(); event.accepted = true; }
                                Keys.onEscapePressed: event => {
                                    langInputPanel.subView = 0
                                    langInputPanel.forceActiveFocus()
                                    event.accepted = true
                                }

                                Text {
                                    visible: !localeSearchInput.text && !localeSearchInput.activeFocus
                                    text: root.t("lang_search_locale", "Search language or locale...")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    // Locales List
                    Flickable {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 300
                        contentHeight: localesCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: localesCol
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: langInputPanel.filteredLocales
                                delegate: Rectangle {
                                    readonly property bool isNavFocus: (langInputPanel.subView === 2 && langInputPanel.pickerNavIndex === index)
                                    Layout.fillWidth: true
                                    height: 38
                                    radius: 6
                                    color: isNavFocus ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.22) : (pickLocaleHover.containsMouse ? root.colSurfaceHover : "transparent")
                                    border.color: isNavFocus ? root.colAccent : "transparent"
                                    border.width: isNavFocus ? 2 : 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 8

                                        Text {
                                            text: modelData.flag ? modelData.flag : "󰗊"
                                            color: root.colAccent
                                            font.pixelSize: 13
                                        }

                                        ColumnLayout {
                                            spacing: 1
                                            Layout.fillWidth: true
                                            Text {
                                                text: modelData.label
                                                color: root.colFg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                            }
                                            Text {
                                                text: modelData.locale
                                                color: root.colMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 9
                                            }
                                        }

                                        Text {
                                            text: root.t("lang_select_btn", "Select")
                                            color: pickLocaleHover.containsMouse ? root.colAccent : "transparent"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }

                                    MouseArea {
                                        id: pickLocaleHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (langInputPanel.localeTarget === 1) {
                                                root.runCmd("$HOME/.local/bin/notch-language-helper set_system_locale '" + modelData.locale + "'")
                                            } else {
                                                root.runCmd("$HOME/.local/bin/notch-language-helper set_user_locale '" + modelData.locale + "'")
                                            }
                                            langInputPanel.subView = 0
                                            langRefreshTimer.restart()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Dynamic Island container fused to top screen edge (Mac notch style)
        Item {
            id: capsule
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 1.0

            HoverHandler {
                id: islandHover
                onHoveredChanged: {
                    if (islandHover.hovered) {
                        hoverCollapseGrace.stop()
                    } else if (islandWin.expanded && !root.notifActive && islandWin.currentTab !== 4) {
                        hoverCollapseGrace.restart()
                    }
                }
            }


            readonly property real ala: 16
            width: islandWin.expanded ? (islandWin.currentTab === 4 ? Math.min(modelData.width - 60, Math.max(780, ((root.workspacesData?.workspaces?.length || 2) * 268) + 210)) : 660) : (root.notifActive ? 460 : (collapsedContent.width + capsule.ala * 2 + 36))
            height: islandWin.expanded ? (islandWin.currentTab === 4 ? Math.min(480, islandContentCol.implicitHeight + 64) : Math.min(800, islandContentCol.implicitHeight + 52)) : (root.notifActive ? 56 : 36)

            Behavior on width {
                NumberAnimation {
                    id: capsuleWidthAnim
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                NumberAnimation {
                    id: capsuleHeightAnim
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            // Silueta con esquinas invertidas (alas) que funden con el borde superior de la pantalla
            SiluetaIsla {
                id: silueta
                anchors.fill: parent
                ala: capsule.ala
                cuerpoRadio: islandWin.expanded ? 24 : (root.notifActive ? 16 : 12)
                relleno: root.colBg
                lado: "arriba"

                Behavior on cuerpoRadio {
                    NumberAnimation { duration: 200 }
                }
            }

            // Area de contenido (dentro del cuerpo de la isla, entre las alas)
            Item {
                id: contentArea
                anchors.fill: parent
                anchors.leftMargin: capsule.ala
                anchors.rightMargin: capsule.ala
                clip: true

            // ─────────────────────────────────────────────────────────────
            // COLLAPSED VIEW (Waybar-style integrated clock / media pill)
            // ─────────────────────────────────────────────────────────────
            Item {
                id: collapsedView
                anchors.fill: parent
                visible: opacity > 0
                opacity: (!islandWin.expanded && !root.notifActive) ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: hoverExpandTimer.restart()
                    onExited: hoverExpandTimer.stop()
                    onClicked: {
                        hoverExpandTimer.stop()
                        islandWin.expanded = !islandWin.expanded
                        if (islandWin.expanded) {
                            islandWin.controlSubView = 0
                            root.refreshAllStates()
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: parent.containsMouse ? root.colSurfaceHover : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }

                Row {
                    id: collapsedContent
                    anchors.centerIn: parent
                    spacing: 8

                    // Media indicator if playing
                    Row {
                        visible: root.isPlaying && root.activePlayerTitle !== ""
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "󰝚"
                            color: root.colAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.activePlayerTitle.length > 14 
                                ? root.activePlayerTitle.substring(0, 13) + "…" 
                                : root.activePlayerTitle
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 1
                            height: 12
                            color: root.colMuted
                            opacity: 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Privacy indicator in collapsed pill (mic green, camera orange)
                    Row {
                        visible: root.privacyState.mic || root.privacyState.cam
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: root.privacyState.cam ? "#FFA726" : "#66BB6A"
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                running: root.privacyState.mic || root.privacyState.cam
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }

                        Text {
                            text: root.privacyState.cam ? "󰄀" : "󰍬"
                            color: root.privacyState.cam ? "#FFA726" : "#66BB6A"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 1
                            height: 12
                            color: root.colMuted
                            opacity: 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Recording indicator in collapsed pill
                    Row {
                        visible: root.recState.recording
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#EF5350"
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                running: root.recState.recording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 500 }
                                NumberAnimation { to: 1.0; duration: 500 }
                            }
                        }

                        Text {
                            text: "REC " + (root.recState.elapsed_str || "00:00")
                            color: "#EF5350"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 1
                            height: 12
                            color: root.colMuted
                            opacity: 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // DND indicator in collapsed pill
                    Row {
                        visible: root.dndEnabled
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#E57373"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "󰂛"
                            color: "#E57373"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 1
                            height: 12
                            color: root.colMuted
                            opacity: 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Night Light indicator in collapsed pill
                    Row {
                        visible: root.nightLightEnabled
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#FFCA28"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "󰖔"
                            color: "#FFCA28"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 1
                            height: 12
                            color: root.colMuted
                            opacity: 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Caffeine indicator in collapsed pill
                    Row {
                        visible: root.caffeineEnabled
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: "#D9A05B"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "󰅶"
                            color: "#D9A05B"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 1
                            height: 12
                            color: root.colMuted
                            opacity: 0.4
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Clock (exact Waybar format: 17:04:12  -  Sábado, 26)
                    Text {
                        text: root.clockStr
                        color: root.colAccent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Unread notifications badge (adaptive count)
                    // El contador de notificaciones va dentro de un MouseArea y no al
                    // reves por una razon concreta: antes el MouseArea era un hijo mas
                    // del Row, con anchors.fill: parent, y dentro de un Row eso no
                    // existe. Quickshell lo avisa —
                    //
                    //   Cannot specify left, right, horizontalCenter, fill or centerIn
                    //   anchors for items inside Row. Row will not function.
                    //
                    // — y el area pulsable se quedaba en cero: el contador se veia pero
                    // no se podia pulsar. En un Row el tamano de un hijo sale de
                    // implicitWidth e implicitHeight, nunca de un anclaje.
                    MouseArea {
                        visible: root.notifUnread > 0 && !islandWin.expanded && !root.notifActive
                        implicitWidth: badgeNotif.implicitWidth
                        implicitHeight: badgeNotif.implicitHeight
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.notifOpenCenter(islandWin.modelData.name)

                        Row {
                            id: badgeNotif
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: "󰂚"
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                height: 16
                                width: Math.max(16, notifCountLbl.implicitWidth + 10)
                                radius: 8
                                color: root.colAccent
                                Text {
                                    id: notifCountLbl
                                    anchors.centerIn: parent
                                    text: root.notifUnread > 9 ? "9+" : root.notifUnread
                                    color: root.colBg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: 1
                                height: 12
                                color: root.colMuted
                                opacity: 0.4
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }


                    // Indicator icon
                    Text {
                        text: islandWin.expanded ? "󰅃" : "󰅀"
                        color: root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        opacity: 0.6
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ─────────────────────────────────────────────────────────────
            // NOTIFICATION BANNER VIEW (Dynamic Island Banner)
            // ─────────────────────────────────────────────────────────────
            Item {
                id: notifView
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                visible: opacity > 0
                opacity: (!islandWin.expanded && root.notifActive) ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.notifOpenCenter(islandWin.modelData.name)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.topMargin: 2
                    anchors.bottomMargin: 4
                    spacing: 10

                    // Notification Icon Bubble
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2)
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰂚"
                            color: root.colAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                        }
                    }

                    // Content Details
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: root.notifAppName.toUpperCase()
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "ahora"
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }

                        Text {
                            text: root.notifSummary || "Notificación"
                            color: root.colFg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: root.notifBody !== ""
                            text: root.notifBody
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.fillWidth: true
                        }
                    }

                    // Dismiss X icon
                    Text {
                        text: "󰅖"
                        color: root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        opacity: 0.7
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            // ─────────────────────────────────────────────────────────────
            // EXPANDED VIEW (Dynamic Island Control Center)
            // ─────────────────────────────────────────────────────────────
            Item {
                id: expandedView
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.topMargin: 32
                anchors.bottomMargin: 20
                visible: opacity > 0
                opacity: islandWin.expanded ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    id: islandContentCol
                    anchors.fill: parent
                    spacing: 14

                    // ── 1. HEADER ROW (Date, Time, Notch grabber, Close/Lock/Power) ──
                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            spacing: 1
                            Layout.preferredWidth: 150
                            Text {
                                text: root.dateStr
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Text {
                                text: root.timeStr
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Notch close indicator / grabber
                        Rectangle {
                            width: 36
                            height: 4
                            radius: 2
                            color: root.colMuted
                            opacity: 0.5
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Item { Layout.fillWidth: true }

                        // Session & Close buttons
                        RowLayout {
                            spacing: 6
                            Layout.preferredWidth: 150
                            Layout.alignment: Qt.AlignRight

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.colSurface
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰌾"
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { islandWin.expanded = false; root.runCmd("hyprlock"); }
                                }
                            }

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.colSurface
                                Text {
                                    anchors.centerIn: parent
                                    text: "⏻"
                                    color: "#ff5555"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { islandWin.expanded = false; root.runCmd("~/.local/bin/powermenu-with-monitor-detection"); }
                                }
                            }

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.colSurface
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandWin.expanded = false
                                }
                            }
                        }
                    }

                    // ── 2. SEGMENTED TABS (CONTROL, HYPRLAND & ALERTS) ──
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        spacing: 8
                        visible: islandWin.controlSubView === 0

                        // Tab 0: Control & Sistema
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 17
                            color: islandWin.currentTab === 0 ? root.colAccent : root.colSurface
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰒓"
                                    color: islandWin.currentTab === 0 ? root.colBg : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: root.t("tab_control", "Control")
                                    color: islandWin.currentTab === 0 ? root.colBg : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandWin.currentTab = 0
                                    islandWin.controlSubView = 0
                                }
                            }
                        }

                        // Tab 4: Workspaces Overview (Super + Tab)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 17
                            color: islandWin.currentTab === 4 ? root.colAccent : root.colSurface
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰍹"
                                    color: islandWin.currentTab === 4 ? root.colBg : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: root.t("tab_spaces", "Spaces")
                                    color: islandWin.currentTab === 4 ? root.colBg : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandWin.currentTab = 4
                                    islandWin.controlSubView = 0
                                    workspacesProc.running = true
                                }
                            }
                        }

                        // Tab 1: Hyprland Settings
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 17
                            color: islandWin.currentTab === 1 ? root.colAccent : root.colSurface
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰣇"
                                    color: islandWin.currentTab === 1 ? root.colBg : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: root.t("tab_hypr", "Hypr")
                                    color: islandWin.currentTab === 1 ? root.colBg : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandWin.currentTab = 1
                                    islandWin.controlSubView = 0
                                }
                            }
                        }

                        // Tab 2: Alerts
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 17
                            color: islandWin.currentTab === 2 ? root.colAccent : root.colSurface
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰂚"
                                    color: islandWin.currentTab === 2 ? root.colBg : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: root.t("tab_alerts", "Alerts")
                                    color: islandWin.currentTab === 2 ? root.colBg : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                                Rectangle {
                                    visible: root.notifUnread > 0
                                    height: 16
                                    width: Math.max(16, tabPillCount.implicitWidth + 8)
                                    radius: 8
                                    color: islandWin.currentTab === 2 ? root.colBg : root.colAccent
                                    Text {
                                        id: tabPillCount
                                        anchors.centerIn: parent
                                        text: root.notifUnread > 9 ? "9+" : root.notifUnread
                                        color: islandWin.currentTab === 2 ? root.colAccent : root.colBg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandWin.currentTab = 2
                                    islandWin.controlSubView = 0
                                    root.notifUnread = 0
                                }
                            }
                        }

                        // Tab 3: Portapapeles (opcion aparte de Alertas, arriba)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 17
                            color: islandWin.currentTab === 3 ? root.colAccent : root.colSurface
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: "󰅍"
                                    color: islandWin.currentTab === 3 ? root.colBg : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                }
                                Text {
                                    text: root.t("tab_clips", "Clips")
                                    color: islandWin.currentTab === 3 ? root.colBg : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandWin.currentTab = 3
                                    islandWin.controlSubView = 0
                                    clipListProc.running = true
                                }
                            }
                        }

                    }

                    // ── 3. TAB 0: CONTROL & SISTEMA ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: islandWin.currentTab === 0 && islandWin.controlSubView === 0
                        opacity: islandWin.tabFade

                        // Media Player Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 74
                            radius: 14
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Rectangle {
                                    width: 48; height: 48; radius: 10
                                    color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2)
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isPlaying ? "󰝚" : "󰝛"
                                        color: root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 20
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: root.activePlayerTitle || root.t("mod_media_nothing", "Nothing Playing")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: root.activePlayerArtist || (root.primaryPlayer?.identity ?? "Media")
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                RowLayout {
                                    spacing: 8
                                    Rectangle {
                                        width: 30; height: 30; radius: 15; color: "transparent"
                                        Text { anchors.centerIn: parent; text: "󰒮"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.primaryPlayer?.previous() || root.runCmd("playerctl previous") }
                                    }
                                    Rectangle {
                                        width: 34; height: 34; radius: 17; color: root.colAccent
                                        Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; color: root.colBg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.primaryPlayer?.playPause() || root.runCmd("playerctl play-pause") }
                                    }
                                    Rectangle {
                                        width: 30; height: 30; radius: 15; color: "transparent"
                                        Text { anchors.centerIn: parent; text: "󰒭"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.primaryPlayer?.next() || root.runCmd("playerctl next") }
                                    }
                                }
                            }
                        }

                        // Quick Toggles Grid (Wi-Fi, Bluetooth, Rust-Dock, Wallpaper) - Material 3 Dual-Action Pills
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 10
                            columnSpacing: 10

                            // Wi-Fi Tile (Material 3 Split Pill)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.wifiEnabled ? root.colAccent : root.colSurface
                                border.color: root.wifiEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    // Main Left Action: Toggle Power
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 10

                                            // Icon container / badge
                                            Rectangle {
                                                width: 34; height: 34; radius: 17
                                                color: root.wifiEnabled ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(255, 255, 255, 0.08)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.wifiEnabled ? "󰖩" : "󰖪"
                                                    color: root.wifiEnabled ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 17
                                                }
                                            }

                                            // Text Column
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: root.t("mod_wifi", "Wi-Fi")
                                                    color: root.wifiEnabled ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: root.wifiEnabled ? (root.wifiSsid || root.t("mod_wifi_connected", "Connected")) : root.t("mod_wifi_disabled", "Disabled")
                                                    color: root.wifiEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    islandWin.controlSubView = 1
                                                    root.wifiScanning = true
                                                    wifiListProc.running = true
                                                } else {
                                                    if (root.wifiEnabled) {
                                                        root.runCmd("nmcli radio wifi off")
                                                        root.wifiEnabled = false
                                                        root.wifiSsid = "Disabled"
                                                    } else {
                                                        root.runCmd("nmcli radio wifi on")
                                                        root.wifiEnabled = true
                                                        root.wifiSsid = "Connecting..."
                                                        wifiProc.running = true
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Subtle Vertical Separator
                                    Rectangle {
                                        width: 1
                                        height: 24
                                        Layout.alignment: Qt.AlignVCenter
                                        color: root.wifiEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                    }

                                    // Right Expand Action: Dedicated Chevron Button
                                    Rectangle {
                                        width: 38
                                        Layout.fillHeight: true
                                        color: wifiChevHover.containsMouse ? (root.wifiEnabled ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(255, 255, 255, 0.08)) : "transparent"
                                        radius: 16

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅂"
                                            color: root.wifiEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }

                                        MouseArea {
                                            id: wifiChevHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.controlSubView = 1
                                                root.wifiScanning = true
                                                wifiListProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Bluetooth Tile (Material 3 Split Pill)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.btEnabled ? root.colAccent : root.colSurface
                                border.color: root.btEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    // Main Left Action: Toggle Power
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 10

                                            // Icon container / badge
                                            Rectangle {
                                                width: 34; height: 34; radius: 17
                                                color: root.btEnabled ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(255, 255, 255, 0.08)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.btEnabled ? "󰂯" : "󰂲"
                                                    color: root.btEnabled ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 17
                                                }
                                            }

                                            // Text Column
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: root.t("mod_bt", "Bluetooth")
                                                    color: root.btEnabled ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: root.pairRequest.active ? root.t("mod_bt_pairing", "Pairing request pending") : (root.btEnabled ? (root.btDevices.filter(d => d.connected).length > 0 ? root.btDevices.filter(d => d.connected)[0].name : root.t("mod_bt_enabled", "Enabled")) : root.t("mod_bt_disabled", "Disabled"))
                                                    color: root.btEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                    font.weight: root.pairRequest.active ? Font.Bold : Font.Normal
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    if (root.pairRequest.active) {
                                                        islandWin.controlSubView = 6
                                                    } else {
                                                        islandWin.controlSubView = 2
                                                        btStatusProc.running = true
                                                    }
                                                } else {
                                                    const newState = !root.btEnabled
                                                    root.btEnabled = newState
                                                    if (newState) {
                                                        root.runCmd("$HOME/.local/bin/notch-bt-helper on")
                                                    } else {
                                                        root.runCmd("$HOME/.local/bin/notch-bt-helper off")
                                                    }
                                                    btDebounceSyncTimer.restart()
                                                }
                                            }
                                        }
                                    }

                                    // Subtle Vertical Separator
                                    Rectangle {
                                        width: 1
                                        height: 24
                                        Layout.alignment: Qt.AlignVCenter
                                        color: root.btEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                    }

                                    // Right Expand Action: Dedicated Chevron Button
                                    Rectangle {
                                        width: 38
                                        Layout.fillHeight: true
                                        color: btChevHover.containsMouse ? (root.btEnabled ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(255, 255, 255, 0.08)) : "transparent"
                                        radius: 16

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅂"
                                            color: root.btEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }

                                        MouseArea {
                                            id: btChevHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.controlSubView = 2
                                                root.btScanning = true
                                                btStatusProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Audio Output Tile (Material 3 Split Pill)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.isMuted ? root.colSurface : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                border.color: root.isMuted ? Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08) : root.colAccent
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    // Main Left Action: Toggle Mute
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 10

                                            Rectangle {
                                                width: 34; height: 34; radius: 17
                                                color: root.isMuted ? root.colSurface : root.colAccent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.isMuted ? "󰝟" : "󰓃"
                                                    color: root.isMuted ? "#ff5555" : root.colBg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 17
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: root.t("mod_audio", "Audio Output")
                                                    color: root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: root.isMuted ? root.t("mod_audio_muted", "Muted") : root.activeSinkName
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.isMuted = !root.isMuted
                                                root.runCmd("pamixer -t")
                                                muteProc.running = true
                                            }
                                        }
                                    }

                                    // Subtle Vertical Separator
                                    Rectangle {
                                        width: 1
                                        height: 24
                                        Layout.alignment: Qt.AlignVCenter
                                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                    }

                                    // Right Expand Action: Dedicated Chevron Button to Audio Subview
                                    Rectangle {
                                        width: 38
                                        Layout.fillHeight: true
                                        color: audioChevHover.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : "transparent"
                                        radius: 16

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅂"
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }

                                        MouseArea {
                                            id: audioChevHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.controlSubView = 3
                                                audioSinksProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Rust-Dock Tile (Material 3 Card)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.dockEnabled ? root.colAccent : (dockHover.containsMouse ? root.colSurfaceHover : root.colSurface)
                                border.color: root.dockEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: root.dockEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰻂"
                                            color: root.dockEnabled ? root.colBg : root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 17
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("mod_dock", "Rust-Dock")
                                            color: root.dockEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.dockEnabled ? root.t("mod_dock_enabled", "Enabled · click to hide") : root.t("mod_dock_disabled", "Disabled · click to show")
                                            color: root.dockEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dockHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runCmd("~/.local/bin/rust-dock-toggle-all toggle")
                                        dockStatusRefreshTimer.restart()
                                    }
                                }
                            }

                            // Notifications Tile (opens center)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: notifTileHover.containsMouse ? root.colSurfaceHover : root.colSurface
                                border.color: root.notifUnread > 0 ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: root.notifUnread > 0 ? 1.5 : 1
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰂚"
                                            color: root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 17
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("mod_notif", "Notifications")
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.notifUnread > 0 ? (root.notifUnread > 9 ? "9+ " + root.t("mod_notif_unread", "unread") : root.notifUnread + " " + root.t("mod_notif_unread", "unread")) : root.t("mod_notif_none", "No unread")
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: notifTileHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.notifOpenCenter(islandWin.modelData.name)
                                }
                            }

                            // Night Light Tile: same split layout as Wi-Fi/Bluetooth.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.nightLightEnabled ? root.colAccent : (nightTileHover.containsMouse ? root.colSurfaceHover : root.colSurface)
                                border.color: root.nightLightEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 0

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 10
                                            Rectangle {
                                                width: 34; height: 34; radius: 17
                                                color: root.nightLightEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰖔"
                                                    color: root.nightLightEnabled ? root.colBg : root.colAccent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 17
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: root.t("mod_nl", "Night Light")
                                                    color: root.nightLightEnabled ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: root.nightLightEnabled ? (root.nightLightTemperature + "K · " + root.nightLightGamma + "%") : (root.nightLightTemperature + "K · " + root.t("mod_nl_inactive", "Inactive"))
                                                    color: root.nightLightEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: nightTileHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.nightLightEnabled = !root.nightLightEnabled
                                                root.runCmd("~/.local/bin/toggle-nightlight " + (root.nightLightEnabled ? "on" : "off"))
                                                nightLightSettingsRefreshTimer.restart()
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 1
                                        height: 24
                                        Layout.alignment: Qt.AlignVCenter
                                        color: root.nightLightEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                    }

                                    Rectangle {
                                        width: 38
                                        Layout.fillHeight: true
                                        radius: 16
                                        color: nightSettingsChevronHover.containsMouse ? (root.nightLightEnabled ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(255, 255, 255, 0.08)) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅂"
                                            color: root.nightLightEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            id: nightSettingsChevronHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.controlSubView = 5
                                                nightLightSettingsProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // Caffeine Tile (Material 3 Card)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.caffeineEnabled ? root.colAccent : (caffeineHover.containsMouse ? root.colSurfaceHover : root.colSurface)
                                border.color: root.caffeineEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: root.caffeineEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅶"
                                            color: root.caffeineEnabled ? root.colBg : root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 17
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("mod_caffeine", "Caffeine")
                                            color: root.caffeineEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.caffeineEnabled ? root.t("mod_caffeine_awake", "Awake Mode") : root.t("mod_caffeine_sleep", "Normal Sleep")
                                            color: root.caffeineEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: caffeineHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.caffeineEnabled = !root.caffeineEnabled
                                        root.runCmd("~/.local/bin/toggle-caffeine")
                                    }
                                }
                            }

                            // Power Saver Tile (Material 3 Card)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.powerSaverEnabled ? root.colAccent : (powerHover.containsMouse ? root.colSurfaceHover : root.colSurface)
                                border.color: root.powerSaverEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: root.powerSaverEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰌪"
                                            color: root.powerSaverEnabled ? root.colBg : root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 17
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("mod_powersave", "Power Saver")
                                            color: root.powerSaverEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.powerSaverEnabled ? root.t("mod_powersave_eco", "Eco Active") : root.t("mod_powersave_disabled", "Disabled")
                                            color: root.powerSaverEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: powerHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.powerSaverEnabled = !root.powerSaverEnabled
                                        if (root.powerSaverEnabled) root.perfMode = false
                                        root.runCmd("~/.local/bin/toggle-powersave")
                                    }
                                }
                            }

                            // Performance Tile (Material 3 Card)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.perfMode ? root.colAccent : (perfHoverTab0.containsMouse ? root.colSurfaceHover : root.colSurface)
                                border.color: root.perfMode ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: root.perfMode ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰓅"
                                            color: root.perfMode ? root.colBg : root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 17
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("mod_perf", "Performance")
                                            color: root.perfMode ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.perfMode ? root.t("mod_perf_boost", "Max Boost") : root.t("mod_perf_balanced", "Balanced")
                                            color: root.perfMode ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: perfHoverTab0
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.perfMode = !root.perfMode
                                        if (root.perfMode) root.powerSaverEnabled = false
                                        root.runCmd("$HOME/.local/bin/notch-hypr-helper toggle-perf")
                                        hyprRefreshTimer.restart()
                                    }
                                }
                            }
                            // Do Not Disturb Tile (Material 3 Card)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 54
                                radius: 16
                                color: root.dndEnabled ? root.colAccent : (dndHover.containsMouse ? root.colSurfaceHover : root.colSurface)
                                border.color: root.dndEnabled ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 34; height: 34; radius: 17
                                        color: root.dndEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.25) : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰂛"
                                            color: root.dndEnabled ? root.colBg : root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 17
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("mod_dnd", "Do Not Disturb")
                                            color: root.dndEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.dndEnabled ? root.t("mod_dnd_silenced", "Silenced") : root.t("mod_dnd_sounds", "Sounds On")
                                            color: root.dndEnabled ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: dndHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.dndEnabled = !root.dndEnabled
                                        root.runCmd("~/.local/bin/toggle-dnd")
                                    }
                                }
                            }
                        }

                        // Sliders Card (Material 3 Pill Sliders: Volume & Brightness)
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Volume Pill Slider
                            Rectangle {
                                id: volSliderTrack
                                Layout.fillWidth: true
                                height: 42
                                radius: 21
                                color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                clip: true

                                // Progress Fill Bar
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(parent.height, parent.width * (root.isMuted ? 0 : root.volumeLevel))
                                    radius: 21
                                    color: root.isMuted ? root.colMuted : root.colAccent
                                    visible: !root.isMuted && root.volumeLevel > 0
                                    Behavior on width {
                                        enabled: !volMouseArea.pressed && !capsuleWidthAnim.running && islandWin.expanded
                                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 14
                                    spacing: 8

                                    // Inset Icon Button
                                    Text {
                                        text: root.isMuted ? "󰝟" : (root.volumeLevel > 0.5 ? "󰕾" : (root.volumeLevel > 0 ? "󰖀" : "󰕿"))
                                        color: root.isMuted ? "#ff5555" : (root.volumeLevel > 0 ? root.colBg : root.colAccent)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.t("mod_volume", "Volume")
                                        color: (!root.isMuted && root.volumeLevel > 0.85) ? root.colBg : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        opacity: (!root.isMuted && root.volumeLevel > 0.85) ? 0.9 : 0.7
                                        visible: !root.isMuted
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Text {
                                        text: root.isMuted ? "Muted" : (Math.round(root.volumeLevel * 100) + "%")
                                        color: (!root.isMuted && root.volumeLevel > 0.85) ? root.colBg : (root.isMuted ? "#ff5555" : root.colFg)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: volMouseArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.x < 36) {
                                            root.isMuted = !root.isMuted
                                            root.runCmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")
                                        } else {
                                            const p = Math.max(0, Math.min(1, mouse.x / width))
                                            root.volumeLevel = p
                                            root.isMuted = false
                                            root.runCmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + Math.round(p * 100) + "%")
                                        }
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed) {
                                            const p = Math.max(0, Math.min(1, mouse.x / width))
                                            root.volumeLevel = p
                                            root.isMuted = false
                                            root.runCmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + Math.round(p * 100) + "%")
                                        }
                                    }
                                }
                            }

                            // Brightness Pill Slider
                            Rectangle {
                                id: brightSliderTrack
                                Layout.fillWidth: true
                                height: 42
                                radius: 21
                                color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: 1
                                clip: true

                                // Progress Fill Bar
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(parent.height, parent.width * root.brightnessLevel)
                                    radius: 21
                                    color: root.colAccent
                                    Behavior on width {
                                        enabled: !brightMouseArea.pressed && !capsuleWidthAnim.running && islandWin.expanded
                                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 14
                                    spacing: 8

                                    // Inset Icon Button
                                    Text {
                                        text: root.brightnessLevel > 0.6 ? "󰃠" : (root.brightnessLevel > 0.25 ? "󰃟" : "󰃞")
                                        color: root.colBg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                        font.weight: Font.Bold
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: root.t("mod_brightness", "Brightness")
                                        color: root.brightnessLevel > 0.85 ? root.colBg : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        opacity: root.brightnessLevel > 0.85 ? 0.9 : 0.7
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    Text {
                                        text: Math.round(root.brightnessLevel * 100) + "%"
                                        color: root.brightnessLevel > 0.85 ? root.colBg : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: brightMouseArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const p = Math.max(0.05, Math.min(1, mouse.x / width))
                                        root.brightnessLevel = p
                                        root.runCmd("brightnessctl set " + Math.round(p * 100) + "%")
                                    }
                                    onPositionChanged: mouse => {
                                        if (pressed) {
                                            const p = Math.max(0.05, Math.min(1, mouse.x / width))
                                            root.brightnessLevel = p
                                            root.runCmd("brightnessctl set " + Math.round(p * 100) + "%")
                                        }
                                    }
                                }
                            }
                        }

                        // Hardware Monitoring Card (Material 3 Segmented Stats)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 52
                            radius: 14
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                // CPU Stat
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        spacing: 6
                                        Text { text: "󰻠"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                        Text { text: "CPU"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                        Item { Layout.fillWidth: true }
                                        Text { text: (root.sysStats?.cpu_pct ?? 0) + "%"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; height: 4; radius: 2
                                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysStats?.cpu_pct ?? 0) / 100.0)))
                                            radius: 2; color: root.colAccent
                                            Behavior on width { NumberAnimation { duration: 200 } }
                                        }
                                    }
                                }

                                // Separator
                                Rectangle { width: 1; height: 26; color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1) }

                                // RAM Stat
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        spacing: 6
                                        Text { text: "󰍛"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                        Text { text: "RAM " + (root.sysStats?.ram_used ?? ""); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight }
                                        Item { Layout.fillWidth: true }
                                        Text { text: (root.sysStats?.ram_pct ?? 0) + "%"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; height: 4; radius: 2
                                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysStats?.ram_pct ?? 0) / 100.0)))
                                            radius: 2; color: root.colAccent
                                            Behavior on width { NumberAnimation { duration: 200 } }
                                        }
                                    }
                                }

                                // Separator
                                Rectangle { width: 1; height: 26; color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1) }

                                // Disk Stat
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    RowLayout {
                                        spacing: 6
                                        Text { text: "󰋊"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                        Text { text: "SSD " + (root.sysStats?.disk_used ?? ""); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight }
                                        Item { Layout.fillWidth: true }
                                        Text { text: (root.sysStats?.disk_pct ?? 0) + "%"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; height: 4; radius: 2
                                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            width: Math.max(0, Math.min(parent.width, parent.width * ((root.sysStats?.disk_pct ?? 0) / 100.0)))
                                            radius: 2; color: root.colAccent
                                            Behavior on width { NumberAnimation { duration: 200 } }
                                        }
                                    }
                                }
                            }
                        }

                        // Bottom Action Chips (Material 3 Pills)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 18; color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08); border.width: 1
                                RowLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "󰈊"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.t("mod_picker", "Picker"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { islandWin.expanded = false; root.runCmd("hyprpicker -a"); } }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 18; color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08); border.width: 1
                                RowLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "󰸉"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.t("mod_gallery", "Gallery"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                // El "sleep 0.6" no es cosmetico. La isla pide foco de teclado
                                // (OnDemand) mientras esta expandida, y si rofi se abre en ese
                                // momento no lo consigue: se auto-selecciona la primera entrada y
                                // se cierra, sin que se vea nada. Medido: lanzado con setsid rofi
                                // devolvia "primero.webp" al instante; con medio segundo de espera se
                                // queda esperando al usuario.
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { islandWin.expanded = false; root.runCmd("sleep 0.6 && ~/.local/bin/wallpaper-gallery"); } }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 18; color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08); border.width: 1
                                RowLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "󰑐"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.t("mod_random", "Random"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                // Este boton pone "Random" y un icono de barajado, pero llamaba a
                                // wallpaper-changer-with-waybar-sync, que abre un selector para elegir
                                // a mano. No es lo aleatorio, y por eso pulsarlo no hacia lo que el
                                // nombre promete. wallpaper-random es el que corresponde y ya
                                // funcionaba.
                                //
                                // Sin el "sleep 0.6" del boton de galeria: aqui no se abre ningun
                                // menu de rofi al que haya que robarle el foco.
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.runCmd("~/.local/bin/wallpaper-random") }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 18
                                color: root.recState.recording ? Qt.rgba(239/255, 83/255, 80/255, 0.25) : root.colSurface
                                border.color: root.recState.recording ? "#EF5350" : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                border.width: root.recState.recording ? 1.5 : 1
                                RowLayout { anchors.centerIn: parent; spacing: 5
                                    Text {
                                        text: root.recState.recording ? "󰓛" : "󰕧"
                                        color: root.recState.recording ? "#EF5350" : root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                                    }
                                    Text {
                                        text: root.recState.recording ? root.recState.elapsed_str : root.t("mod_record", "Record")
                                        color: root.recState.recording ? "#EF5350" : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runCmd("$HOME/.local/bin/screen-recorder-helper toggle")
                                        recStatusProc.running = true
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 36; radius: 18; color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08); border.width: 1
                                RowLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "󰌌"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.kbLayout; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.runCmd("~/.local/bin/toggle-keyboard-layout"); kbProc.running = true; } }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 18; color: root.colSurface
                                border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08); border.width: 1
                                RowLayout { anchors.centerIn: parent; spacing: 5
                                    Text { text: "󰈮"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.t("mod_tasks", "Tasks"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { islandWin.expanded = false; root.runCmd("kitty -e htop"); } }
                            }
                        }

                    }

                    // ── 3. SUBSECCIÓN: REDES WI-FI (CONTROL) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: islandWin.controlSubView === 1

                        // Sub-header with back button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 100
                                height: 32
                                radius: 16
                                color: root.colSurface
                                border.color: root.colBorder
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "󰁍"
                                        color: root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        text: root.t("wifi_back", "Back")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandWin.controlSubView = 0
                                }
                            }

                            Text {
                                text: root.t("wifi_title", "Available Wi-Fi Networks")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Header card: Wi-Fi master switch & quick buttons
                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: 14
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 36; height: 36; radius: 18
                                    color: root.wifiEnabled ? root.colAccent : root.colSurface
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.wifiEnabled ? "󰖩" : "󰖪"
                                        color: root.wifiEnabled ? root.colBg : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Wi-Fi"
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        text: root.wifiEnabled ? (root.wifiSsid !== "Disabled" && root.wifiSsid !== "Disconnected" ? (root.t("wifi_connected", "Connected to:") + " " + root.wifiSsid) : root.t("mod_wifi_enabled", "Enabled")) : root.t("mod_wifi_disabled", "Disabled")
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: 8

                                    // Rescan button
                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: root.wifiScanning ? root.colAccent : Qt.rgba(255, 255, 255, 0.08)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰑐"
                                            color: root.wifiScanning ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.wifiScanning = true
                                                wifiRescanProc.running = true
                                            }
                                        }
                                    }

                                    // Advanced GUI button
                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: Qt.rgba(255, 255, 255, 0.08)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰒓"
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.expanded = false
                                                root.runCmd("nm-connection-editor")
                                            }
                                        }
                                    }

                                    // Master Toggle Pill
                                    Rectangle {
                                        width: 68; height: 32; radius: 16
                                        color: root.wifiEnabled ? root.colAccent : root.colSurface
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.wifiEnabled ? "ON" : "OFF"
                                            color: root.wifiEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.wifiEnabled) {
                                                    root.runCmd("nmcli radio wifi off")
                                                    root.wifiEnabled = false
                                                    root.wifiSsid = "Disabled"
                                                } else {
                                                    root.runCmd("nmcli radio wifi on")
                                                    root.wifiEnabled = true
                                                    root.wifiScanning = true
                                                    wifiListProc.running = true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 10
                            visible: islandWin.selectedWifiSsid === "" && islandWin.wifiConnectState !== "idle"
                            color: Qt.rgba(76/255, 175/255, 80/255, 0.18)
                            border.color: "#4caf50"
                            border.width: 1
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                text: islandWin.wifiConnectMessage
                                color: "#80d890"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }

                        // Inline Wi-Fi password card; errors stay here for retry.
                        Rectangle {
                            Layout.fillWidth: true
                            height: islandWin.wifiConnectState === "idle" ? 48 : 96
                            radius: 12
                            color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                            border.color: islandWin.wifiConnectState === "error" ? "#ef5350" : root.colAccent
                            border.width: 1
                            visible: islandWin.selectedWifiSsid !== ""

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 7

                                    Text {
                                        text: "󰌾 " + islandWin.selectedWifiSsid
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        Layout.preferredWidth: 112
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 30
                                        radius: 8
                                        color: root.colBg
                                        TextInput {
                                            id: wifiPassInput
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            echoMode: islandWin.wifiPasswordVisible ? TextInput.Normal : TextInput.Password
                                            enabled: islandWin.wifiConnectState !== "connecting" && islandWin.wifiConnectState !== "connected"
                                            selectByMouse: true
                                            clip: true
                                            onAccepted: connectBtnArea.clicked(null)
                                        }
                                    }

                                    Rectangle {
                                        width: 42; height: 30; radius: 8
                                        color: root.colSurface
                                        Text {
                                            anchors.centerIn: parent
                                            text: islandWin.wifiPasswordVisible ? root.t("wifi_hide", "Hide") : root.t("wifi_show", "Show")
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: islandWin.wifiConnectState !== "connecting" && islandWin.wifiConnectState !== "connected"
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: islandWin.wifiPasswordVisible = !islandWin.wifiPasswordVisible
                                        }
                                    }

                                    Rectangle {
                                        width: 76; height: 30; radius: 8
                                        color: islandWin.wifiConnectState === "connected" ? "#4caf50" : root.colAccent
                                        opacity: islandWin.wifiConnectState === "connecting" ? 0.65 : 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: islandWin.wifiConnectState === "connecting" ? root.t("wifi_connecting", "Connecting") :
                                                  islandWin.wifiConnectState === "connected" ? "Connected" :
                                                  islandWin.wifiConnectState === "error" ? "Retry" : "Connect"
                                            color: root.colBg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            id: connectBtnArea
                                            anchors.fill: parent
                                            enabled: islandWin.wifiConnectState !== "connecting" && islandWin.wifiConnectState !== "connected"
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const pass = wifiPassInput.text
                                                if (pass.length === 0) {
                                                    islandWin.wifiConnectState = "error"
                                                    islandWin.wifiConnectMessage = "Enter the Wi-Fi password. Use Show to check it before connecting."
                                                    return
                                                }
                                                root.startWifiConnect(islandWin.modelData.name, islandWin.selectedWifiSsid, pass, false)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 28; height: 30; radius: 8
                                        color: root.colSurface
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.selectedWifiSsid = ""
                                                islandWin.wifiConnectState = "idle"
                                                islandWin.wifiConnectMessage = ""
                                                islandWin.wifiPasswordVisible = false
                                                wifiPassInput.text = ""
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: islandWin.wifiConnectState !== "idle"
                                    text: islandWin.wifiConnectMessage
                                    color: islandWin.wifiConnectState === "error" ? "#ff7777" :
                                           islandWin.wifiConnectState === "connected" ? "#80d890" : root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Available Networks List
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: islandWin.selectedWifiSsid !== "" ? 300 : 355
                            contentWidth: width
                            contentHeight: wifiNetColumn.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: wifiNetColumn
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: root.wifiList
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 44
                                        radius: 12
                                        color: modelData.connected ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.18) : root.colSurface
                                        border.color: modelData.connected ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            Text {
                                                text: modelData.signal >= 75 ? "󰤨" : (modelData.signal >= 50 ? "󰤥" : (modelData.signal >= 25 ? "󰤢" : "󰤟"))
                                                color: modelData.connected ? root.colAccent : root.colFg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 16
                                            }

                                            ColumnLayout {
                                                spacing: 0
                                                Layout.fillWidth: true
                                                Text {
                                                    text: modelData.ssid
                                                    color: root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: modelData.connected ? Font.Bold : Font.Normal
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: (modelData.saved ? (root.t("wifi_saved", "Saved") + "  •  ") : "") + modelData.signal + "%  •  " + modelData.security
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                }
                                            }

                                            Rectangle {
                                                height: 26
                                                width: modelData.connected ? 95 : 72
                                                radius: 8
                                                color: modelData.connected ? Qt.rgba(255, 85, 85, 0.2) : root.colAccent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.connected ? root.t("wifi_disconnect", "Disconnect") : root.t("wifi_connect", "Connect")
                                                    color: modelData.connected ? "#ff5555" : root.colBg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.connected) {
                                                            root.runCmd("~/.local/bin/notch-wifi-helper disconnect")
                                                            wifiListProc.running = true
                                                        } else {
                                                            if (modelData.saved) {
                                                                // Reuse NetworkManager's saved credentials; only show the password
                                                                // form if bringing the saved profile up fails.
                                                                root.startWifiConnect(islandWin.modelData.name, modelData.ssid, "", true)
                                                            } else if (modelData.security === "Open" || modelData.security === "Abierta" || modelData.security === "--") {
                                                                islandWin.selectedWifiSsid = ""
                                                                islandWin.wifiConnectState = "idle"
                                                                islandWin.wifiConnectMessage = ""
                                                                root.startWifiConnect(islandWin.modelData.name, modelData.ssid, "", false)
                                                            } else {
                                                                islandWin.selectedWifiSsid = modelData.ssid
                                                                islandWin.wifiConnectState = "idle"
                                                                islandWin.wifiConnectMessage = ""
                                                                islandWin.wifiPasswordVisible = false
                                                                wifiPassInput.text = ""
                                                                wifiPassInput.forceActiveFocus()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: root.wifiList.length === 0
                                    text: root.wifiScanning ? root.t("wifi_scanning", "Scanning nearby Wi-Fi networks...") : root.t("wifi_none", "No Wi-Fi networks found. Click Scan.")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 20
                                }
                            }
                        }
                    }

                    // ── 4. SUBSECCIÓN: BLUETOOTH (CONTROL) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: islandWin.controlSubView === 2

                        // Sub-header with back button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 100
                                height: 32
                                radius: 16
                                color: root.colSurface
                                border.color: root.colBorder
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "󰁍"
                                        color: root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        text: root.t("bt_back", "Back")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandWin.controlSubView = 0
                                }
                            }

                            Text {
                                text: root.t("bt_title", "Bluetooth Devices")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Header card: Bluetooth master switch & quick buttons
                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: 14
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 36; height: 36; radius: 18
                                    color: root.btEnabled ? root.colAccent : root.colSurface
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.btEnabled ? "󰂯" : "󰂲"
                                        color: root.btEnabled ? root.colBg : root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Text {
                                        text: "Bluetooth"
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        text: !root.btEnabled ? root.t("mod_bt_disabled", "Disabled") : (root.btScanning ? root.t("bt_scanning_short", "Scanning nearby...") : (root.namedBtDevices.length > 0 ? (root.namedBtDevices.length + " " + root.t("bt_devices_avail", "devices available")) : root.t("bt_ready", "Ready to pair")))
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: 8

                                    // Rescan / Scan toggle button
                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: root.btScanning ? root.colAccent : Qt.rgba(255, 255, 255, 0.08)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰑐"
                                            color: root.btScanning ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.btScanning) {
                                                    root.runCmd("$HOME/.local/bin/notch-bt-helper stop_scan")
                                                    root.btScanning = false
                                                } else {
                                                    root.btScanning = true
                                                    root.runCmd("$HOME/.local/bin/notch-bt-helper scan")
                                                    btPollTimer.restart()
                                                }
                                            }
                                        }
                                    }

                                    // Advanced GUI button
                                    Rectangle {
                                        width: 32; height: 32; radius: 16
                                        color: Qt.rgba(255, 255, 255, 0.08)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰒓"
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.expanded = false
                                                root.runCmd("blueman-manager")
                                            }
                                        }
                                    }

                                    // Master Toggle Pill
                                    Rectangle {
                                        width: 68; height: 32; radius: 16
                                        color: root.btEnabled ? root.colAccent : root.colSurface
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.btEnabled ? "ON" : "OFF"
                                            color: root.btEnabled ? root.colBg : root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const newState = !root.btEnabled
                                                root.btEnabled = newState
                                                if (newState) {
                                                    root.runCmd("$HOME/.local/bin/notch-bt-helper on")
                                                    root.runCmd("$HOME/.local/bin/notch-bt-helper scan")
                                                } else {
                                                    root.runCmd("$HOME/.local/bin/notch-bt-helper off")
                                                    root.runCmd("$HOME/.local/bin/notch-bt-helper stop_scan")
                                                }
                                                btDebounceSyncTimer.restart()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Disabled state placeholder
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 30
                            spacing: 10
                            Layout.alignment: Qt.AlignHCenter
                            visible: !root.btEnabled

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 56; height: 56; radius: 28
                                color: root.colSurface
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰂲"
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 26
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.t("bt_disabled_title", "Bluetooth is Disabled")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.t("bt_disabled_desc", "Turn on Bluetooth to discover and connect nearby devices")
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 6
                                width: 160; height: 32; radius: 16
                                color: root.colAccent
                                Text {
                                    anchors.centerIn: parent
                                    text: root.t("bt_turn_on", "Turn On Bluetooth")
                                    color: root.colBg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.btEnabled = true
                                        root.runCmd("$HOME/.local/bin/notch-bt-helper on")
                                        root.runCmd("$HOME/.local/bin/notch-bt-helper scan")
                                        btDebounceSyncTimer.restart()
                                    }
                                }
                            }
                        }

                        // Enabled: Devices List
                        Flickable {
                            visible: root.btEnabled
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            Layout.preferredHeight: 350
                            contentWidth: width
                            contentHeight: btDevColumn.implicitHeight + 20
                            clip: true

                            ColumnLayout {
                                id: btDevColumn
                                width: parent.width
                                spacing: 6

                                // Scanning banner
                                Rectangle {
                                    visible: root.btScanning
                                    Layout.fillWidth: true
                                    height: 28
                                    radius: 8
                                    color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.12)
                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text {
                                            text: "󰑐"
                                            color: root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: root.t("bt_scanning", "Scanning nearby Bluetooth devices...")
                                            color: root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                // Empty state when no named devices
                                Text {
                                    visible: root.namedBtDevices.length === 0 && !root.btScanning
                                    text: root.t("bt_none_found", "No paired or named devices found. Click Scan above.")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 20
                                }

                                // 1. Named / Paired / Connected Devices
                                Repeater {
                                    model: root.namedBtDevices
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 48
                                        radius: 12
                                        color: modelData.connected ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.18) : root.colSurface
                                        border.color: modelData.connected ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 10

                                            Text {
                                                text: {
                                                    const t = (modelData.icon || "").toLowerCase()
                                                    const n = (modelData.name || "").toLowerCase()
                                                    if (t.indexOf("audio") >= 0 || t.indexOf("headset") >= 0 || t.indexOf("headphone") >= 0 || n.indexOf("wh-") >= 0 || n.indexOf("airpods") >= 0 || n.indexOf("buds") >= 0) return "󰋋"
                                                    if (t.indexOf("speaker") >= 0 || n.indexOf("speaker") >= 0 || n.indexOf("flip") >= 0 || n.indexOf("charge") >= 0 || n.indexOf("jbl") >= 0) return "󰓃"
                                                    if (t.indexOf("keyboard") >= 0 || n.indexOf("key") >= 0) return "󰌌"
                                                    if (t.indexOf("mouse") >= 0 || n.indexOf("mouse") >= 0) return "󰍽"
                                                    if (t.indexOf("phone") >= 0 || n.indexOf("iphone") >= 0 || n.indexOf("galaxy") >= 0) return "󰄡"
                                                    if (t.indexOf("gamepad") >= 0 || n.indexOf("controller") >= 0 || n.indexOf("dualsense") >= 0 || n.indexOf("xbox") >= 0) return "󰊴"
                                                    if (t.indexOf("computer") >= 0 || n.indexOf("mac") >= 0 || n.indexOf("pc") >= 0) return "󰌢"
                                                    return "󰂯"
                                                }
                                                color: modelData.connected ? root.colAccent : root.colFg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 18
                                            }

                                            ColumnLayout {
                                                spacing: 0
                                                Layout.fillWidth: true
                                                Text {
                                                    text: modelData.name || modelData.mac
                                                    color: root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: modelData.connected ? Font.Bold : Font.Normal
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: modelData.mac + (modelData.connected ? ("  •  " + root.t("bt_connected", "Connected")) : (modelData.paired ? ("  •  " + root.t("bt_paired", "Paired")) : (modelData.rssi ? "  •  " + modelData.rssi + " dBm" : ("  •  " + root.t("bt_available", "Available")))))
                                                    color: modelData.connected ? root.colAccent : root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                }
                                            }

                                            // Connect / Disconnect / Pair Button
                                            Rectangle {
                                                height: 26
                                                width: modelData.connected ? 95 : (modelData.paired ? 72 : 90)
                                                radius: 8
                                                color: modelData.connected ? Qt.rgba(255, 85, 85, 0.2) : root.colAccent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.connected ? root.t("bt_disconnect", "Disconnect") : (modelData.paired ? root.t("bt_connect", "Connect") : root.t("bt_pair", "Pair & Link"))
                                                    color: modelData.connected ? "#ff5555" : root.colBg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData.connected) {
                                                             root.runCmd("$HOME/.local/bin/notch-bt-helper disconnect " + modelData.mac)
                                                        } else {
                                                             root.runCmd("$HOME/.local/bin/notch-bt-helper connect " + modelData.mac)
                                                        }
                                                        btDebounceSyncTimer.restart()
                                                    }
                                                }
                                            }

                                            // Remove / Unpair Button (only for paired or connected)
                                            Rectangle {
                                                visible: modelData.paired || modelData.connected
                                                width: 26; height: 26; radius: 8
                                                color: Qt.rgba(255, 255, 255, 0.06)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰆴"
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.runCmd("$HOME/.local/bin/notch-bt-helper remove " + modelData.mac)
                                                        btDebounceSyncTimer.restart()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // 2. Collapsible Unnamed Devices Section
                                Rectangle {
                                    visible: root.unnamedBtDevices.length > 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    height: 32
                                    radius: 8
                                    color: Qt.rgba(255, 255, 255, 0.04)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6
                                        Text {
                                            text: root.showUnnamedBtDevices ? "󰅀" : "󰅂"
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            text: (root.showUnnamedBtDevices ? root.t("bt_hide_unnamed", "Hide") : root.t("bt_show_unnamed", "Show")) + " " + root.unnamedBtDevices.length + " " + root.t("bt_unnamed_desc", "unnamed devices (beacons)")
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            Layout.fillWidth: true
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.showUnnamedBtDevices = !root.showUnnamedBtDevices
                                    }
                                }

                                Repeater {
                                    model: root.showUnnamedBtDevices ? root.unnamedBtDevices : []
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 42
                                        radius: 10
                                        color: Qt.rgba(255, 255, 255, 0.03)
                                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.04)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 8

                                            Text {
                                                text: "󰂯"
                                                color: root.colMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 14
                                            }

                                            ColumnLayout {
                                                spacing: 0
                                                Layout.fillWidth: true
                                                Text {
                                                    text: root.t("bt_unnamed_device", "Unnamed Device")
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                                Text {
                                                    text: modelData.mac + (modelData.rssi ? "  •  " + modelData.rssi + " dBm" : "")
                                                    color: Qt.rgba(root.colMuted.r, root.colMuted.g, root.colMuted.b, 0.6)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 8
                                                }
                                            }

                                            Rectangle {
                                                height: 24
                                                width: 60
                                                radius: 6
                                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.t("bt_pair", "Pair")
                                                    color: root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                    font.weight: Font.Bold
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.runCmd("$HOME/.local/bin/notch-bt-helper connect " + modelData.mac)
                                                        btDebounceSyncTimer.restart()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── 4. SUBSECCIÓN: DISPOSITIVOS DE AUDIO (CONTROL) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: islandWin.controlSubView === 3

                        // Sub-header with back button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 100
                                height: 32
                                radius: 16
                                color: root.colSurface
                                border.color: root.colBorder
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "󰁍"
                                        color: root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        text: root.t("audio_back", "Back")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: islandWin.controlSubView = 0
                                }
                            }

                            Text {
                                text: root.t("audio_title", "Audio Output Devices")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Item { Layout.fillWidth: true }

                            // Refresh button
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: Qt.rgba(255, 255, 255, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑐"
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: audioSinksProc.running = true
                                }
                            }

                            // Pavucontrol GUI button
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: Qt.rgba(255, 255, 255, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒓"
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        islandWin.expanded = false
                                        root.runCmd("pavucontrol")
                                    }
                                }
                            }
                        }

                        // Sinks List
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 380
                            contentWidth: width
                            contentHeight: audioSinksColumn.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: audioSinksColumn
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: root.audioSinks
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 54
                                        radius: 14
                                        color: modelData.active ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.18) : (sinkHover.containsMouse ? root.colSurfaceHover : root.colSurface)
                                        border.color: modelData.active ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 12

                                            Rectangle {
                                                width: 34; height: 34; radius: 17
                                                color: modelData.active ? root.colAccent : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.active ? "󰓃" : "󰕾"
                                                    color: modelData.active ? root.colBg : root.colAccent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 16
                                                }
                                            }

                                            ColumnLayout {
                                                spacing: 2
                                                Layout.fillWidth: true
                                                Text {
                                                    text: modelData.name || ("Sink #" + modelData.id)
                                                    color: root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                    font.weight: modelData.active ? Font.Bold : Font.Normal
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: "ID: " + modelData.id + "  •  Volume: " + modelData.volume + "%"
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                }
                                            }

                                            Rectangle {
                                                width: modelData.active ? 72 : 80
                                                height: 30
                                                radius: 15
                                                color: modelData.active ? root.colAccent : Qt.rgba(255, 255, 255, 0.08)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.active ? ("󰄬 " + root.t("audio_sink_active", "Active")) : root.t("audio_select", "Select")
                                                    color: modelData.active ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: sinkHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.runCmd("~/.local/bin/notch-audio-helper set " + modelData.id)
                                                root.activeSinkName = modelData.name
                                                audioSinksProc.running = true
                                                volProc.running = true
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: root.audioSinks.length === 0
                                    text: root.t("audio_none", "No audio output devices detected.")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 20
                                }

                                // ── Application Volume Mixer ──
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 10
                                    Text {
                                        text: root.t("audio_mixer", "Application Volume Mixer")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: root.audioApps.length + " " + root.t("audio_active_apps", "active app(s)")
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                    }
                                }

                                Repeater {
                                    model: root.audioApps
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        height: 56
                                        radius: 12
                                        color: root.colSurface
                                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 6

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: modelData.icon || "󰓃"
                                                    color: root.colAccent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                }

                                                Text {
                                                    text: modelData.name || ("App #" + modelData.id)
                                                    color: root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                Text {
                                                    text: (modelData.muted ? root.t("mod_audio_muted", "Muted") : (modelData.volume + "%"))
                                                    color: modelData.muted ? "#EF5350" : root.colAccent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }

                                                Rectangle {
                                                    width: 24; height: 24; radius: 12
                                                    color: modelData.muted ? Qt.rgba(239/255, 83/255, 80/255, 0.2) : Qt.rgba(255, 255, 255, 0.08)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.muted ? "󰝟" : "󰕾"
                                                        color: modelData.muted ? "#EF5350" : root.colFg
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 11
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            root.runCmd("$HOME/.local/bin/notch-audio-helper toggle-app-mute " + modelData.id)
                                                            audioAppsProc.running = true
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                id: appSliderTrack
                                                Layout.fillWidth: true
                                                height: 8
                                                radius: 4
                                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    width: Math.max(0, Math.min(parent.width, parent.width * ((modelData.volume || 0) / 100.0)))
                                                    radius: 4
                                                    color: modelData.muted ? root.colMuted : root.colAccent
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onPositionChanged: mouse => {
                                                        if (pressed) {
                                                            let pct = Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100)))
                                                            root.runCmd("$HOME/.local/bin/notch-audio-helper set-app-vol " + modelData.id + " " + pct)
                                                            modelData.volume = pct
                                                        }
                                                    }
                                                    onClicked: mouse => {
                                                        let pct = Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100)))
                                                        root.runCmd("$HOME/.local/bin/notch-audio-helper set-app-vol " + modelData.id + " " + pct)
                                                        audioAppsProc.running = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: root.audioApps.length === 0
                                    text: root.t("audio_no_apps", "No active application audio streams.")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 4
                                    Layout.bottomMargin: 8
                                }
                            }
                        }
                    }

                    // ── 5. TAB 1: AJUSTES HYPRLAND ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: islandWin.currentTab === 1 && islandWin.controlSubView === 0
                        opacity: islandWin.tabFade

                        // Subtitle
                        Text {
                            text: root.t("hypr_title", "Real-time Hyprland Compositor Settings")

                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            Layout.alignment: Qt.AlignHCenter
                        }


                        // 4 Hyprland Toggles (2x2 Grid)
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 8
                            columnSpacing: 8

                            // Animaciones
                            Rectangle {
                                Layout.fillWidth: true
                                height: 54
                                radius: 14
                                color: root.hyprAnim ? root.colAccent : root.colSurface
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10
                                    Text { text: "󰑮"; color: root.hyprAnim ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: root.t("hypr_animations", "Animations"); color: root.hyprAnim ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                                        Text { text: root.hyprAnim ? root.t("hypr_enabled", "Enabled") : root.t("hypr_disabled", "Disabled"); color: root.hyprAnim ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.hyprAnim = !root.hyprAnim
                                        root.runCmd("$HOME/.local/bin/notch-hypr-helper set-anim " + root.hyprAnim)
                                    }
                                }
                            }

                            // Desenfoque Blur
                            Rectangle {
                                Layout.fillWidth: true
                                height: 54
                                radius: 14
                                color: root.hyprBlur ? root.colAccent : root.colSurface
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10
                                    Text { text: "󰂵"; color: root.hyprBlur ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: root.t("hypr_blur", "Blur Effect"); color: root.hyprBlur ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                                        Text { text: root.hyprBlur ? root.t("hypr_enabled", "Enabled") : root.t("hypr_disabled", "Disabled"); color: root.hyprBlur ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.hyprBlur = !root.hyprBlur
                                        root.runCmd("$HOME/.local/bin/notch-hypr-helper set-blur " + root.hyprBlur)
                                    }
                                }
                            }

                            // Sombras
                            Rectangle {
                                Layout.fillWidth: true
                                height: 54
                                radius: 14
                                color: root.hyprShadow ? root.colAccent : root.colSurface
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10
                                    Text { text: "󰞏"; color: root.hyprShadow ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: root.t("hypr_shadows", "Shadows"); color: root.hyprShadow ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                                        Text { text: root.hyprShadow ? root.t("hypr_enabled", "Enabled") : root.t("hypr_disabled", "Disabled"); color: root.hyprShadow ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.hyprShadow = !root.hyprShadow
                                        root.runCmd("$HOME/.local/bin/notch-hypr-helper set-shadow " + root.hyprShadow)
                                    }
                                }
                            }

                            // Rendimiento
                            Rectangle {
                                Layout.fillWidth: true
                                height: 54
                                radius: 14
                                color: root.perfMode ? root.colAccent : root.colSurface
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10
                                    Text { text: "󰓅"; color: root.perfMode ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 20 }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: root.t("hypr_perf", "Performance"); color: root.perfMode ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                                        Text { text: root.perfMode ? root.t("hypr_max_perf", "Max Performance") : root.t("hypr_balanced", "Balanced"); color: root.perfMode ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.perfMode = !root.perfMode
                                        if (root.perfMode) root.powerSaverEnabled = false
                                        root.runCmd("$HOME/.local/bin/notch-hypr-helper toggle-perf")
                                        hyprRefreshTimer.restart()
                                    }
                                }
                            }

                            // Batteries / Power Source: muestra baterías si existen o estado de corriente directa / AC
                            Rectangle {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            height: 54
                            radius: 14
                            visible: true
                            color: root.colSurface

                            RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10
                            Text {
                                text: (root.batt?.count ?? 0) > 0 ? "󰁹" : "󰚥"
                                color: root.colAccent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 20
                            }
                            ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Text {
                                text: (root.batt?.count ?? 0) > 0 ? root.t("hypr_batteries", "Batteries") : root.t("hypr_power_source", "Power Source")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Text {
                                text: (root.batt?.count ?? 0) > 1
                                    ? (root.batt.count) + " " + root.t("bat_devices", "devices") + " · " + (root.batt.total_pct ?? 0) + "% · "
                                      + ((root.batt?.total_cycles ?? 0) + " " + root.t("bat_cycles", "cycles"))
                                    : ((root.batt?.count ?? 0) === 1
                                        ? ((root.batt?.total_pct ?? 0) + "% · " + ((root.batt?.ac?.online) ? root.t("bat_charging", "Charging") : root.t("bat_on_battery", "On battery"))
                                          + " · " + ((root.batt?.total_cycles ?? 0) + " " + root.t("bat_cycles", "cycles")))
                                        : ((root.batt?.ac?.online ?? true) ? root.t("bat_ac_online", "AC Mains Online") : root.t("bat_ac_active", "Direct Power Supply Active")))
                                color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            }

                            // Separador + chevron
                            Rectangle {
                                width: 1
                                height: 16
                                radius: 0.5
                                color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.15)
                            }

                            Text {
                                text: "󰅂"
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                            }
                            }

                            MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                            islandWin.controlSubView = 7
                            battProc.running = true
                            }
                            }
                            }
                        }

                        // Card de Perfil de Gráficos / GPU Switcher
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.gpuData.has_hybrid ? 136 : 64
                            radius: 14
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                // Cabecera: Icono, Título y GPU Activa
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 36; height: 36; radius: 18
                                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰢮"
                                            color: root.colAccent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 18
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.t("hypr_gpu_profile", "Graphics Profile")
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            text: root.gpuData.active_gpu || "Auto Graphics Detection"
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Rectangle {
                                        width: 28; height: 28; radius: 14
                                        color: gpuRefHover.containsMouse ? root.colSurfaceHover : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰑐"
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 13
                                        }
                                        MouseArea {
                                            id: gpuRefHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: gpuStatusProc.running = true
                                        }
                                    }
                                }

                                // 3 Botones de Selección (Solo para sistemas híbridos con dGPU + iGPU)
                                RowLayout {
                                    visible: root.gpuData.has_hybrid
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // Integrated (iGPU)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 38
                                        radius: 10
                                        color: root.gpuData.current_mode === "integrated" ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 4
                                                Text {
                                                    text: "󰌢"
                                                    color: root.gpuData.current_mode === "integrated" ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                }
                                                Text {
                                                    text: root.t("hypr_gpu_integrated", "Integrated")
                                                    color: root.gpuData.current_mode === "integrated" ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.t("hypr_gpu_igpu_only", "iGPU Only")
                                                color: root.gpuData.current_mode === "integrated" ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.runCmd("$HOME/.local/bin/gpu-profile set integrated")
                                                gpuRefreshTimer.restart()
                                            }
                                        }
                                    }

                                    // Hybrid (Auto)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 38
                                        radius: 10
                                        color: root.gpuData.current_mode === "hybrid" ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 4
                                                Text {
                                                    text: "⚡"
                                                    color: root.gpuData.current_mode === "hybrid" ? root.colBg : root.colFg
                                                    font.pixelSize: 10
                                                }
                                                Text {
                                                    text: root.t("hypr_gpu_hybrid", "Hybrid")
                                                    color: root.gpuData.current_mode === "hybrid" ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.t("hypr_gpu_prime_auto", "PRIME Auto")
                                                color: root.gpuData.current_mode === "hybrid" ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.runCmd("$HOME/.local/bin/gpu-profile set hybrid")
                                                gpuRefreshTimer.restart()
                                            }
                                        }
                                    }

                                    // Dedicated (dGPU)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 38
                                        radius: 10
                                        color: root.gpuData.current_mode === "dedicated" ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 1
                                            RowLayout {
                                                Layout.alignment: Qt.AlignHCenter
                                                spacing: 4
                                                Text {
                                                    text: "󰢮"
                                                    color: root.gpuData.current_mode === "dedicated" ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                }
                                                Text {
                                                    text: root.t("hypr_gpu_dedicated", "Dedicated")
                                                    color: root.gpuData.current_mode === "dedicated" ? root.colBg : root.colFg
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                }
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.t("hypr_gpu_dgpu_only", "dGPU Only")
                                                color: root.gpuData.current_mode === "dedicated" ? Qt.rgba(root.colBg.r, root.colBg.g, root.colBg.b, 0.8) : root.colMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.runCmd("$HOME/.local/bin/gpu-profile set dedicated")
                                                gpuRefreshTimer.restart()
                                            }
                                        }
                                    }
                                }

                                // Hardware chips footer
                                RowLayout {
                                    visible: root.gpuData.has_hybrid
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        text: "iGPU: " + (root.gpuData.igpu_name || "Integrated")
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "dGPU: " + (root.gpuData.dgpu_name || "Dedicated")
                                        color: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }

                        // Card de Estilo y Ventanas (Redondeo y Gaps)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 96
                            radius: 14
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                // Presets de Redondeo (Rounding)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: root.t("hypr_rounding", "Rounding:")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        Layout.preferredWidth: 80
                                    }

                                    Repeater {
                                        model: [
                                            { label: "Sharp (0px)", val: 0 },
                                            { label: "Normal (10px)", val: 10 },
                                            { label: "Curved (16px)", val: 16 }
                                        ]
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 30
                                            radius: 8
                                            color: root.hyprRounding === modelData.val ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: root.hyprRounding === modelData.val ? root.colBg : root.colFg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.hyprRounding = modelData.val
                                                    root.runCmd("$HOME/.local/bin/notch-hypr-helper set-rounding " + modelData.val)
                                                    hyprRefreshTimer.restart()
                                                }
                                            }
                                        }
                                    }
                                }

                                // Presets de Gaps (Espaciado)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: root.t("hypr_gaps", "Gaps:")
                                        color: root.colFg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        Layout.preferredWidth: 80
                                    }

                                    Repeater {
                                        model: [
                                            { label: "0px", val: 0 },
                                            { label: "6px", val: 6 },
                                            { label: "10px", val: 10 },
                                            { label: "16px", val: 16 }
                                        ]
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 30
                                            radius: 8
                                            color: root.hyprGaps === modelData.val ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: root.hyprGaps === modelData.val ? root.colBg : root.colFg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.hyprGaps = modelData.val
                                                    root.runCmd("$HOME/.local/bin/notch-hypr-helper set-gaps " + modelData.val)
                                                    hyprRefreshTimer.restart()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Android-Style System Update (OTA) Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 56
                            radius: 14
                            color: otaCardHover.containsMouse ? root.colSurfaceHover : root.colSurface
                            border.color: root.otaData.has_updates ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: root.otaData.has_updates ? 1.5 : 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                // Android OTA Icon Badge
                                Rectangle {
                                    width: 36; height: 36; radius: 18
                                    color: root.otaData.has_updates ? root.colAccent : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰚰"
                                        color: root.otaData.has_updates ? root.colBg : root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 18
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: root.t("ota_title", "System Update (OTA)")
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                        }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            visible: root.otaData.has_updates
                                            implicitWidth: otaPillText.implicitWidth + 14
                                            height: 18; radius: 9
                                            color: root.colAccent
                                            Text {
                                                id: otaPillText
                                                anchors.centerIn: parent
                                                text: root.t("ota_new", "New Update")
                                                color: root.colBg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }
                                    Text {
                                        text: root.otaData.has_updates ? root.otaData.status_text : ("Rhythm Hyprland " + (root.otaData.current_version || "v1.0.0") + " · Up to date")
                                        color: root.otaData.has_updates ? root.colAccent : root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Chevron
                                Text {
                                    text: "󰅂"
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }
                            }

                            MouseArea {
                                id: otaCardHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    islandWin.controlSubView = 4
                                    otaStatusProc.running = true
                                    otaChangelogProc.running = true
                                }
                            }
                        }


                        // Herramientas Hyprland
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 10; color: root.colSurface
                                RowLayout { anchors.centerIn: parent; spacing: 6
                                    Text { text: "󰕰"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.t("hypr_split", "Split Layout"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.runCmd("$HOME/.local/bin/notch-hypr-helper toggle-split") }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 36; radius: 10; color: root.colSurface
                                RowLayout { anchors.centerIn: parent; spacing: 6
                                    Text { text: "󰑐"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                    Text { text: root.t("hypr_reload", "Reload"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.runCmd("$HOME/.local/bin/notch-hypr-helper reload"); hyprRefreshTimer.restart(); } }
                            }
                        }
                        }

                    // ── SUBSECCIÓN: BATERIAS ──
                    // Un apartado entero dentro de la pestaña Hyprland: una tarjeta por bateria con
                    // sus datos y sus botones de limite. Se llega pulsando la tarjeta Batteries de
                    // la cuadrícula de arriba, y se vuelve con el boton Back.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: islandWin.currentTab === 1 && islandWin.controlSubView === 7
                        // 28 de cabecera + 116 por bateria + 8 de separacion + 44 del boton Back.
                        // Un Repeater no propaga el implicitHeight de sus delegates al layout padre,
                        // asi que el alto se declara aqui y no sale de calcularlo.
                        Layout.preferredHeight: (root.batt?.count ?? 0) > 0 ? (28 + root.batt.count * 116 + 8 + 44) : (28 + 100 + 8 + 44)

                        // Cabecera: total de todas las pilas y estado del cargador
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: (root.batt?.count ?? 0) > 0 ? "󰁹" : "󰚥"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                            Text { text: (root.batt?.count ?? 0) > 0 ? "Batteries" : "Power Source"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: (root.batt?.count ?? 0) > 1
                                text: (root.batt?.total_pct ?? 0) + "% total"
                                color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                            }
                            Text {
                                text: (root.batt?.count ?? 0) > 0 ? ((root.batt?.ac?.online) ? root.t("bat_charging", "Charging") : root.t("bat_on_battery", "On battery")) : ((root.batt?.ac?.online ?? true) ? root.t("bat_ac_online", "AC Mains Online") : root.t("bat_external_power", "External Power"))
                                color: (root.batt?.ac?.online ?? true) ? root.colAccent : root.colMuted
                                font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                            }
                        }

                        // Tarjeta para escritorio / corriente directa cuando no hay baterías
                        Rectangle {
                            visible: (root.batt?.count ?? 0) === 0
                            Layout.fillWidth: true
                            height: 100
                            radius: 12
                            color: root.colSurface
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6

                                RowLayout {
                                    spacing: 8
                                    Text { text: "󰚥"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18 }
                                    Text { text: root.t("bat_ac_active", "Direct Power Supply Active"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                                }
                                Text {
                                    text: (root.batt?.ac?.online ?? true)
                                        ? "AC Mains power connected. System is running continuously on wall power supply."
                                        : "External power supply active. No internal battery present."
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        Repeater {
                        model: root.batt?.devices ?? []

                        delegate: Rectangle {
                        id: battCardDel
                        // El limite y el nombre de la bateria pasan por propiedades CON TIPO.
                        // Leer modelData desde el delegate de dentro no es fiable: con el limite
                        // ningun boton se resaltaba, y al pulsar el nombre daba undefined y el
                        // comando se lanzaba contra una bateria inexistente.
                        readonly property int umbral: (modelData && modelData.threshold !== null && modelData.threshold !== undefined) ? modelData.threshold : 100
                        readonly property string batName: (modelData && modelData.name) ? modelData.name : ""
                        Layout.fillWidth: true
                        // 116 px: lo que ocupa la tarjeta con los datos y los botones de limite
                        // DENTRO. Con menos, los botones se salian de la tarjeta.
                        height: 116
                        radius: 12
                        color: root.colSurface
                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                        border.width: 1

                        ColumnLayout {
                        id: battCard
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                        text: modelData.icon
                        color: root.colAccent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        }
                        Text {
                        text: modelData.name + (modelData.model ? " · " + modelData.model : "")
                        color: root.colFg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        }
                        Text {
                        visible: modelData.remaining !== null && modelData.remaining !== undefined
                        text: modelData.remaining ?? ""
                        color: root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        }
                        Text {
                        text: modelData.state
                        color: root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        }
                        Text {
                        text: (modelData.capacity ?? 0) + "%"
                        color: root.colAccent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        }
                        }

                        Rectangle {
                        Layout.fillWidth: true
                        height: 4
                        radius: 2
                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                        Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, Math.min(parent.width, parent.width * ((modelData.capacity ?? 0) / 100.0)))
                        radius: 2
                        color: (modelData.capacity ?? 100) <= 15 ? "#e05c5c" : ((modelData.capacity ?? 100) <= 30 ? "#e0a75c" : root.colAccent)
                        Behavior on width { NumberAnimation { duration: 200 } }
                        }
                        Rectangle {
                        visible: battCardDel.umbral < 100
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: Math.max(0, Math.min(parent.width, parent.width * (battCardDel.umbral / 100.0)))
                        color: "transparent"
                        border.color: Qt.rgba(255, 255, 255, 0.35)
                        border.width: 1
                        radius: 2
                        }
                        }

                        Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        Row {
                        spacing: 3
                        visible: (modelData.power_w !== null && modelData.power_w !== undefined)
                        Text { text: root.t("bat_power", "Power"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        Text { text: (modelData.power_w ?? 0) + " W"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        }
                        Row {
                        spacing: 3
                        visible: (modelData.voltage !== null && modelData.voltage !== undefined)
                        Text { text: root.t("bat_volt", "Volt"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        Text {
                            // Sin toFixed sale "17.580000000000002 V": con una sola
                            // bateria el voltaje ya viene redondeado de sysfs y no se
                            // nota, pero con varias se ve el error de coma flotante.
                            text: (modelData.voltage ?? 0).toFixed(2) + " V"
                            color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9
                        }
                        }
                        Row {
                        spacing: 3
                        visible: (modelData.health !== null && modelData.health !== undefined)
                        Text { text: root.t("bat_health", "Health"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        Text { text: (modelData.health ?? 0) + "%"; color: (modelData.health ?? 100) >= 90 ? root.colFg : "#e0a75c"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        }
                        Row {
                        spacing: 3
                        visible: (modelData.energy_full !== null && modelData.energy_full !== undefined)
                        Text { text: root.t("bat_full", "Full"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        Text { text: (modelData.energy_full ?? 0) + " Wh"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        }
                        Row {
                        spacing: 3
                        visible: (modelData.cycles !== null && modelData.cycles !== undefined)
                        Text { text: root.t("bat_cycles", "Cycles"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        Text { text: "" + (modelData.cycles ?? 0); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        }
                        Row {
                        spacing: 3
                        visible: (modelData.threshold !== null && modelData.threshold !== undefined)
                        Text { text: root.t("bat_limit", "Limit"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        Text { text: (battCardDel.umbral) + "%"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                        }
                        }

                        // ── Limite de carga ──
                        // Un boton por valor, y cada uno escribe en el charge_control_end_threshold
                        // de SU bateria, no en el de al lado: el limite va por dispositivo. El valor
                        // puesto sale resaltado, y 100 es "sin limite" y se dice con palabras. Solo de
                        // 70 para arriba: por debajo el firmware de este portatil acepta el numero pero
                        // luego no lo respeta.
                        Row {
                        Layout.alignment: Qt.AlignRight
                        Layout.topMargin: 2
                        spacing: 6
                        Repeater {
                        model: [70, 80, 90, 100]
                        delegate: Rectangle {
                        id: limitBtn
                        readonly property int valor: modelData
                        readonly property bool puesto: valor === battCardDel.umbral
                        readonly property string texto: valor === 100 ? "Off" : valor + "%"
                        width: limitLabel.implicitWidth + 16
                        height: 22
                        radius: 11
                        color: puesto ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.06)
                        border.color: puesto ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                        id: limitLabel
                        anchors.centerIn: parent
                        text: limitBtn.texto
                        color: limitBtn.puesto ? root.colBg : root.colMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: limitBtn.puesto ? Font.Bold : Font.Normal
                        }
                        MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                        battLimitProc.command = ["bash", "-c",
                        "$HOME/.local/bin/battery-charge-limit " + limitBtn.valor + " " + battCardDel.batName + " 2>&1"]
                        battLimitProc.running = true
                        }
                        }
                        }
                        }
                        }

                        Text {
                        Layout.fillWidth: true
                        visible: root.battLimitMsg !== ""
                        text: root.battLimitMsg
                        color: root.battLimitMsg.indexOf(battCardDel.batName + " ") === 0 ? root.colAccent : "#e05c5c"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 8
                        elide: Text.ElideRight
                        }
                        }
                        }
                        }

                        // Boton de vuelta a la vista principal, como en los demas subapartados
                        // (WiFi, Bluetooth, audio).
                        Rectangle {
                            Layout.preferredWidth: 96
                            height: 32
                            radius: 16
                            color: root.colSurface
                            border.color: root.colBorder
                            border.width: 1

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "󰁍"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14 }
                                Text { text: root.t("notif_back", "Back"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { islandWin.controlSubView = 0 }
                            }
                        }
                    }

                    // ── TAB 2: ALERTS CENTER ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: islandWin.currentTab === 2
                        opacity: islandWin.tabFade

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                text: root.t("notif_title", "Notifications")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Rectangle {
                                height: 20
                                width: Math.max(20, tabUnreadLbl.implicitWidth + 12)
                                radius: 10
                                color: root.notifUnread > 0 ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                Text {
                                    id: tabUnreadLbl
                                    anchors.centerIn: parent
                                    text: root.notifUnread > 9 ? "9+" : root.notifUnread
                                    color: root.notifUnread > 0 ? root.colBg : root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                height: 32
                                width: 96
                                radius: 16
                                color: root.colSurface
                                border.color: root.colBorder
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: root.t("notif_clear", "Clear all")
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.notifClear()
                                }
                            }
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(470, Math.max(140, tabNotifCol.implicitHeight))
                            contentWidth: width
                            contentHeight: tabNotifCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: tabNotifCol
                                width: parent.width
                                spacing: 10

                                Repeater {
                                    model: root.notifHistory
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: tabNotifCardCol.implicitHeight + 24
                                        radius: 12
                                        color: root.colSurface
                                        border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                        border.width: 1

                                        ColumnLayout {
                                            id: tabNotifCardCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 12
                                            anchors.bottomMargin: 12
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                Text {
                                                    text: "󰂚"
                                                    color: root.colAccent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 12
                                                }
                                                Text {
                                                    text: modelData.app
                                                    color: root.colAccent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                    font.weight: Font.Bold
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: modelData.time
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                }
                                            }

                                            Text {
                                                visible: modelData.summary !== ""
                                                text: modelData.summary
                                                color: root.colFg
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                wrapMode: Text.Wrap
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                visible: modelData.body !== ""
                                                text: modelData.body
                                                color: root.colMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: root.t("notif_tap_open", "Tap to open app")
                                                color: root.colMuted
                                                opacity: 0.6
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 8
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.expanded = false
                                                root.runCmd("$HOME/.local/bin/open-notification-app '" + modelData.app + "'")
                                            }
                                        }
                                    }
                                }

                                // ── MUTED APPS ──
                                // Silenciar una app entera: sus notificaciones se
                                // descartan al llegar y ni aparecen aqui. La lista
                                // sale de las apps que ya han hablado mas las que
                                // estan silenciadas, para poder quitar el silencio
                                // sin esperar a que la app vuelva a notificar.
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: root.notifKnownApps().length > 0

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: "󰖔"
                                            color: root.mutedApps.length > 0 ? "#e0a75c" : root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: root.t("notif_muted_apps", "Muted apps")
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            visible: root.mutedApps.length > 0
                                            text: root.mutedApps.length + " active"
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Repeater {
                                            model: root.notifKnownApps()

                                            delegate: Rectangle {
                                                readonly property bool muteOn: root.notifMuted(modelData)

                                                height: 26
                                                width: muteLabel.implicitWidth + 26
                                                radius: 13
                                                color: muteOn ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.22) : root.colSurface
                                                border.color: muteOn ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    id: muteLabel
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 9
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: (parent.muteOn ? "󰖔 " : "󰂚 ") + modelData
                                                    color: parent.muteOn ? root.colFg : root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                    elide: Text.ElideRight
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        // El nombre se copia ANTES de tocar nada: al
                                                        // silenciar, notifKnownApps() cambia y el
                                                        // delegate se reconstruye, y después modelData
                                                        // ya no vale.
                                                        let app = modelData
                                                        root.notifToggleMute(app)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: root.mutedApps.length > 0
                                        text: root.t("notif_muted_desc", "Notifications from muted apps are discarded before they reach the list.")
                                        color: root.colMuted
                                        opacity: 0.65
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 8
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    visible: root.notifHistory.length === 0
                                    text: root.t("notif_empty", "No notifications yet.")
                                    color: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: 20
                                }
                            }
                        }
                    }



                    // ── TAB 3: PORTAPAPELES ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: islandWin.currentTab === 3
                        opacity: islandWin.tabFade

                        // ── PORTAPAPELES: opcion aparte dentro de Alertas ──
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                text: root.t("clip_title", "Clipboard")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Rectangle {
                                height: 20
                                width: 34
                                radius: 10
                                color: root.clipList.length > 0 ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.clipList.length > 9 ? "9+" : root.clipList.length
                                    color: root.clipList.length > 0 ? root.colBg : root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                height: 32
                                width: 110
                                radius: 16
                                color: root.colSurface
                                border.color: root.colBorder
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: root.t("clip_clear", "Clear all")
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.runCmd("cliphist wipe"); clipListProc.running = true }
                                }
                            }
                        }

Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(470, Math.max(140, tabClipCol.implicitHeight))
                            contentWidth: width
                            contentHeight: tabClipCol.implicitHeight
                            clip: true

                            ColumnLayout {
                                id: tabClipCol
                                width: parent.width
                                spacing: 8
                        Repeater {
                            model: root.clipList
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 48
                                radius: 12
                                color: modelData.id === root.clipCopiedId ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.25) : root.colSurface
                                border.color: modelData.id === root.clipCopiedId ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.05)
                                border.width: 1
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    Item {
                                        width: 26; height: 26
                                        Layout.alignment: Qt.AlignVCenter
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 13
                                            visible: !modelData.image
                                            color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰅍"
                                                color: root.colAccent
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 14
                                            }
                                        }
                                        Image {
                                            anchors.fill: parent
                                            visible: modelData.image
                                            source: modelData.image ? "file://" + modelData.thumb : ""
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            asynchronous: true
                                        }
                                    }
                                    ColumnLayout {
                                        spacing: 1
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        Text {
                                            text: modelData.title
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        // Al copiar, la propia fila lo dice: "Text copied" o
                                        // "Image pasted" en vez de su subtitulo, en color acento.
                                        Text {
                                            readonly property bool justCopied: modelData.id === root.clipCopiedId && root.clipToast !== ""
                                            text: justCopied ? root.clipToast : modelData.sub
                                            visible: justCopied || modelData.sub !== ""
                                            color: justCopied ? root.colAccent : root.colMuted
                                            font.weight: justCopied ? Font.Bold : Font.Normal
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runCmd("cliphist decode " + modelData.id + " | wl-copy")
                                        root.clipCopiedId = modelData.id
                                        root.clipToast = modelData.image ? "Image pasted" : "Text copied"
                                        clipCopyTimer.restart()
                                        clipListProc.running = true
                                    }
                                }
                            }
                        }

                    Timer {
                            id: clipCopyTimer
                            interval: 1500
                            repeat: false
                            onTriggered: { root.clipCopiedId = -1; root.clipToast = "" }
                        }
                        Timer {
                            interval: 5000
                            repeat: true
                            running: islandWin.currentTab === 3
                            triggeredOnStart: true
                            onTriggered: clipListProc.running = true
                        }

                        Text {
                            visible: root.clipList.length === 0
                            text: root.t("clip_empty", "Empty: copy something first")
                            color: root.colMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            Layout.alignment: Qt.AlignHCenter
                        }
                            }
                        }

                    }

                    // ── TAB 4: WORKSPACES OVERVIEW (Super + Tab) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: islandWin.currentTab === 4 && islandWin.controlSubView === 0
                        opacity: islandWin.tabFade

                        Timer {
                            id: wsProcRefreshTimer
                            interval: 200
                            repeat: false
                            onTriggered: workspacesProc.running = true
                        }

                        // Header Bar: Title, Active Pill, Add Space button, Refresh button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: "󰍹 " + root.t("ws_overview", "Workspaces Overview")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }

                            Rectangle {
                                height: 22
                                implicitWidth: wsActivePillText.implicitWidth + 14
                                radius: 11
                                color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.18)
                                border.color: root.colAccent
                                border.width: 1
                                Text {
                                    id: wsActivePillText
                                    anchors.centerIn: parent
                                    text: root.t("ws_space", "Space") + " " + (root.workspacesData?.active_id || 1) + " " + root.t("ws_active", "Active")
                                    color: root.colAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // + Add Space Button
                            Rectangle {
                                height: 30
                                implicitWidth: addWsRow.implicitWidth + 20
                                radius: 15
                                color: addWsMouse.containsMouse ? root.colAccentHover : root.colAccent
                                Behavior on color { ColorAnimation { duration: 150 } }

                                RowLayout {
                                    id: addWsRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "󰐕"
                                        color: root.colBg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        text: root.t("ws_add", "Add Space")
                                        color: root.colBg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: addWsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runCmd("$HOME/.local/bin/notch-workspaces-helper add")
                                        wsProcRefreshTimer.restart()
                                    }
                                }
                            }

                            // Refresh button
                            Rectangle {
                                width: 30; height: 30; radius: 15
                                color: wsRefMouse.containsMouse ? root.colSurfaceHover : root.colSurface
                                border.color: root.colBorder; border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑐"
                                    color: root.colFg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    id: wsRefMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!workspacesProc.running) workspacesProc.running = true
                                    }
                                }
                            }
                        }

                        // Workspaces Live Visual Strip (Apple macOS Spaces / Mission Control style)
                        Flickable {
                            id: wsFlickable
                            Layout.fillWidth: true
                            Layout.preferredHeight: 215
                            contentWidth: wsHorizontalRow.implicitWidth + 24
                            contentHeight: 215
                            flickableDirection: Flickable.HorizontalFlick
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            RowLayout {
                                id: wsHorizontalRow
                                spacing: 14
                                anchors.verticalCenter: parent.verticalCenter

                                Repeater {
                                    model: workspacesModel

                                    delegate: Rectangle {
                                        id: wsCard
                                        readonly property int cardWsId: model.id
                                        readonly property var cardClients: (root.workspacesData?.workspaces?.find(w => w.id === model.id)?.clients) || []
                                        width: 250
                                        height: 195
                                        radius: 14
                                        scale: cardHover.containsMouse ? 1.03 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        color: cardHover.containsMouse ? root.colSurfaceHover : root.colSurface
                                        border.color: model.is_active ? root.colAccent : (cardHover.containsMouse ? Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.25) : root.colBorder)
                                        border.width: model.is_active ? 2 : 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        MouseArea {
                                            id: cardHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                islandWin.expanded = false
                                                root.runCmd("$HOME/.local/bin/notch-workspaces-helper switch " + wsCard.cardWsId)
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 6

                                            // Card Top Badge Bar
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Rectangle {
                                                    height: 20
                                                    implicitWidth: spaceBadgeText.implicitWidth + 12
                                                    radius: 10
                                                    color: model.is_active ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.1)
                                                    Text {
                                                        id: spaceBadgeText
                                                        anchors.centerIn: parent
                                                        text: root.t("ws_space", "Space") + " " + model.id
                                                        color: model.is_active ? root.colBg : root.colFg
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                    }
                                                }

                                                Text {
                                                    text: model.monitor || ""
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 9
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Remove button (appears smoothly on hover)
                                                Rectangle {
                                                    width: 20; height: 20; radius: 10
                                                    opacity: (cardHover.containsMouse || closeWsHover.containsMouse) ? 1.0 : 0.0
                                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                                    color: closeWsHover.containsMouse ? "#ff5555" : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.15)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰅖"
                                                        color: closeWsHover.containsMouse ? "#ffffff" : root.colFg
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                    }

                                                    MouseArea {
                                                        id: closeWsHover
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            root.runCmd("$HOME/.local/bin/notch-workspaces-helper remove " + wsCard.cardWsId)
                                                            wsProcRefreshTimer.restart()
                                                        }
                                                    }
                                                }
                                            }

                                            // Desktop Miniature Preview (16:9 Viewport)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 125
                                                radius: 8
                                                clip: true
                                                color: "#12131a"
                                                border.color: model.is_active ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.12)
                                                border.width: 1

                                                // 1. Placeholder underneath (visible only if no windows or neither image loaded yet)
                                                Item {
                                                    anchors.fill: parent
                                                    visible: model.windows_count === 0 || (!imgA.isLoaded && !imgB.isLoaded)

                                                    ColumnLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 4

                                                        Text {
                                                            text: model.windows_count > 0 ? "󰍹" : "󰘔"
                                                            color: model.is_active ? root.colAccent : root.colMuted
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 20
                                                            Layout.alignment: Qt.AlignHCenter
                                                        }
                                                        Text {
                                                            text: model.windows_count > 0 ? (root.t("ws_space", "Space") + " " + model.id) : root.t("ws_empty", "Empty Space")
                                                            color: root.colFg
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 10
                                                            font.weight: Font.Bold
                                                            Layout.alignment: Qt.AlignHCenter
                                                        }
                                                    }
                                                }

                                                // 2. Full Desktop Preview - Zero Flicker Double Buffer
                                                Item {
                                                    id: previewContainer
                                                    anchors.fill: parent
                                                    visible: model.windows_count > 0 && model.preview !== ""

                                                    property string currentUrl: model.preview
                                                    onCurrentUrlChanged: {
                                                        if (currentUrl === "") return
                                                        let fileUrl = "file://" + currentUrl
                                                        if (imgA.isFront) {
                                                            imgB.source = fileUrl
                                                        } else {
                                                            imgA.source = fileUrl
                                                        }
                                                    }

                                                    Component.onCompleted: {
                                                        if (model.preview) {
                                                            imgA.source = "file://" + model.preview
                                                        }
                                                    }

                                                    Image {
                                                        id: imgA
                                                        anchors.fill: parent
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
                                                        asynchronous: true
                                                        cache: false
                                                        opacity: isFront ? 1.0 : 0.0
                                                        property bool isFront: true
                                                        property bool isLoaded: status === Image.Ready
                                                        onStatusChanged: {
                                                            if (status === Image.Ready) {
                                                                isLoaded = true
                                                                if (!isFront) {
                                                                    isFront = true
                                                                    imgB.isFront = false
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Image {
                                                        id: imgB
                                                        anchors.fill: parent
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
                                                        asynchronous: true
                                                        cache: false
                                                        opacity: isFront ? 1.0 : 0.0
                                                        property bool isFront: false
                                                        property bool isLoaded: status === Image.Ready
                                                        onStatusChanged: {
                                                            if (status === Image.Ready) {
                                                                isLoaded = true
                                                                if (!isFront) {
                                                                    isFront = true
                                                                    imgA.isFront = false
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Footer: Window chips
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4
                                                visible: wsCard.cardClients.length > 0

                                                Repeater {
                                                    model: wsCard.cardClients.slice(0, 3)

                                                    delegate: Rectangle {
                                                        height: 18
                                                        implicitWidth: Math.min(100, chipText.implicitWidth + 14)
                                                        radius: 9
                                                        color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)

                                                        RowLayout {
                                                            anchors.centerIn: parent
                                                            spacing: 3
                                                            Text {
                                                                text: modelData.icon || "󰘔"
                                                                color: root.colAccent
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 9
                                                            }
                                                            Text {
                                                                id: chipText
                                                                text: modelData.app_name || modelData.class
                                                                color: root.colFg
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 8
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    visible: wsCard.cardClients.length > 3
                                                    text: "+" + (wsCard.cardClients.length - 3)
                                                    color: root.colMuted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 8
                                                }
                                            }
                                        }
                                    }
                                }

                                // + Add Space Button Card at the end of the row (Apple macOS Spaces style)
                                Rectangle {
                                    id: addWsCard
                                    width: 120
                                    height: 195
                                    radius: 14
                                    scale: addCardHover.containsMouse ? 1.03 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    color: addCardHover.containsMouse ? root.colSurfaceHover : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.04)
                                    border.color: addCardHover.containsMouse ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.15)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Rectangle {
                                            width: 38; height: 38; radius: 19
                                            color: addCardHover.containsMouse ? root.colAccent : Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Layout.alignment: Qt.AlignHCenter

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰐕"
                                                color: addCardHover.containsMouse ? root.colBg : root.colAccent
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 18
                                                font.weight: Font.Bold
                                            }
                                        }

                                        Text {
                                            text: root.t("ws_add", "Add Space")
                                            color: root.colFg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: root.t("ws_space", "Space") + " " + (root.workspacesData?.next_id || "+")
                                            color: root.colMuted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }

                                    MouseArea {
                                        id: addCardHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.runCmd("$HOME/.local/bin/notch-workspaces-helper add")
                                            wsProcRefreshTimer.restart()
                                        }
                                    }
                                }
                            }
                        }

                        // Bottom Help Hint
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Layout.topMargin: 2

                            Text {
                                text: "󰌌 " + root.t("ws_footer", "Super + Tab toggles Overview • Click card to switch • 󰅖 removes space")
                                color: root.colMuted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    // ── 5. SUBSECCIÓN: NIGHT LIGHT ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: islandWin.controlSubView === 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                width: 100; height: 32; radius: 16
                                color: root.colSurface
                                border.color: root.colBorder; border.width: 1
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 6
                                    Text { text: "󰁍"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14 }
                                    Text { text: root.t("nl_back", "Back"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: islandWin.controlSubView = 0 }
                            }
                            Text {
                                text: root.t("nl_title", "Night Light")
                                color: root.colFg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: Qt.rgba(255, 255, 255, 0.08)
                                Text { anchors.centerIn: parent; text: "󰑐"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nightLightSettingsProc.running = true }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            radius: 14
                            color: root.colSurface
                            border.color: root.nightLightEnabled ? root.colAccent : root.colBorder
                            border.width: 1
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10
                                Rectangle {
                                    width: 38; height: 38; radius: 19
                                    color: root.nightLightEnabled ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.22) : root.colBg
                                    Text { anchors.centerIn: parent; text: "󰖔"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18 }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: root.nightLightEnabled ? root.t("nl_enabled", "Enabled") : root.t("nl_disabled", "Disabled"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                                    Text { text: root.nightLightEnabled ? root.t("nl_active_desc", "Blue-light filter is active") : root.t("nl_off_desc", "Blue-light filter is off"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                }
                                Item { Layout.fillWidth: true }
                                Rectangle {
                                    width: 68; height: 32; radius: 16
                                    color: root.nightLightEnabled ? root.colAccent : root.colSurface
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text { anchors.centerIn: parent; text: root.nightLightEnabled ? "ON" : "OFF"; color: root.nightLightEnabled ? root.colBg : root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.nightLightEnabled = !root.nightLightEnabled
                                            root.runCmd("~/.local/bin/toggle-nightlight " + (root.nightLightEnabled ? "on" : "off"))
                                            nightLightSettingsRefreshTimer.restart()
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 132
                            radius: 14
                            color: root.colSurface
                            border.color: root.colBorder; border.width: 1
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 12; spacing: 7
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: root.t("nl_temp", "Color temperature"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.nightLightTemperature + " K"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                                Slider {
                                    id: nightTemperatureSlider
                                    Layout.fillWidth: true
                                    from: 1800; to: 6500; stepSize: 100
                                    value: root.nightLightTemperature
                                    onMoved: {
                                        root.nightLightTemperature = Math.round(value / 100) * 100
                                        nightTemperatureApplyTimer.restart()
                                    }
                                    background: Rectangle {
                                        x: nightTemperatureSlider.leftPadding
                                        y: nightTemperatureSlider.topPadding + nightTemperatureSlider.availableHeight / 2 - height / 2
                                        width: nightTemperatureSlider.availableWidth; height: 5; radius: 3
                                        color: root.colBg
                                        Rectangle { width: nightTemperatureSlider.visualPosition * parent.width; height: parent.height; radius: 3; color: root.colAccent }
                                    }
                                    handle: Rectangle {
                                        x: nightTemperatureSlider.leftPadding + nightTemperatureSlider.visualPosition * (nightTemperatureSlider.availableWidth - width)
                                        y: nightTemperatureSlider.topPadding + nightTemperatureSlider.availableHeight / 2 - height / 2
                                        width: 18; height: 18; radius: 9
                                        color: root.colAccent; border.color: root.colFg; border.width: 1
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Repeater {
                                        model: [
                                            { label: root.t("nl_candle", "Candle"), value: 2200 },
                                            { label: root.t("nl_warm", "Warm"), value: 3000 },
                                            { label: root.t("nl_balanced", "Balanced"), value: 4500 },
                                            { label: root.t("nl_daylight", "Daylight"), value: 6000 }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true; height: 25; radius: 12
                                            color: root.nightLightTemperature === modelData.value ? root.colAccent : root.colBg
                                            Text { anchors.centerIn: parent; text: modelData.label; color: root.nightLightTemperature === modelData.value ? root.colBg : root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                                            MouseArea {
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.nightLightTemperature = modelData.value
                                                    root.runCmd("~/.local/bin/toggle-nightlight temperature " + modelData.value)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text { text: root.t("nl_temp_desc", "Lower values are warmer; higher values look more neutral."); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8 }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 118
                            radius: 14
                            color: root.colSurface
                            border.color: root.colBorder; border.width: 1
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 12; spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: root.t("nl_gamma", "Display gamma"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.nightLightGamma + "%"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                                Slider {
                                    id: nightGammaSlider
                                    Layout.fillWidth: true
                                    from: 20; to: 100; stepSize: 5
                                    value: root.nightLightGamma
                                    onMoved: {
                                        root.nightLightGamma = Math.round(value / 5) * 5
                                        nightGammaApplyTimer.restart()
                                    }
                                    background: Rectangle {
                                        x: nightGammaSlider.leftPadding
                                        y: nightGammaSlider.topPadding + nightGammaSlider.availableHeight / 2 - height / 2
                                        width: nightGammaSlider.availableWidth; height: 5; radius: 3
                                        color: root.colBg
                                        Rectangle { width: nightGammaSlider.visualPosition * parent.width; height: parent.height; radius: 3; color: root.colAccent }
                                    }
                                    handle: Rectangle {
                                        x: nightGammaSlider.leftPadding + nightGammaSlider.visualPosition * (nightGammaSlider.availableWidth - width)
                                        y: nightGammaSlider.topPadding + nightGammaSlider.availableHeight / 2 - height / 2
                                        width: 18; height: 18; radius: 9
                                        color: root.colAccent; border.color: root.colFg; border.width: 1
                                    }
                                }
                                Text { text: root.t("nl_gamma_desc", "Lower gamma dims the image; 100% is normal brightness."); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8 }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 170
                            radius: 14
                            color: root.colSurface
                            border.color: root.nightLightScheduleEnabled ? root.colAccent : root.colBorder
                            border.width: 1
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 7
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: root.t("nl_schedule", "Automatic schedule"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.nightLightScheduleEnabled ? root.t("nl_enabled", "Enabled") : root.t("nl_optional_off", "Optional · Off"); color: root.nightLightScheduleEnabled ? root.colAccent : root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text { text: root.t("nl_start", "Start"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                    TextField {
                                        id: nightScheduleStartInput
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        maximumLength: 5
                                        placeholderText: "HH:MM"
                                        text: islandWin.nightScheduleStartText
                                        color: root.colFg
                                        placeholderTextColor: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        horizontalAlignment: TextInput.AlignHCenter
                                        onTextEdited: islandWin.nightScheduleStartText = text
                                        background: Rectangle { radius: 8; color: root.colBg; border.color: root.colBorder; border.width: 1 }
                                    }
                                    Text { text: root.t("nl_end", "End"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                    TextField {
                                        id: nightScheduleEndInput
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        maximumLength: 5
                                        placeholderText: "HH:MM"
                                        text: islandWin.nightScheduleEndText
                                        color: root.colFg
                                        placeholderTextColor: root.colMuted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                        horizontalAlignment: TextInput.AlignHCenter
                                        onTextEdited: islandWin.nightScheduleEndText = text
                                        background: Rectangle { radius: 8; color: root.colBg; border.color: root.colBorder; border.width: 1 }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: islandWin.nightScheduleValidation || root.t("nl_schedule_hint", "Off by default. Set both times (24-hour HH:MM) to enable.")
                                    color: islandWin.nightScheduleValidation ? root.colAccent : root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 30; radius: 15
                                        color: root.colAccent
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.nightLightScheduleEnabled ? root.t("nl_schedule_update", "Update schedule") : root.t("nl_schedule_enable", "Enable schedule")
                                            color: root.colBg
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const start = islandWin.nightScheduleStartText.trim()
                                                const end = islandWin.nightScheduleEndText.trim()
                                                const valid = /^([01][0-9]|2[0-3]):[0-5][0-9]$/
                                                if (!valid.test(start) || !valid.test(end) || start === end) {
                                                    islandWin.nightScheduleValidation = "Enter different valid start and end times."
                                                    return
                                                }
                                                root.nightLightScheduleStart = start
                                                root.nightLightScheduleEnd = end
                                                islandWin.nightScheduleValidation = "Schedule saved. Night Light follows this time window."
                                                root.runCmd("~/.local/bin/toggle-nightlight schedule on " + start + " " + end)
                                                nightLightSettingsRefreshTimer.restart()
                                            }
                                        }
                                    }
                                    Rectangle {
                                        width: 78; height: 30; radius: 15
                                        color: root.colBg
                                        border.color: root.colBorder; border.width: 1
                                        opacity: root.nightLightScheduleEnabled ? 1 : 0.45
                                        Text { anchors.centerIn: parent; text: root.t("nl_disable", "Disable"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: root.nightLightScheduleEnabled
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.nightLightScheduleEnabled = false
                                                islandWin.nightScheduleValidation = "Automatic schedule disabled."
                                                root.runCmd("~/.local/bin/toggle-nightlight schedule off")
                                                nightLightSettingsRefreshTimer.restart()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.fillWidth: true; height: 34; radius: 17
                                color: root.colSurface; border.color: root.colBorder; border.width: 1
                                Text { anchors.centerIn: parent; text: root.t("nl_reset", "Reset defaults · 4500 K · 100%"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.nightLightTemperature = 4500
                                        root.nightLightGamma = 100
                                        root.runCmd("~/.local/bin/toggle-nightlight reset")
                                    }
                                }
                            }
                        }
                    }
                    // ── SUBSECCIÓN: BLUETOOTH PAIRING REQUEST ──
                    // BlueZ entrega la solicitud al agente registrado, no al
                    // servidor de notificaciones: bluetooth-pair-agent la
                    // reenvia aqui para que la confirme el usuario.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: islandWin.controlSubView === 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                width: 100; height: 32; radius: 16
                                color: root.colSurface
                                border.color: root.colBorder; border.width: 1
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 6
                                    Text { text: "󰁍"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14 }
                                    Text { text: root.t("pair_back", "Back"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.pairRequest.active && root.pairRequest.state === "pending") root.answerPairing("reject")
                                        islandWin.controlSubView = 0
                                    }
                                }
                            }
                            Text {
                                text: root.t("pair_title", "Pairing Request")
                                color: root.colFg; font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13; font.weight: Font.Bold
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 68; height: 32; radius: 16
                                color: root.colSurface
                                border.color: root.colBorder; border.width: 1
                                visible: root.pairRequest.active
                                Text {
                                    anchors.centerIn: parent
                                    text: root.pairRequest.state === "pending" ? root.t("pair_waiting", "Waiting") : (root.pairRequest.state === "accepted" ? root.t("pair_done", "Done") : root.t("pair_closed", "Closed"))
                                    color: root.pairRequest.state === "accepted" ? root.colAccent : root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9; font.weight: Font.Bold
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 232
                            radius: 14
                            color: root.colSurface
                            border.color: root.pairRequest.active ? root.colAccent : root.colBorder
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 180 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        width: 38; height: 38; radius: 19
                                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.18)
                                        Text { anchors.centerIn: parent; text: "󰂯"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18 }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: root.pairRequest.name
                                            color: root.colFg; font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12; font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: root.pairRequest.device
                                            color: root.colMuted; font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 9
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: root.colBorder
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.pairRequest.kind === "pin" ? root.t("pair_pin", "Enter the PIN") : (root.pairRequest.kind === "authorize" ? root.t("pair_auth", "Authorization") : root.t("pair_code", "Confirmation code"))
                                    color: root.colMuted; font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9; font.weight: Font.Bold
                                }

                                // Numeric comparison: the code is split in pairs
                                // so it can be read digit by digit.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: root.pairRequest.kind !== "pin" && root.pairRequest.passkey !== ""
                                    Repeater {
                                        model: {
                                            let digits = (root.pairRequest.passkey || "").split("")
                                            let grouped = []
                                            for (let i = 0; i < digits.length; i += 2) grouped.push(digits[i] + (digits[i + 1] || ""))
                                            return grouped
                                        }
                                        delegate: Rectangle {
                                            required property int index
                                            required property string modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 40
                                            radius: 10
                                            color: root.colBg
                                            border.color: root.colBorder; border.width: 1
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData
                                                color: root.colAccent; font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 18; font.weight: Font.Bold
                                            }
                                        }
                                    }
                                }

                                TextField {
                                    id: pairPinInput
                                    Layout.fillWidth: true
                                    visible: root.pairRequest.kind === "pin"
                                    implicitHeight: 34
                                    maximumLength: 8
                                    echoMode: TextInput.PasswordEchoOnEdit
                                    placeholderText: "PIN"
                                    text: root.pairRequest.pin
                                    color: root.colFg
                                    placeholderTextColor: root.colMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                    horizontalAlignment: TextInput.AlignHCenter
                                    onTextEdited: root.pairRequest = Object.assign({}, root.pairRequest, { pin: text })
                                    background: Rectangle { radius: 10; color: root.colBg; border.color: root.colBorder; border.width: 1 }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.pairRequest.hint
                                    color: root.colMuted; font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    wrapMode: Text.WordWrap
                                }

                                Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 32; radius: 16
                                        color: root.colSurface
                                        border.color: root.colBorder; border.width: 1
                                        opacity: root.pairRequest.state === "pending" ? 1 : 0.45
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.t("pair_reject", "Reject")
                                            color: root.colFg; font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10; font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            enabled: root.pairRequest.state === "pending"
                                            onClicked: root.answerPairing("reject")
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 32; radius: 16
                                        color: root.colAccent
                                        opacity: root.pairRequest.state === "pending"
                                                && (root.pairRequest.kind !== "pin" || root.pairRequest.pin.length > 0) ? 1 : 0.45
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.t("pair_confirm", "Confirm")
                                            color: root.colBg; font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 10; font.weight: Font.Bold
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            enabled: root.pairRequest.state === "pending"
                                                    && (root.pairRequest.kind !== "pin" || root.pairRequest.pin.length > 0)
                                            onClicked: root.answerPairing("accept")
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.pairRequest.active
                            text: root.t("pair_none", "No pending pairing request.")
                            color: root.colMuted; font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }

                    // ── SUBSECCIÓN: SYSTEM UPDATE (OTA - ANDROID STYLE) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: islandWin.controlSubView === 4

                        // Sub-header with back button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Rectangle {
                                width: 100; height: 32; radius: 16
                                color: root.colSurface
                                border.color: root.colBorder; border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent; spacing: 6
                                    Text { text: "󰁍"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14 }
                                    Text { text: root.t("ota_back", "Back"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: islandWin.controlSubView = 0
                                }
                            }

                            Text {
                                text: root.t("ota_title", "System Update")
                                color: root.colFg; font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13; font.weight: Font.Bold
                            }

                            Item { Layout.fillWidth: true }

                            // GitHub Releases Button
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: ghBtnHover.containsMouse ? root.colSurfaceHover : Qt.rgba(255, 255, 255, 0.08)
                                border.color: ghBtnHover.containsMouse ? root.colAccent : "transparent"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: ""
                                    color: ghBtnHover.containsMouse ? root.colAccent : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
                                }
                                MouseArea {
                                    id: ghBtnHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { islandWin.expanded = false; root.runCmd("xdg-open https://github.com/rhythmcreative/hyprland/releases") }
                                }
                            }

                            // Check / Refresh Button
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: checkBtnHover.containsMouse ? root.colSurfaceHover : Qt.rgba(255, 255, 255, 0.08)
                                border.color: checkBtnHover.containsMouse ? root.colAccent : "transparent"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: "󰑐"
                                    color: checkBtnHover.containsMouse ? root.colAccent : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14
                                    RotationAnimation on rotation {
                                        running: root.otaChecking; loops: Animation.Infinite
                                        from: 0; to: 360; duration: 800
                                    }
                                }
                                MouseArea {
                                    id: checkBtnHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (!root.otaChecking) { root.otaChecking = true; otaCheckProc.running = true } }
                                }
                            }

                            // Terminal GUI Button (Terminal Console Icon)
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: termBtnHover.containsMouse ? root.colSurfaceHover : Qt.rgba(255, 255, 255, 0.08)
                                border.color: termBtnHover.containsMouse ? root.colAccent : "transparent"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: "󰆍"
                                    color: termBtnHover.containsMouse ? root.colAccent : root.colFg
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14
                                }
                                MouseArea {
                                    id: termBtnHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { islandWin.expanded = false; root.runCmd("kitty -e system-ota gui") }
                                }
                            }
                        }

                        // Android 15 Status Hero Card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 118
                            radius: 16
                            color: root.colSurface
                            border.color: root.otaData.has_updates ? root.colAccent : Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08)
                            border.width: 1

                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 6

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 48; height: 48; radius: 24
                                    color: root.otaData.has_updates ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.2) : Qt.rgba(76/255, 175/255, 80/255, 0.2)
                                    border.color: root.otaData.has_updates ? root.colAccent : "#4CAF50"
                                    border.width: 2

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.otaData.has_updates ? "󰚰" : "󰄬"
                                        color: root.otaData.has_updates ? root.colAccent : "#4CAF50"
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 22
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.otaData.has_updates ? root.t("ota_available", "System Update Available") : root.t("ota_uptodate", "System is Up to Date")
                                    color: root.colFg; font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13; font.weight: Font.Bold
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.otaData.has_updates ? root.otaData.status_text : ("Rhythm Hyprland " + (root.otaData.current_version || "v1.0.0") + " · " + root.t("ota_last_checked", "Last checked:") + " " + (root.otaData.last_checked || root.t("ota_recently", "Recently")))
                                    color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10
                                }
                            }
                        }

                        // System Release & Specs Grid
                        GridLayout {
                            Layout.fillWidth: true; columns: 2; rowSpacing: 6; columnSpacing: 6

                            Rectangle {
                                Layout.fillWidth: true; height: 42; radius: 10; color: root.colSurface
                                RowLayout { anchors.fill: parent; anchors.margins: 8; spacing: 8
                                    Text { text: "󰓅"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
                                    ColumnLayout { spacing: 1
                                        Text { text: root.t("ota_current", "Current Version"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        Text { text: (root.otaData.current_version || "v1.0.0") + " (" + (root.otaData.dotfiles_hash || "git") + ")"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 42; radius: 10; color: root.colSurface
                                RowLayout { anchors.fill: parent; anchors.margins: 8; spacing: 8
                                    Text { text: "󰑐"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
                                    ColumnLayout { spacing: 1
                                        Text { text: root.t("ota_target", "Target Release"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        Text { text: (root.otaData.latest_version && root.otaData.latest_version !== root.otaData.current_version) ? (root.otaData.latest_version + " (New)") : (root.otaData.current_version + " (Latest)"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 42; radius: 10; color: root.colSurface
                                RowLayout { anchors.fill: parent; anchors.margins: 8; spacing: 8
                                    Text { text: "󰌽"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
                                    ColumnLayout { spacing: 1
                                        Text { text: root.t("ota_kernel", "Linux Kernel"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        Text { text: root.otaData.kernel || "Arch Linux"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 42; radius: 10; color: root.colSurface
                                RowLayout { anchors.fill: parent; anchors.margins: 8; spacing: 8
                                    Text { text: "󰘬"; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15 }
                                    ColumnLayout { spacing: 1
                                        Text { text: root.t("ota_channel", "Release Channel"); color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        Text { text: (root.otaData.dotfiles_branch || "main") + " · " + (root.otaData.has_updates ? (root.otaData.dotfiles_behind + " " + root.t("ota_behind", "behind")) : root.t("ota_uptodate", "Up to date")); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }
                        }

                        // Changelog Preview Card
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 110
                            radius: 12; color: root.colSurface; clip: true
                            border.color: Qt.rgba(root.colFg.r, root.colFg.g, root.colFg.b, 0.08); border.width: 1

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 10; spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: root.t("ota_changelog", "Changelog & History"); color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        height: 20; radius: 10
                                        width: ghChipText.implicitWidth + 24
                                        color: ghChipHover.containsMouse ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.25) : Qt.rgba(255, 255, 255, 0.06)
                                        RowLayout {
                                            anchors.centerIn: parent; spacing: 4
                                            Text { text: ""; color: root.colAccent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 }
                                            Text { id: ghChipText; text: root.otaData.current_version || "Releases"; color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                                        }
                                        MouseArea {
                                            id: ghChipHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { islandWin.expanded = false; root.runCmd("xdg-open https://github.com/rhythmcreative/hyprland/releases") }
                                        }
                                    }
                                }

                                Flickable {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    contentWidth: width; contentHeight: changelogDisplayText.implicitHeight; clip: true

                                    Text {
                                        id: changelogDisplayText
                                        width: parent.width
                                        text: root.otaChangelogText || root.t("ota_loading_changelog", "Loading changelog...")
                                        color: root.colMuted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9; wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }

                        // OTA Action Footer
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10

                            Rectangle {
                                Layout.fillWidth: true; height: 40; radius: 20
                                color: checkOtaHover.containsMouse ? root.colSurfaceHover : root.colSurface
                                border.color: root.colBorder; border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text {
                                        text: "󰑐"; color: root.colAccent
                                        font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14
                                        RotationAnimation on rotation {
                                            running: root.otaChecking; loops: Animation.Infinite; from: 0; to: 360; duration: 800
                                        }
                                    }
                                    Text {
                                        text: root.otaChecking ? root.t("ota_checking", "Checking...") : root.t("ota_check", "Check for update")
                                        color: root.colFg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    id: checkOtaHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (!root.otaChecking) { root.otaChecking = true; otaCheckProc.running = true } }
                                }
                            }

                            Rectangle {
                                visible: root.otaData.has_updates || root.otaUpdating
                                Layout.fillWidth: true; height: 40; radius: 20
                                color: root.otaUpdating ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.6) : root.colAccent
                                Behavior on color { ColorAnimation { duration: 200 } }

                                RowLayout {
                                    anchors.centerIn: parent; spacing: 8
                                    Text {
                                        text: root.otaUpdating ? "󱑑" : "󰀚"
                                        color: root.colBg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
                                    }
                                    Text {
                                        text: root.otaUpdating ? root.t("ota_installing", "Installing...") : root.t("ota_install", "Download & Install")
                                        color: root.colBg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    enabled: !root.otaUpdating
                                    onClicked: { root.otaUpdating = true; otaUpdateProc.running = true }
                                }
                            }
                        }
                    }



                }
            }
        }
    }
}
}
}
