// Agent Awake — menu-bar control for the lid-close hold. SwiftUI popover, SF Symbols, native
// light/dark. Same engine underneath: ~/.local/bin/agent-awake and the Claude Code hooks.
import SwiftUI
import Carbon

let awake = NSString(string: "~/.local/bin/agent-awake").expandingTildeInPath
let sleepNow = NSString(string: "~/.local/bin/sleep-now").expandingTildeInPath
let disabledFlag = NSString(string: "~/.config/agent-awake/disabled").expandingTildeInPath
let activeDir = "/tmp/agent-awake.active"
let loginPlist = NSString(string: "~/Library/LaunchAgents/com.automyte.agent-awake-menu.plist").expandingTildeInPath
let loginOff = loginPlist + ".disabled"
let hotkeyLabel = "⌃⌥A"
let allowOnBatteryFlag = NSString(string: "~/.config/agent-awake/allow-on-battery").expandingTildeInPath
let awakeLog = NSString(string: "~/.local/state/agent-awake/agent-awake.log").expandingTildeInPath
let projectsDir = NSString(string: "~/.claude/projects").expandingTildeInPath
func clock12(_ d: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "h:mm a"; return f.string(from: d) }
func countdown(_ d: Date) -> String { let s = max(0, Int(d.timeIntervalSinceNow)); return s >= 3600 ? "\(s/3600)h \((s%3600)/60)m" : "\(s/60)m \(s%60)s" }
struct Event: Identifiable { let id = UUID(); let time: String; let text: String; let symbol: String }
struct Hog: Identifiable { let id: Int32; let name: String; let detail: String; let cpu: Double; let killable: Bool }
let systemNames: Set<String> = ["kernel_task","WindowServer","launchd","loginwindow","coreaudiod","mds","mds_stores","mdworker","mdworker_shared","powerd","bluetoothd","wifid","Dock","Finder","SystemUIServer","ControlCenter","NotificationCenter","top","AgentAwake","com.apple.Virtua","Virtualization"]
/// What a process IS, in plain words, from evidence: its command line, the folder it runs in,
/// the ports it listens on, and who started it. Returns (label, where-and-origin).
func friendly(_ pid: Int32) -> (String, String) {
    let (_, cmdRaw) = run(["/bin/ps", "-o", "command=", "-p", String(pid)])
    let cmd = cmdRaw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cmd.isEmpty else { return ("", "") }
    let parts = cmd.split(separator: " ").map(String.init)
    let exe = (parts.first! as NSString).lastPathComponent
    let home = NSHomeDirectory()
    // --- where: working directory, shown relative to home
    var folder = ""
    let (_, lsofCwd) = run(["/usr/sbin/lsof", "-a", "-p", String(pid), "-d", "cwd", "-Fn"])
    if let n = lsofCwd.split(separator: "\n").first(where: { $0.hasPrefix("n/") }) {
        var f = String(n.dropFirst()); if f.hasPrefix(home) { f = "~" + f.dropFirst(home.count) }
        if f != "~" && f != "/" { folder = f }
    }
    // --- ports it serves
    var ports: [String] = []
    let (_, lsofPorts) = run(["/usr/sbin/lsof", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-P", "-Fn"])
    for l in lsofPorts.split(separator: "\n") where l.hasPrefix("n") { if let colon = l.lastIndex(of: ":") { let port = String(l[l.index(after: colon)...]); if !ports.contains(port) { ports.append(port) } } }
    // --- who started it: climb parents, keep the most telling names
    var origin: [String] = []; var pp = pid
    for _ in 0..<6 {
        let (_, ppidS) = run(["/bin/ps", "-o", "ppid=", "-p", String(pp)])
        guard let ppid = Int32(ppidS.trimmingCharacters(in: .whitespacesAndNewlines)), ppid > 1 else { if pp != pid { origin.append("launchd") }; break }
        let (_, pcmd) = run(["/bin/ps", "-o", "command=", "-p", String(ppid)])
        let pc = pcmd.trimmingCharacters(in: .whitespacesAndNewlines); var pname = ((pc.split(separator: " ").first.map(String.init) ?? "") as NSString).lastPathComponent
        if pname.hasPrefix("-") { pname = String(pname.dropFirst()) }
        if pname == "tmux" { if let r = pc.range(of: "-s ") { let rest = pc[r.upperBound...]; origin.append("tmux “" + rest.split(separator: " ").first.map(String.init)! + "”") } else { origin.append("tmux") } }
        else if pname.hasSuffix(".sh") || pc.contains(".sh ") { let sh = pc.split(separator: " ").first(where: { $0.hasSuffix(".sh") }).map { ($0 as NSString).lastPathComponent } ?? pname; origin.append(sh) }
        else if pname == "claude" { origin.append("a Claude Code session") }
        else if pname == "codex" { origin.append("Codex") }
        else if !["zsh","bash","sh","login","python","python3","node","perl"].contains(where: { pname.hasPrefix($0) }) && !pname.isEmpty { origin.append(pname) }
        pp = ppid
    }
    // --- what it is
    let low = cmd.lowercased(); var label = exe
    func has(_ k: String) -> Bool { low.contains(k) }
    let macosNames: [String: String] = ["suggestd": "Siri suggestions (macOS)", "spotlightknowledged": "Spotlight learning (macOS)", "mds": "Spotlight indexing (macOS)", "mds_stores": "Spotlight indexing (macOS)", "mdworker": "Spotlight indexing (macOS)", "mdworker_shared": "Spotlight indexing (macOS)", "photoanalysisd": "Photos analysis (macOS)", "photolibraryd": "Photos library (macOS)", "com.apple.WebKit.WebContent": "a web page (Safari or an app's browser view)", "WindowServer": "Screen drawing (macOS)", "coreaudiod": "Audio (macOS)", "kernel_task": "macOS kernel", "bird": "iCloud Drive sync (macOS)", "cloudd": "iCloud sync (macOS)", "backupd": "Time Machine (macOS)", "softwareupdated": "Software Update (macOS)", "trustd": "Certificates (macOS)", "syspolicyd": "Gatekeeper (macOS)", "corespotlightd": "Spotlight (macOS)", "sharingd": "AirDrop / Handoff (macOS)", "mediaanalysisd": "Media analysis (macOS)"]
    let isSystemPath = parts.first!.hasPrefix("/System/") || parts.first!.hasPrefix("/usr/libexec/") || parts.first!.hasPrefix("/usr/sbin/") || low.contains("/system/library/")
    if let nice = macosNames[exe] { return (nice, "macOS, not yours to quit") }
    if isSystemPath && !["caffeinate"].contains(exe) { return (exe + " (macOS)", "macOS, not yours to quit") }
    if exe == "caffeinate" { label = "caffeinate — keeping the Mac awake" }
    else if exe == "claude" { label = "Claude Code session" }
    else if exe == "codex" { label = "Codex session" }
    else if has("hermes_cli") || has("hermes-agent") { label = "Hermes (room manager)" }
    else if exe == "ollama" || has("ollama") { label = "Ollama (local AI models)" }
    else if has("com.apple.virtualization") { label = "Linux VM (container runtime)" }
    else if has("uvicorn") || has("gunicorn") || has("fastapi") || has("flask") { let mod = parts.first(where: { $0.contains(":app") || $0.contains("_api") || $0.contains(".main") }) ?? ""; label = "API server" + (mod.isEmpty ? "" : " · " + mod.replacingOccurrences(of: ":app", with: "")) }
    else if has("/mcp") || has("mcp-server") || has("-mcp") || has("mcp ") { let name = parts.first(where: { $0.contains("mcp") }).map { ($0 as NSString).lastPathComponent } ?? "mcp"; label = "MCP server · " + name.replacingOccurrences(of: "-mcp", with: "").replacingOccurrences(of: "mcp-", with: "") }
    else if has("vite") || has("next dev") || has("astro dev") || has("webpack") { label = "Dev server (" + (has("vite") ? "vite" : (has("next") ? "next" : "astro")) + ")" }
    else if has("agentawake") { label = "Agent Awake" }
    else if exe.hasPrefix("python") || exe == "node" || exe == "ruby" {
        if let i = parts.firstIndex(of: "-m"), parts.count > i + 1 { label = exe + " · " + parts[i + 1] } else if parts.count > 1 { label = exe + " · " + (parts[1] as NSString).lastPathComponent }
    }
    if !ports.isEmpty { label += " · port " + ports.prefix(2).joined(separator: ", ") }
    var where_ = folder.isEmpty ? "" : "in " + folder
    if !origin.isEmpty { where_ += (where_.isEmpty ? "" : " · ") + "started by " + origin.prefix(2).joined(separator: " → ") }
    return (label, where_)
}

func topHogs() -> [Hog] {
    // Two samples: the first is a lifetime average and useless, the second is "now".
    let (_, out) = run(["/usr/bin/top", "-l", "2", "-s", "1", "-n", "8", "-o", "cpu", "-stats", "pid,cpu,command"])
    guard let last = out.components(separatedBy: "PID").last else { return [] }
    var hogs: [Hog] = []
    for line in last.split(separator: "\n").dropFirst() {
        let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard cols.count >= 3, let pid = Int32(cols[0]), let cpu = Double(cols[1]) else { continue }
        if cpu < 3 { continue }
        let comm = cols[2...].joined(separator: " ")
        if pid == 0 { continue }   // kernel_task: not a thing anyone can quit
        var (name, detail) = friendly(pid)
        if name.isEmpty { name = comm; detail = "" }   // already gone, or not ours to inspect
        if detail.hasPrefix("macOS") { hogs.append(Hog(id: pid, name: name, detail: "", cpu: cpu, killable: false)); if hogs.count == 5 { break }; continue }
        let killable = !systemNames.contains(where: { comm.hasPrefix($0) || name.hasPrefix($0) }) && pid != ProcessInfo.processInfo.processIdentifier && !detail.isEmpty || (!systemNames.contains(where: { comm.hasPrefix($0) }) && kill(pid, 0) == 0 && !name.isEmpty && pid != ProcessInfo.processInfo.processIdentifier)
        hogs.append(Hog(id: pid, name: name, detail: detail, cpu: cpu, killable: killable))
        if hogs.count == 5 { break }
    }
    return hogs
}
func sleepBlockers() -> [String] {
    let (_, out) = run(["/usr/bin/pmset", "-g", "assertions"])
    var names: [String] = []
    for line in out.split(separator: "\n") where line.contains("PreventUserIdleSystemSleep named") || line.contains("PreventSystemSleep named") {
        let l = String(line)
        guard let a = l.range(of: "("), let b = l.range(of: ")") , a.upperBound < b.lowerBound else { continue }
        let proc = String(l[a.upperBound..<b.lowerBound])
        if ["powerd","coreaudiod","WindowServer","sharingd","bluetoothd","hidd"].contains(proc) { continue }
        if !names.contains(proc) { names.append(proc) }
    }
    return names
}
func quitProcess(_ pid: Int32) -> String {
    kill(pid, SIGTERM); usleep(1_500_000)
    if kill(pid, 0) == 0 { kill(pid, SIGKILL); usleep(300_000) }
    return kill(pid, 0) == 0 ? "still running" : "stopped"
}

@discardableResult
func run(_ args: [String], env: [String: String] = [:]) -> (Int32, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: args[0]); p.arguments = Array(args.dropFirst())
    var e = ProcessInfo.processInfo.environment
    e["PATH"] = (e["PATH"] ?? "") + ":/usr/bin:/bin:/usr/sbin:/sbin:" + NSString(string: "~/.local/bin").expandingTildeInPath
    env.forEach { e[$0] = $1 }; p.environment = e
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    do { try p.run() } catch { return (127, "\(error)") }
    p.waitUntilExit()
    return (p.terminationStatus, String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
}

enum Mode { case holding, normal, off, orphaned }

final class Model: ObservableObject {
    @Published var mode: Mode = .normal
    @Published var battery = 0
    @Published var charging = false
    @Published var sessions = 0
    @Published var deadline: Date? = nil
    @Published var watcher = ""
    @Published var busy = false
    @Published var launchAtLogin = false
    @Published var showHelp = false
    @Published var hogs: [Hog] = []
    @Published var blockers: [String] = []
    @Published var showHogs = false
    @Published var confirmPid: Int32? = nil
    @Published var pluggedInOnly = true
    @Published var sessionNames: [String] = []
    @Published var events: [Event] = []

    private var refreshing = false
    /// Shell work off the main thread; publish on it. The popover never hitches on `status`.
    func refresh() {
        if Thread.isMainThread {
            if refreshing { return }; refreshing = true
            DispatchQueue.global(qos: .userInitiated).async { self.refresh(); DispatchQueue.main.async { self.refreshing = false } }
            return
        }
        let snapshot = Model.gather()
        DispatchQueue.main.async { self.apply(snapshot) }
    }
    struct Snapshot { var mode: Mode; var battery: Int; var charging: Bool; var watcher: String; var deadline: Date?; var sessions: Int; var launchAtLogin: Bool; var pluggedInOnly: Bool; var sessionNames: [String]; var events: [Event]; var hogs: [Hog]; var blockers: [String] }
    func apply(_ s: Snapshot) {
        mode = s.mode; battery = s.battery; charging = s.charging; watcher = s.watcher; deadline = s.deadline; sessions = s.sessions
        launchAtLogin = s.launchAtLogin; pluggedInOnly = s.pluggedInOnly; sessionNames = s.sessionNames; events = s.events
        hogs = s.hogs; blockers = s.blockers
        if hogs.contains(where: { $0.cpu >= 25 }) { showHogs = true }
    }
    static func gather() -> Snapshot {
        let m = Model(); m.gatherInto(); return Snapshot(mode: m.mode, battery: m.battery, charging: m.charging, watcher: m.watcher, deadline: m.deadline, sessions: m.sessions, launchAtLogin: m.launchAtLogin, pluggedInOnly: m.pluggedInOnly, sessionNames: m.sessionNames, events: m.events, hogs: m.hogs, blockers: m.blockers)
    }
    func quit(_ pid: Int32) {
        if confirmPid != pid { confirmPid = pid; DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if self.confirmPid == pid { self.confirmPid = nil } }; return }
        confirmPid = nil; busy = true
        DispatchQueue.global().async { _ = quitProcess(pid); DispatchQueue.main.async { self.refresh(); self.busy = false } }
    }
    func gatherInto() {
        let (_, o) = run([awake, "status"])
        let off = FileManager.default.fileExists(atPath: disabledFlag)
        mode = off ? .off : o.contains("ORPHANED") ? .orphaned : o.contains("HOLDING") ? .holding : .normal
        if let m = o.range(of: #"battery: (\d+)%"#, options: .regularExpression) {
            battery = Int(o[m].filter(\.isNumber)) ?? 0
        }
        charging = o.contains("(charging)")
        if let m = o.range(of: #"watcher pid (\d+)"#, options: .regularExpression) {
            watcher = String(o[m].filter(\.isNumber))
            let (_, ps) = run(["/bin/ps", "-o", "command=", "-p", watcher])
            let parts = ps.split(separator: " ")
            if let i = parts.firstIndex(of: "__guard"), parts.count > i + 1, let epoch = Double(parts[i + 1]), epoch > 0 {
                deadline = Date(timeIntervalSince1970: epoch)
            } else { deadline = nil }
        } else { watcher = ""; deadline = nil }
        sessions = (try? FileManager.default.contentsOfDirectory(atPath: activeDir).filter { !$0.hasPrefix(".") }.count) ?? 0
        launchAtLogin = FileManager.default.fileExists(atPath: loginPlist)
        pluggedInOnly = !FileManager.default.fileExists(atPath: allowOnBatteryFlag)
        hogs = topHogs(); blockers = sleepBlockers()
        sessionNames = ((try? FileManager.default.contentsOfDirectory(atPath: activeDir)) ?? []).filter { !$0.hasPrefix(".") }.map(projectName)
        events = recentEvents()
    }
    func setPluggedInOnly(_ on: Bool) {
        let fm = FileManager.default
        if on { try? fm.removeItem(atPath: allowOnBatteryFlag) }
        else { try? fm.createDirectory(atPath: (allowOnBatteryFlag as NSString).deletingLastPathComponent, withIntermediateDirectories: true); fm.createFile(atPath: allowOnBatteryFlag, contents: nil) }
        refresh()
    }
    /// A session id -> the project folder its transcript lives under, e.g. "College/Classes".
    func projectName(_ sid: String) -> String {
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: projectsDir) else { return sid.prefix(8).description }
        for d in dirs where FileManager.default.fileExists(atPath: "\(projectsDir)/\(d)/\(sid).jsonl") {
            let homePrefix = NSHomeDirectory().replacingOccurrences(of: "/", with: "-")
            var n = d; if n.hasPrefix(homePrefix) { n = String(n.dropFirst(homePrefix.count)) }
            n = n.trimmingCharacters(in: CharacterSet(charactersIn: "-")).replacingOccurrences(of: "-", with: "/")
            return n.isEmpty ? "Home" : n
        }
        return sid.prefix(8).description
    }
    /// The hold's own log, last few lines, in plain words and a 12-hour clock.
    func recentEvents() -> [Event] {
        guard let raw = try? String(contentsOfFile: awakeLog, encoding: .utf8) else { return [] }
        let inFmt = DateFormatter(); inFmt.locale = Locale(identifier: "en_US_POSIX"); inFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out: [Event] = []
        for line in raw.split(separator: "\n").reversed() {
            let l = String(line); guard l.count > 20 else { continue }
            let stamp = String(l.prefix(19)); let msg = String(l.dropFirst(20))
            if msg.hasPrefix("no owner") || msg.hasPrefix("superseding") || msg.hasPrefix("owner:") || msg.hasPrefix("(dry run") || msg.hasPrefix("(test)") { continue }
            let t = inFmt.date(from: stamp).map(clock12) ?? stamp.suffix(8).description
            let (text, sym): (String, String)
            if msg.hasPrefix("held") { (text, sym) = ("Kept awake" + (msg.range(of: #"battery \d+%"#, options: .regularExpression).map { " (" + msg[$0] + ")" } ?? ""), "cup.and.saucer") }
            else if msg.contains("Claude finished") { (text, sym) = ("Let it sleep — Claude finished", "checkmark.circle") }
            else if msg.hasPrefix("released") { (text, sym) = ("Let it sleep", "moon") }
            else if msg.hasPrefix("refused") { (text, sym) = ("Didn't hold — " + msg.dropFirst("refused: ".count).replacingOccurrences(of: "plugged-in-only is on", with: "“only while plugged in” is on"), "hand.raised") }
            else if msg.contains("critical") { (text, sym) = ("Battery almost empty — put the Mac to sleep", "battery.0percent") }
            else if msg.contains("floor") { (text, sym) = ("Let it sleep — battery low", "battery.25percent") }
            else if msg.hasPrefix("stopping") { (text, sym) = ("You turned it off", "hand.raised") }
            else if msg.contains("deadline") { (text, sym) = ("Let it sleep — time was up", "timer") }
            else if msg.contains("idle") { (text, sym) = ("Let it sleep — nothing was running", "zzz") }
            else if msg.contains("unplugged") { (text, sym) = ("Let it sleep — you unplugged it", "powerplug") }
            else { (text, sym) = (msg, "circle") }
            out.append(Event(time: t, text: text, symbol: sym))
            if out.count == 5 { break }
        }
        return out
    }
    func setLaunchAtLogin(_ on: Bool) {
        let fm = FileManager.default
        if on, fm.fileExists(atPath: loginOff) { try? fm.moveItem(atPath: loginOff, toPath: loginPlist) }
        if !on, fm.fileExists(atPath: loginPlist) { try? fm.moveItem(atPath: loginPlist, toPath: loginOff) }
        refresh()
    }
    func act(_ args: [String], env: [String: String] = [:]) {
        busy = true
        DispatchQueue.global().async {
            run(args, env: env)
            DispatchQueue.main.async { self.refresh(); self.busy = false }
        }
    }
    var onBatteryBlocked: Bool { pluggedInOnly && !charging && mode != .holding }
    func holdUntilDone() { act([awake, "start", "--no-owner", "--minutes", "240"]) }
    func holdAnyway() { act([awake, "start", "--no-owner", "--minutes", "240", "--force-battery"]) }
    func holdTwoHours() { act([awake, "start", "--no-owner", "--minutes", "120"], env: ["AGENT_AWAKE_REGARDLESS": "1"]) }
    func release() { act([awake, "stop"]) }
    func sleepMac() { act([sleepNow]) }
    func setAutomatic(_ on: Bool) {
        let fm = FileManager.default
        if on { try? fm.removeItem(atPath: disabledFlag) }
        else {
            try? fm.createDirectory(atPath: (disabledFlag as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: disabledFlag, contents: nil)
            act([awake, "stop"]); return
        }
        refresh()
    }
}

struct ContentView: View {
    @ObservedObject var model: Model
    var tint: Color { switch model.mode { case .holding: return .green; case .normal: return .secondary; case .off: return .blue; case .orphaned: return .orange } }
    var symbol: String { switch model.mode { case .holding: return "cup.and.saucer.fill"; case .normal: return "moon.fill"; case .off: return "moon.zzz.fill"; case .orphaned: return "exclamationmark.triangle.fill" } }
    var title: String { switch model.mode { case .holding: return "Keeping the Mac awake"; case .normal: return "Not keeping it awake"; case .off: return "Turned off"; case .orphaned: return "Something's stuck" } }
    var subtitle: String {
        switch model.mode {
        case .holding:
            var s = model.sessions > 0 ? "Claude is working in \(model.sessions) project\(model.sessions == 1 ? "" : "s"). The lid won't put it to sleep." : "Waiting for Claude to start working."
            if let d = model.deadline { s += " Stops by \(clock12(d)) at the latest." }
            return s
        case .normal: return "Close the lid and the Mac sleeps, like any laptop."
        case .off: return "Nothing happens on its own. The Mac sleeps like normal."
        case .orphaned: return "Sleep is blocked but nothing is in charge of it. Click “Let it sleep”."
        }
    }
    var batterySymbol: String {
        if model.charging { return "battery.100percent.bolt" }
        switch model.battery { case 0..<15: return "battery.0percent"; case 15..<40: return "battery.25percent"; case 40..<65: return "battery.50percent"; case 65..<90: return "battery.75percent"; default: return "battery.100percent" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.title3, design: .rounded).weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if model.mode == .holding && !model.sessionNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(model.sessionNames.prefix(3), id: \.self) { n in
                        Text(n).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(tint.opacity(0.12))).foregroundStyle(tint)
                    }
                    if model.sessionNames.count > 3 { Text("+\(model.sessionNames.count - 3)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            HStack(spacing: 8) {
                Label("\(model.battery)%", systemImage: batterySymbol)
                    .foregroundStyle(model.battery <= 25 && !model.charging ? .red : .secondary)
                if model.charging { Text("Charging").foregroundStyle(.secondary) }
                Spacer()
                if model.mode == .holding, let d = model.deadline {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Label(countdown(d), systemImage: "timer").foregroundStyle(.secondary).monospacedDigit()
                    }
                } else if model.mode == .holding && !model.watcher.isEmpty {
                    Label("Watcher ok", systemImage: "checkmark.shield").foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            if !model.hogs.isEmpty || !model.blockers.isEmpty {
                let hot = model.hogs.first.map { $0.cpu >= 25 } ?? false
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: { model.showHogs.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: hot ? "flame.fill" : "gauge.with.dots.needle.33percent").foregroundStyle(hot ? .orange : .secondary)
                            Text(hot ? "Something is eating the battery" : "Using the battery").font(.callout.weight(.medium))
                            Spacer()
                            if let h = model.hogs.first { Text("\(h.name.prefix(22)) \(Int(h.cpu))%").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Image(systemName: model.showHogs ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }.buttonStyle(.plain)
                    if model.showHogs {
                        ForEach(model.hogs) { h in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(h.name).font(.caption.weight(.medium)).lineLimit(1)
                                    if !h.detail.isEmpty { Text(h.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text("\(Int(h.cpu))%").font(.caption).monospacedDigit().foregroundStyle(h.cpu >= 25 ? .orange : .secondary)
                                if h.killable {
                                    Button(model.confirmPid == h.id ? "Sure?" : "Quit") { model.quit(h.id) }
                                        .buttonStyle(.bordered).controlSize(.mini).tint(model.confirmPid == h.id ? .red : .accentColor)
                                } else { Text("system").font(.caption2).foregroundStyle(.tertiary) }
                            }
                        }
                        if !model.blockers.isEmpty {
                            Text("Keeping the Mac from idling: " + model.blockers.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text("CPU right now, not an average. Quit asks once, then stops the process.").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(hot ? Color.orange.opacity(0.12) : Color.primary.opacity(0.05)))
            }
            if model.onBatteryBlocked && model.mode != .off {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bolt.slash").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're on battery, so it won't stay awake").font(.callout.weight(.medium))
                        Text("Plug in, or turn off “Only while plugged in” below. You can also override it once; it will still sleep at 10% to save the battery.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            VStack(spacing: 8) {
                if model.onBatteryBlocked && model.mode != .off {
                    Button(action: model.holdAnyway) { Label("Keep awake on battery anyway", systemImage: "cup.and.saucer").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(.orange)
                } else if model.mode == .holding || model.mode == .orphaned {
                    Button(action: model.release) { Label("Let it sleep", systemImage: "moon").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(tint == .secondary ? .accentColor : tint)
                } else {
                    Button(action: model.holdUntilDone) { Label("Keep awake while Claude works", systemImage: "cup.and.saucer").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                HStack(spacing: 8) {
                    Button(action: model.holdTwoHours) { Label("2 hours", systemImage: "timer").frame(maxWidth: .infinity) }
                        .disabled(model.onBatteryBlocked)
                    Button(action: model.sleepMac) { Label("Sleep now", systemImage: "powersleep").frame(maxWidth: .infinity) }
                }.buttonStyle(.bordered).controlSize(.regular)
            }
            .disabled(model.busy)

            Divider()
            Toggle(isOn: Binding(get: { model.mode != .off }, set: { model.setAutomatic($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Automatic").font(.callout.weight(.medium))
                    Text("Turns on by itself when Claude is working, off when it's done").font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)

            Toggle(isOn: Binding(get: { model.pluggedInOnly }, set: { model.setPluggedInOnly($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Only while plugged in").font(.callout.weight(.medium))
                    Text("Never on battery, so it can't drain it overnight").font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
            Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                Text("Start when I log in").font(.callout.weight(.medium))
            }.toggleStyle(.switch).controlSize(.small)

            if !model.events.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("What happened").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(model.events) { ev in
                        HStack(spacing: 6) {
                            Image(systemName: ev.symbol).font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                            Text(ev.time).font(.caption2).monospacedDigit().foregroundStyle(.tertiary).frame(width: 56, alignment: .leading)
                            Text(ev.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            if model.showHelp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Macs sleep when you close the lid. Agent Awake keeps yours awake only while Claude is working, then lets it sleep like normal. It never stops you sleeping it yourself.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Label("awake", systemImage: "cup.and.saucer.fill"); Label("normal", systemImage: "moon"); Label("off", systemImage: "moon.zzz"); Label("stuck", systemImage: "exclamationmark.triangle.fill")
                    }.font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }
            HStack {
                Button(action: { model.showHelp.toggle() }) { Image(systemName: "questionmark.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).help("What is this?")
                Text("Agent Awake").font(.caption2).foregroundStyle(.tertiary)
                Text("·").font(.caption2).foregroundStyle(.tertiary)
                Text("\(hotkeyLabel) opens this").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

final class HotKeyBox { let handler: () -> Void; init(_ h: @escaping () -> Void) { handler = h } }
var hotKeyRef: EventHotKeyRef?
func installHotKey(_ handler: @escaping () -> Void) {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let box = Unmanaged.passRetained(HotKeyBox(handler)).toOpaque()
    InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
        Unmanaged<HotKeyBox>.fromOpaque(userData!).takeUnretainedValue().handler(); return noErr
    }, 1, &spec, box, nil)
    let id = EventHotKeyID(signature: 0x41574B45, id: 1)   // 'AWKE'
    RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    let popover = NSPopover()
    let model = Model()
    var hosting: NSHostingController<ContentView>!
    /// Size the popover from the content BEFORE it shows, and cap it to the screen. NSPopover
    /// keeps its bottom edge when content grows after presentation, so a taller Recent list
    /// pushed the top off the screen (2026-10-21).
    func fitPopover() {
        hosting.view.layoutSubtreeIfNeeded()
        let want = hosting.view.fittingSize
        let screen = item.button?.window?.screen ?? NSScreen.main
        let maxH = (screen?.visibleFrame.height ?? 800) - 24
        let size = NSSize(width: 320, height: min(max(want.height, 200), maxH))
        if popover.contentSize != size { popover.contentSize = size }
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        if ProcessInfo.processInfo.environment["AGENT_AWAKE_SELFTEST"] == "1" { FileHandle.standardError.write("selftest: launched\n".data(using: .utf8)!) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self; item.button?.action = #selector(toggle)
        hosting = NSHostingController(rootView: ContentView(model: model))
        popover.contentViewController = hosting
        popover.behavior = .transient; popover.animates = true
        model.refresh(); updateIcon(); fitPopover()
        installHotKey { [weak self] in self?.toggle() }
        // AGENT_AWAKE_SELFTEST=1: drive the button the way AppKit does for a real click, then exit.
        // AX "click" on a status item and CGEvent from an untrusted helper both proved unusable.
        if ProcessInfo.processInfo.environment["AGENT_AWAKE_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let b = self.item.button
                FileHandle.standardError.write("selftest: button=\(b != nil) target=\(String(describing: b?.target)) action=\(String(describing: b?.action)) enabled=\(b?.isEnabled ?? false) window=\(b?.window != nil)\n".data(using: .utf8)!)
                b?.performClick(nil)
                let after1 = FileManager.default.fileExists(atPath: "/tmp/agent-awake-menu.last-toggle")
                FileHandle.standardError.write("selftest: performClick fired=\(after1)\n".data(using: .utf8)!)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let scr = NSScreen.main?.frame ?? .zero
                    if let w = self.popover.contentViewController?.view.window {
                        let f = w.frame
                        let inside = f.minY >= scr.minY && f.maxY <= scr.maxY
                        FileHandle.standardError.write("selftest: popover frame y=\(Int(f.minY))..\(Int(f.maxY)) h=\(Int(f.height)) screen h=\(Int(scr.height)) contentSize=\(Int(self.popover.contentSize.height)) fitting=\(Int(self.hosting.view.fittingSize.height)) INSIDE_SCREEN=\(inside)\n".data(using: .utf8)!)
                    } else { FileHandle.standardError.write("selftest: popover has no window\n".data(using: .utf8)!) }
                    exit(0)
                }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in self.model.refresh(); self.updateIcon(); if self.popover.isShown { self.fitPopover() } }
    }
    func updateIcon() {
        let name: String
        switch model.mode { case .holding: name = "cup.and.saucer.fill"; case .normal: name = "moon"; case .off: name = "moon.zzz"; case .orphaned: name = "exclamationmark.triangle.fill" }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Agent Awake")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = "Agent Awake — " + (model.mode == .holding ? "staying awake" : model.mode == .off ? "off" : "normal sleep")
    }
    @objc func toggle() {
        // Observable from a script: a transient popover cannot be seen by screenshots or System Events.
        try? "\(Date().timeIntervalSince1970)".write(toFile: "/tmp/agent-awake-menu.last-toggle", atomically: true, encoding: .utf8)
        guard let b = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        model.refresh(); updateIcon(); fitPopover()
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        // Content can still settle a frame later (SwiftUI lays out lazily); re-fit once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.fitPopover() }
    }
}

// --snapshot <png> [holding|normal|off|orphaned]: render the popover offscreen and exit. The
// only reliable way to look at the UI from a script — a transient popover closes before a
// screenshot can catch it.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--quit", let qp = Int32(CommandLine.arguments[2]) {
    print("quit \(qp): \(quitProcess(qp))"); exit(0)   // the same path the button uses
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--describe", let dp = Int32(CommandLine.arguments[2]) {
    let (l, w) = friendly(dp); print("\(dp)\t\(l)\t\(w)"); exit(0)
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--hogs" {
    let napp = NSApplication.shared; napp.setActivationPolicy(.prohibited); napp.finishLaunching()
    for h in topHogs() { print("\(h.id)\t\(Int(h.cpu))%\t\(h.killable ? "quit" : "system")\t\(h.name)\t\(h.detail)") }
    print("blockers: \(sleepBlockers().joined(separator: ", "))"); exit(0)
}
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--icon" {
    // --icon out.png <symbol> [size] : the status-bar glyph as a PNG, for documentation.
    let napp = NSApplication.shared; napp.setActivationPolicy(.prohibited); napp.finishLaunching()
    let size = CGFloat(Double(CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "88") ?? 88)
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.72, weight: .medium)
    let img = NSImage(systemSymbolName: CommandLine.arguments[3], accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: (size - img.size.width) / 2, y: (size - img.size.height) / 2, width: img.size.width, height: img.size.height)
    NSColor.white.set(); img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    // tint: draw white through the glyph as a mask
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[2])); print("icon \(CommandLine.arguments[3]) -> \(CommandLine.arguments[2])"); exit(0)
}
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--snapshot" {
    // AppKit must exist before any view is built; without this the hosting view blocks forever.
    let napp = NSApplication.shared; napp.setActivationPolicy(.prohibited); napp.finishLaunching()
    let m = Model(); m.gatherInto()
    if CommandLine.arguments.count >= 4 {
        switch CommandLine.arguments[3] { case "holding": m.mode = .holding; m.sessions = 2; m.sessionNames = ["College/Classes", "Brain/memory"]; m.deadline = Date().addingTimeInterval(7200); m.watcher = "1"
        case "off": m.mode = .off; case "orphaned": m.mode = .orphaned
        case "battery": m.mode = .normal; m.charging = false; m.battery = 96; m.pluggedInOnly = true
        case "hogs": m.mode = .normal; m.charging = false; m.battery = 41; m.showHogs = true
            m.hogs = [Hog(id: 60623, name: "API server · aegra_api.main · port 5002", detail: "in ~/Hackathon/templates/template-agent · started by up.sh → tmux “hack”", cpu: 84, killable: true), Hog(id: 72338, name: "Linux VM (container runtime)", detail: "", cpu: 5, killable: false), Hog(id: 419, name: "Screen drawing (macOS)", detail: "", cpu: 4, killable: false)]
            m.blockers = ["caffeinate"]
        default: m.mode = .normal }
    }
    let host = NSHostingView(rootView: ContentView(model: m))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: host.fittingSize.height)
    host.layoutSubtreeIfNeeded()
    if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("snapshot \(Int(host.bounds.width))x\(Int(host.bounds.height)) -> \(CommandLine.arguments[2])")
    }
    exit(0)
}

if ProcessInfo.processInfo.environment["AGENT_AWAKE_SELFTEST"] == "1" { FileHandle.standardError.write("selftest: main\n".data(using: .utf8)!) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
