#if DEBUG
import AppKit
import CopilotCreditsCore
import SwiftUI

/// README tutorial frames, rendered with the real views and fake data:
/// no real account or usage ever appears. Run by scripts/make-tutorial.sh, which assembles
/// the PNGs into a GIF / MP4 with ffmpeg using the `frames.txt` list (duration of each frame).
@MainActor
enum Tutorial {
    static let size = CGSize(width: 760, height: 600)
    static let scale: CGFloat = 2
    nonisolated static let fps = 20.0

    /// Position of the app icon in the fake menu bar.
    static let iconCenter = CGPoint(x: 470, y: 14)
    static let panelOrigin = CGPoint(x: 300, y: 34)

    // MARK: - Storyboard

    static func render(to dir: URL) {
        _ = NSApplication.shared
        pretendAppIsActive()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Fixed time (10:41) for a stable image; the script pins TZ=UTC and the locale.
        let now = Calendar.current.date(bySettingHour: 10, minute: 41, second: 0, of: Date()) ?? Date()
        let usage = demoSnapshot(now: now, used: 612)
        let alert = demoSnapshot(now: now, used: 823)

        var t = Timeline(cursor: CGPoint(x: 330, y: 330))

        // 1. Icon in the menu bar
        var shot = Shot(step: 1, caption: tr("Cliquez sur l'icône dans la barre de menus",
                                             "Click the icon in the menu bar"))
        t.hold(shot, 1.2)
        t.move(shot, to: iconCenter, 0.9)
        t.click(shot)

        // 2. Sign-in
        shot = Shot(step: 2, caption: tr("Connectez le compte GitHub qui porte votre siège Copilot",
                                         "Sign in with the GitHub account that holds your Copilot seat"),
                    panel: UsageStore(tutorialPhase: .loggedOut))
        t.hold(shot, 1.2)
        t.move(shot, to: CGPoint(x: 470, y: 130), 0.8)
        t.click(shot)

        // 3. Device flow code
        shot = Shot(step: 3, caption: tr("Copiez le code : GitHub s'ouvre dans le navigateur",
                                         "Copy the code: GitHub opens in your browser"),
                    panel: UsageStore(tutorialPhase: .awaitingDevice(demoDeviceCode)))
        t.hold(shot, 1.2)
        t.move(shot, to: CGPoint(x: 476, y: 128), 0.7)
        t.click(shot)
        t.hold(shot, 0.5)

        // 4. Browser: paste the code
        shot = Shot(step: 4, caption: tr("Collez le code sur github.com/login/device, puis Continue",
                                         "Paste the code on github.com/login/device, then Continue"),
                    browser: .device(filled: false))
        t.hold(shot, 0.9)
        t.move(shot, to: Browser.firstBox, 0.7)
        t.click(shot)
        shot.browser = .device(filled: true)
        shot.pasteHint = true
        t.hold(shot, 0.9)
        shot.pasteHint = false
        t.move(shot, to: Browser.continueButton, 0.6)
        t.click(shot)

        // 5. Browser: authorize
        shot = Shot(step: 5, caption: tr("Autorisez l'accès avec le compte qui porte votre siège Copilot",
                                         "Authorize access with the account that holds your Copilot seat"),
                    browser: .authorize)
        t.hold(shot, 1.4)
        t.move(shot, to: Browser.authorizeButton, 0.7)
        t.click(shot)
        shot.browser = .done
        t.hold(shot, 1.3)
        t.move(shot, to: iconCenter, 0.8)
        t.click(shot)

        // 6. Tracking
        shot = Shot(step: 6, caption: tr("Suivez vos AI credits : rythme, budget par jour, projection",
                                         "Track your AI credits: pace, daily budget, projection"),
                    menuBar: usage,
                    panel: UsageStore(tutorialPhase: .ready, snapshot: usage,
                                      history: demoHistory(for: usage, now: now), login: "octocat"))
        t.move(shot, to: CGPoint(x: 690, y: 430), 0.8)
        t.hold(shot, 4.5)

        // 7. Always-visible percentage + alerts
        shot = Shot(step: 7, caption: tr("Le % reste visible ; une alerte à 80 % et à 100 %",
                                         "The % stays in the menu bar; alerts at 80% and 100%"),
                    menuBar: alert, notification: alert)
        t.move(shot, to: CGPoint(x: 478, y: 26), 0.8)
        t.hold(shot, 3.5)

        write(t.frames, to: dir)
    }

    // MARK: - Fake data

    static func demoSnapshot(now: Date, used: Double) -> UsageSnapshot {
        let reset = Calendar.current.startOfDay(for: now.addingTimeInterval(13 * 86_400))
        return UsageSnapshot(date: now.addingTimeInterval(-120), plan: "business", used: used, entitlement: 1000,
                             overage: 0, overagePermitted: true, unlimited: false, resetDate: reset)
    }

    /// Plausible curve: busy weekdays, quiet weekends, a snapshot every 6 h.
    static func demoHistory(for s: UsageSnapshot, now: Date) -> [HistoryPoint] {
        guard let start = s.cycleStart else { return [] }
        let steps = Int(now.timeIntervalSince(start) / (6 * 3600))
        var weights: [Double] = []
        for i in 0...steps {
            let day = Calendar.current.component(.weekday, from: start.addingTimeInterval(Double(i) * 6 * 3600))
            let weekend = day == 1 || day == 7
            weights.append(weekend ? 0.1 : 1 + 0.6 * sin(Double(i) * 1.7))
        }
        let total = weights.reduce(0, +)
        var used = 0.0
        return weights.enumerated().map { i, w in
            used += s.used * w / total
            return HistoryPoint(date: start.addingTimeInterval(Double(i) * 6 * 3600), used: used)
        }
    }

    /// Example code from the GitHub documentation.
    static var demoDeviceCode: DeviceCode {
        let json = #"{"device_code":"x","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
        return try! JSONDecoder().decode(DeviceCode.self, from: Data(json.utf8))
    }

    /// Fake menu bar clock, consistent with the storyboard's fixed time.
    static var clock: String {
        let now = Calendar.current.date(bySettingHour: 10, minute: 41, second: 0, of: Date()) ?? Date()
        return now.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(L10n.locale))
    }

    // MARK: - Images

    /// AppKit draws buttons and progress bars greyed out when the app is inactive, which is always
    /// the case for an offscreen render: force NSApplication.isActive to true (render only).
    static func pretendAppIsActive() {
        let block: @convention(block) (AnyObject) -> Bool = { _ in true }
        guard let method = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)) else { return }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Offscreen window that claims to be active: otherwise buttons and bars render grey (inactive).
    final class ActiveWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var isMainWindow: Bool { true }
        override var canBecomeKey: Bool { true }
    }

    struct Shot {
        var step: Int
        var caption: String
        var menuBar: UsageSnapshot?
        var panel: UsageStore?
        var notification: UsageSnapshot?
        var browser: Browser.Page?
        var pasteHint = false
    }

    struct Frame {
        var shot: Shot
        var cursor: CGPoint
        var clicking = false
        var duration: Double
    }

    struct Timeline {
        var cursor: CGPoint
        var frames: [Frame] = []

        mutating func hold(_ shot: Shot, _ seconds: Double) {
            frames.append(Frame(shot: shot, cursor: cursor, duration: seconds))
        }

        mutating func move(_ shot: Shot, to target: CGPoint, _ seconds: Double) {
            let n = max(1, Int(seconds * Tutorial.fps))
            let from = cursor
            for i in 1...n {
                let x = Double(i) / Double(n)
                let e = x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 // ease-in-out
                cursor = CGPoint(x: from.x + (target.x - from.x) * e, y: from.y + (target.y - from.y) * e)
                frames.append(Frame(shot: shot, cursor: cursor, duration: 1 / Tutorial.fps))
            }
        }

        mutating func click(_ shot: Shot) {
            frames.append(Frame(shot: shot, cursor: cursor, clicking: true, duration: 0.25))
            frames.append(Frame(shot: shot, cursor: cursor, duration: 0.15))
        }
    }

    static func write(_ frames: [Frame], to dir: URL) {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.appearance = NSAppearance(named: .darkAqua)
        let window = ActiveWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        // Shown outside every screen: a window that was never ordered in keeps the inactive look.
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        window.makeKey()

        var list = ""
        for (i, frame) in frames.enumerated() {
            host.rootView = AnyView(Stage(frame: frame)
                .environment(\.colorScheme, .dark)
                .environment(\.controlActiveState, .key))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))

            let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                       pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)

            let name = String(format: "frame%04d.png", i)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            list += "file '\(name)'\nduration \(frame.duration)\n"
        }
        // ffmpeg's concat demuxer ignores the last frame's duration without this repetition.
        list += "file '\(String(format: "frame%04d.png", frames.count - 1))'\n"
        try? list.write(to: dir.appendingPathComponent("frames.txt"), atomically: true, encoding: .utf8)
    }
}

// MARK: - Staging

private struct Stage: View {
    let frame: Tutorial.Frame

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.22, blue: 0.30),
                                    Color(red: 0.10, green: 0.12, blue: 0.28)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            menuBar

            if let store = frame.shot.panel {
                ContentView()
                    .environmentObject(store)
                    .environment(\.locale, L10n.locale)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                    .offset(x: Tutorial.panelOrigin.x - 0, y: Tutorial.panelOrigin.y)
            }

            if let page = frame.shot.browser {
                Browser(page: page)
                    .offset(x: Browser.origin.x, y: Browser.origin.y)
            }

            if frame.shot.pasteHint {
                Text("⌘V")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .offset(x: frame.cursor.x - 66, y: frame.cursor.y - 8)
            }

            if let s = frame.shot.notification, let reset = s.resetDate {
                notification(UsageStore.alertText(s, reset: reset))
                    .offset(x: Tutorial.size.width - 372, y: 38)
            }

            caption
                .frame(width: Tutorial.size.width)
                .offset(y: Tutorial.size.height - 64)

            Cursor(clicking: frame.clicking)
                .offset(x: frame.cursor.x - 3, y: frame.cursor.y - 2)
        }
        .frame(width: Tutorial.size.width, height: Tutorial.size.height, alignment: .topLeading)
        .clipped()
    }

    private var menuBar: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black.opacity(0.35)).frame(height: 28)

            HStack(spacing: 16) {
                Image(systemName: "apple.logo")
                Text("Finder").bold()
                Text(tr("Fichier", "File"))
                Text(tr("Édition", "Edit"))
            }
            .offset(x: 18, y: 6)

            HStack(spacing: 4) {
                if let s = frame.shot.menuBar {
                    Image(systemName: s.fractionUsed >= 0.8 ? "exclamationmark.triangle.fill" : "speedometer")
                    Text(L10n.percent(s.fractionUsed))
                } else {
                    Image(systemName: "speedometer")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(frame.shot.panel == nil ? 0 : 0.22)))
            .fixedSize()
            .frame(width: 120)
            .offset(x: Tutorial.iconCenter.x - 60, y: 3)

            HStack(spacing: 16) {
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(Tutorial.clock)
            }
            .offset(x: Tutorial.size.width - 210, y: 6)
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
    }

    private func notification(_ text: (title: String, body: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speedometer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(.system(size: 13, weight: .semibold))
                Text(text.body).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 356)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.2)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private var caption: some View {
        HStack(spacing: 10) {
            Text("\(frame.shot.step)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            Text(frame.shot.caption)
                .font(.system(size: 16, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.black.opacity(0.55)))
    }
}

/// Simplified look-alike of GitHub's device activation pages (no GitHub logo). The signed-in
/// account is a generic placeholder, blurred: no real account ever appears.
struct Browser: View {
    enum Page { case device(filled: Bool), authorize, done }
    let page: Page

    static let origin = CGPoint(x: 70, y: 46)
    static let size = CGSize(width: 620, height: 470)
    // Click targets, in stage coordinates (checked against the rendered frames).
    static let firstBox = CGPoint(x: origin.x + 164, y: origin.y + 280)
    static let continueButton = CGPoint(x: origin.x + 310, y: origin.y + 330)
    static let authorizeButton = CGPoint(x: origin.x + 408, y: origin.y + 340)

    private let pageColor = Color(red: 0.05, green: 0.07, blue: 0.09)
    private let cardColor = Color(red: 0.09, green: 0.11, blue: 0.13)
    private let borderColor = Color.white.opacity(0.14)
    private let green = Color(red: 0.14, green: 0.53, blue: 0.24)

    var body: some View {
        VStack(spacing: 0) {
            chrome
            VStack(spacing: 0) {
                header
                content.frame(maxHeight: .infinity, alignment: .top)
            }
            .background(pageColor)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
        .foregroundStyle(.white)
    }

    private var chrome: some View {
        ZStack {
            Color(white: 0.17)
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12) }
                Spacer()
            }
            .padding(.leading, 14)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text("github.com/login/device")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 300, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.24)))
        }
        .frame(height: 40)
    }

    /// Top bar with the signed-in account: generic avatar and blurred placeholder name.
    private var header: some View {
        HStack(spacing: 8) {
            Text("GitHub").font(.system(size: 15, weight: .semibold))
            Spacer()
            BlurredName(size: 12)
            avatar(22)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .overlay(alignment: .bottom) { Rectangle().fill(borderColor).frame(height: 1) }
    }

    private func avatar(_ size: CGFloat) -> some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.55))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(red: 0.35, green: 0.40, blue: 0.48)))
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .device(let filled):
            VStack(spacing: 16) {
                Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 34)).padding(.top, 34)
                Text("Device Activation").font(.system(size: 22, weight: .regular))
                VStack(alignment: .leading, spacing: 14) {
                    Text("Enter the code displayed on your device").font(.system(size: 13, weight: .semibold))
                    codeBoxes(filled ? Array("WDJBMJHT") : [])
                    Text("Continue")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(green))
                }
                .padding(18)
                .frame(width: 360)
                .background(RoundedRectangle(cornerRadius: 6).fill(cardColor))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor))
            }
        case .authorize:
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 22))
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.22)))
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    avatar(48)
                }
                .padding(.top, 30)
                Text("Authorize GitHub Copilot Plugin").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        Text("GitHub Copilot Plugin wants to access your").font(.system(size: 13))
                        BlurredName(size: 13)
                        Text("account").font(.system(size: 13))
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "person.text.rectangle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personal user data").font(.system(size: 13, weight: .semibold))
                            Text("Profile information (read-only)").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Rectangle().fill(borderColor).frame(height: 1)
                    HStack(spacing: 10) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.2)))
                        Text("Authorize")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(RoundedRectangle(cornerRadius: 6).fill(green))
                    }
                    .font(.system(size: 13))
                }
                .padding(18)
                .frame(width: 420)
                .background(RoundedRectangle(cornerRadius: 6).fill(cardColor))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor))
            }
        case .done:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(green)
                    .padding(.top, 90)
                Text("Congratulations, you're all set!").font(.system(size: 22))
                Text("Your device is now connected.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private func codeBoxes(_ chars: [Character]) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                if i == 4 { Text("–").foregroundStyle(.secondary) }
                Text(i < chars.count ? String(chars[i]) : " ")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .frame(width: 32, height: 40)
                    .background(RoundedRectangle(cornerRadius: 6).fill(pageColor))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(i == 0 && chars.isEmpty ? Color.blue : borderColor, lineWidth: i == 0 && chars.isEmpty ? 2 : 1))
            }
        }
    }
}

/// Placeholder account name, blurred. SwiftUI's .blur doesn't survive cacheDisplay, so the blur
/// is faked by stacking faint offset copies of the text.
private struct BlurredName: View {
    let size: CGFloat

    var body: some View {
        let text = Text("octocat").font(.system(size: size, weight: .semibold))
        ZStack {
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) * .pi / 6
                let r = i < 12 ? 2.5 : 4.5
                text.opacity(0.09).offset(x: cos(angle) * r, y: sin(angle) * r * 0.6)
            }
        }
        .fixedSize()
    }
}

/// Hand-drawn mouse arrow (system cursors can't be captured).
private struct Cursor: View {
    let clicking: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if clicking {
                Circle()
                    .stroke(.white.opacity(0.8), lineWidth: 2)
                    .background(Circle().fill(.white.opacity(0.25)))
                    .frame(width: 30, height: 30)
                    .offset(x: -12, y: -13)
            }
            Arrow().fill(.black).overlay(Arrow().stroke(.white, lineWidth: 1.5))
                .frame(width: 17, height: 25)
                .scaleEffect(clicking ? 0.9 : 1, anchor: .topLeading)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }

    struct Arrow: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: r.height * 0.86))
            p.addLine(to: CGPoint(x: r.width * 0.28, y: r.height * 0.66))
            p.addLine(to: CGPoint(x: r.width * 0.48, y: r.height))
            p.addLine(to: CGPoint(x: r.width * 0.64, y: r.height * 0.93))
            p.addLine(to: CGPoint(x: r.width * 0.45, y: r.height * 0.6))
            p.addLine(to: CGPoint(x: r.width, y: r.height * 0.6))
            p.closeSubpath()
            return p
        }
    }
}
#endif
