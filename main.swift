// ShiftPlayhead — 로직 12.4에서 고장 난 "트랙 영역 빈 곳 Shift-클릭 → 재생헤드 이동"을 대신 해 주는 메뉴바 앱.
// 빈 곳 Shift-클릭을 붙잡아, 같은 가로 위치의 눈금자 클릭으로 바꿔 보낸다. Shift-드래그(영역 선택)는 그대로 둔다.
import AppKit
import ApplicationServices
import Darwin

let logicBundleID = "com.apple.logic10"
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ShiftPlayhead.log")

func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    // 1MB가 넘으면 새로 시작 (끝없이 커지지 않게)
    if let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 1_000_000 {
        try? FileManager.default.removeItem(at: logURL)
    }
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - AX 도우미

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String { (attr(e, name) as? String) ?? "" }
/// 값이 진짜 AX 요소일 때만 돌려준다 (억지 변환으로 앱이 죽지 않게).
func axElement(_ v: AnyObject?) -> AXUIElement? {
    guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
}
func parent(_ e: AXUIElement) -> AXUIElement? { axElement(attr(e, kAXParentAttribute)) }
func axValue(_ v: AnyObject?) -> AXValue? {
    guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    return (v as! AXValue)
}
func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = axValue(attr(e, kAXPositionAttribute)), let s = axValue(attr(e, kAXSizeAttribute)) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    guard AXValueGetValue(p, .cgPoint, &pt), AXValueGetValue(s, .cgSize, &sz) else { return nil }
    return CGRect(origin: pt, size: sz)
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func describe(_ e: AXUIElement) -> String {
    let f = frame(e).map { "[\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))]" } ?? "[?]"
    return "\(str(e, kAXRoleAttribute))/\(str(e, kAXSubroleAttribute)) d=\"\(str(e, kAXDescriptionAttribute))\" t=\"\(str(e, kAXTitleAttribute))\" id=\"\(str(e, kAXIdentifierAttribute))\" \(f)"
}

/// 클릭을 붙잡은 채 로직에 물어보므로, 로직이 멈춰 있으면 맥 전체 마우스가 같이 멈춘다.
/// → 대답을 0.2초까지만 기다린다 (기본은 6초).
let axTimeout: Float = 0.2
let systemWide: AXUIElement = {
    let e = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(e, axTimeout)
    return e
}()

func element(at p: CGPoint) -> AXUIElement? {
    var el: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success, let el else { return nil }
    AXUIElementSetMessagingTimeout(el, axTimeout)
    return el
}

func logChain(at p: CGPoint, label: String) {
    guard var e = element(at: p) else { log("\(label) @\(p): 요소 없음"); return }
    var lines = ["\(label) @\(Int(p.x)),\(Int(p.y))"]
    for depth in 0..<12 {
        lines.append(String(repeating: "  ", count: depth) + describe(e))
        guard let up = parent(e) else { break }
        e = up
    }
    log(lines.joined(separator: "\n"))
}

func dumpLogicWindow() {
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == logicBundleID }) else { log("로직이 안 켜져 있음"); return }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    guard let win = axElement(attr(ax, kAXMainWindowAttribute)) else { log("로직 창 없음"); return }
    var lines: [String] = ["== 로직 창 구조 =="]
    func walk(_ e: AXUIElement, _ d: Int) {
        if d > 9 || lines.count > 3000 { return }
        lines.append(String(repeating: "  ", count: d) + describe(e))
        for c in children(e) { walk(c, d + 1) }
    }
    walk(win, 0)
    log(lines.joined(separator: "\n"))
}

// MARK: - 빈 곳 / 눈금자 찾기

/// 클릭한 곳이 트랙 영역의 빈 배경이면, 그 위 눈금자에서 클릭할 지점을 돌려준다. 아니면 nil.
/// 눈금자 찾기에 쓸 수 있는 시간. 넘기면 포기하고 원래 클릭을 그대로 보낸다.
var searchDeadline = Date.distantFuture

func rulerPoint(forBackgroundClickAt p: CGPoint, logicPID: pid_t) -> CGPoint? {
    searchDeadline = Date().addingTimeInterval(0.3)
    var pid: pid_t = 0
    guard let hit = element(at: p), AXUIElementGetPid(hit, &pid) == .success, pid == logicPID,   // 위에 뜬 다른 앱 창이면 무시
          str(hit, kAXRoleAttribute) == "AXLayoutArea",
          let g = parent(hit), str(g, kAXRoleAttribute) == "AXGroup",
          let sa = parent(g), str(sa, kAXRoleAttribute) == "AXScrollArea",
          let saFrame = frame(sa) else { return nil }
    // 스크롤 영역 바로 위에 붙어 있는 낮은 AXLayoutArea = 눈금자. 위로 올라가며 찾는다.
    var anc = sa
    for _ in 0..<5 {
        guard let up = parent(anc) else { break }
        anc = up
        if let r = findRuler(in: anc, above: saFrame, depth: 0) {
            return CGPoint(x: p.x, y: r.minY + r.height * 0.75)
        }
    }
    return nil
}

func findRuler(in e: AXUIElement, above sa: CGRect, depth: Int) -> CGRect? {
    if depth > 4 || Date() > searchDeadline { return nil }
    for c in children(e) {
        if str(c, kAXRoleAttribute) == "AXLayoutArea", let f = frame(c),
           f.height < 70, abs(f.maxY - sa.minY) < 4, abs(f.minX - sa.minX) < 4 { return f }
        if let r = findRuler(in: c, above: sa, depth: depth + 1) { return r }
    }
    return nil
}

// MARK: - 이벤트 탭

let myTag: Int64 = 0x5348_4950   // 우리가 보낸 이벤트 표시 ("SHIP")
var tap: CFMachPort?
var enabled = true
var pendingDown: CGEvent?        // 붙잡아 둔 Shift-클릭 (드래그로 바뀌면 그대로 돌려보낸다)
var pendingRuler: CGPoint?

/// 로직이 맨 앞이면 그 프로세스 번호, 아니면 nil.
func frontLogicPID() -> pid_t? {
    guard let a = NSWorkspace.shared.frontmostApplication, a.bundleIdentifier == logicBundleID else { return nil }
    return a.processIdentifier
}

/// 우리가 보내는 이벤트의 출처. 기본값이면 보낸 뒤 0.25초 동안 실제 마우스 움직임을 막아서
/// 재생헤드를 옮긴 직후 커서가 버벅인다 → 막는 시간을 0으로.
let eventSource: CGEventSource? = {
    let src = CGEventSource(stateID: .combinedSessionState)
    src?.localEventsSuppressionInterval = 0
    src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
                                                     state: .eventSuppressionStateSuppressionInterval)
    src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
                                                     state: .eventSuppressionStateRemoteMouseDrag)
    return src
}()

func post(_ type: CGEventType, at p: CGPoint) {
    guard let e = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
    e.flags = []
    e.setIntegerValueField(.eventSourceUserData, value: myTag)
    e.post(tap: .cghidEventTap)
}

/// 워프 뒤 0.25초 동안 실제 마우스 입력을 막는 맥 기본값을 0으로 (공개 API가 없어 직접 찾아 부른다).
let setSuppression: (@convention(c) (Double) -> Int32)? = {
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSetLocalEventsSuppressionInterval") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Double) -> Int32).self)
}()

func cursorNow() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

/// 눈금자를 클릭하고 커서를 원래 자리로 돌려놓는다.
/// 클릭 뒤에 "원래 자리로 이동" 이벤트를 이어 보내면 화면의 커서는 돌아오지만, 맥이 기억하는
/// 실제 마우스 위치는 눈금자에 남아 다음 움직임에서 커서가 위로 튄다.
/// → 잠시 뒤 지금 커서 자리로 워프해 둘을 맞춘다. 워프 뒤 입력 막힘은 0초로 꺼 둔다.
func clickRuler(_ r: CGPoint, returnTo back: CGPoint) {
    post(.mouseMoved, at: r)
    post(.leftMouseDown, at: r)
    post(.leftMouseUp, at: r)
    post(.mouseMoved, at: back)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
        var c = cursorNow()
        if hypot(c.x - r.x, c.y - r.y) < 40 { c = back }   // 아직 눈금자에 있으면 원래 자리로
        _ = setSuppression?(0)
        CGWarpMouseCursorPosition(c)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        pendingDown = nil; pendingRuler = nil   // 꺼진 사이 손 떼는 신호를 놓쳤을 수 있다
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == myTag { return Unmanaged.passUnretained(event) }

    switch type {
    case .leftMouseDown:
        pendingDown = nil; pendingRuler = nil   // 이전 클릭이 끝나지 않은 채 남아 있으면 버린다
        let f = event.flags
        let shiftOnly = f.contains(.maskShift) && !f.contains(.maskCommand) && !f.contains(.maskAlternate) && !f.contains(.maskControl)
        guard enabled, shiftOnly, event.getIntegerValueField(.mouseEventClickState) == 1, let pid = frontLogicPID(),
              let r = rulerPoint(forBackgroundClickAt: event.location, logicPID: pid) else { return Unmanaged.passUnretained(event) }
        pendingDown = event.copy()
        pendingRuler = r
        return nil
    case .leftMouseDragged:
        if let d = pendingDown, hypot(event.location.x - d.location.x, event.location.y - d.location.y) > 4 {
            // 드래그(Shift-영역 선택)였으면 붙잡아 둔 클릭을 원래대로 보낸다
            d.setIntegerValueField(.eventSourceUserData, value: myTag)
            d.post(tap: .cghidEventTap)
            pendingDown = nil; pendingRuler = nil
        }
        return pendingDown == nil ? Unmanaged.passUnretained(event) : nil
    case .leftMouseUp:
        guard let d = pendingDown, let r = pendingRuler else { return Unmanaged.passUnretained(event) }
        pendingDown = nil; pendingRuler = nil
        let back = d.location
        DispatchQueue.main.async { clickRuler(r, returnTo: back) }
        log("재생헤드 이동 x=\(Int(r.x))")
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}

func startTap() -> Bool {
    let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil) else { return false }
    tap = t
    let src = CFMachPortCreateRunLoopSource(nil, t, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    return true
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var retry: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇧▶︎"
        let menu = NSMenu()
        let t = NSMenuItem(title: "켜짐", action: #selector(toggle(_:)), keyEquivalent: "")
        t.state = .on
        menu.addItem(t)
        menu.addItem(withTitle: "로직 창 구조 기록", action: #selector(dump), keyEquivalent: "")
        menu.addItem(withTitle: "기록 파일 열기", action: #selector(openLog), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) { log("손쉬운 사용 권한 대기 중") }
        tryStart()
    }

    func tryStart() {
        if AXIsProcessTrusted(), startTap() { log("시작됨"); item.button?.title = "⇧▶︎"; return }
        item.button?.title = "⇧▶︎?"
        retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.tryStart() }
    }

    @objc func toggle(_ m: NSMenuItem) {
        enabled.toggle()
        m.state = enabled ? .on : .off
        item.button?.title = enabled ? "⇧▶︎" : "⇧▷"
    }
    @objc func dump() { DispatchQueue.global(qos: .utility).async { dumpLogicWindow() } }
    @objc func openLog() { NSWorkspace.shared.open(logURL) }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
