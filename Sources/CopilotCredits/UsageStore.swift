import AppKit
import CopilotCreditsCore
import Foundation
import ServiceManagement

/// App state: authentication, periodic fetches, history, alerts.
@MainActor
final class UsageStore: ObservableObject {
    enum Phase: Equatable {
        case loggedOut
        case awaitingDevice(DeviceCode)
        case ready
    }

    @Published private(set) var phase: Phase = .loggedOut
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    @Published private(set) var login: String?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    /// Changing the language republishes state: every view redraws with tr().
    var language: AppLanguage {
        get { AppLanguage.current }
        set {
            AppLanguage.current = newValue
            objectWillChange.send()
        }
    }

    /// 10 min: frequent enough to be useful, rare enough not to hammer an internal endpoint.
    static let refreshInterval: UInt64 = 10 * 60

    private var token: String?
    private var pollTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private let historyStore = HistoryStore(path: HistoryStore.defaultPath)
    private var wakeObserver: NSObjectProtocol?

    init() {
        Notifier.requestAuthorization()

        // When the Mac wakes up, the last snapshot may be hours old.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        // Priority order: the app's Keychain item, then the environment variable.
        if let saved = Keychain.load() {
            useToken(saved)
        } else if let env = ProcessInfo.processInfo.environment["GH_COPILOT_TOKEN"], !env.isEmpty {
            useToken(env)
        }
    }

    // MARK: - Authentication

    func startDeviceLogin() {
        authTask?.cancel()
        errorMessage = nil
        authTask = Task {
            do {
                let code = try await DeviceFlow.start()
                phase = .awaitingDevice(code)
                let token = try await DeviceFlow.waitForToken(code)
                try Keychain.save(token)
                useToken(token)
            } catch {
                phase = .loggedOut
                if !Task.isCancelled { errorMessage = L10n.message(for: error) }
            }
        }
    }

    func cancelLogin() {
        authTask?.cancel()
        authTask = nil
        phase = .loggedOut
    }

    func importFromCopilotCLI() {
        errorMessage = nil
        do {
            let token = try Keychain.readCopilotCLIToken()
            try Keychain.save(token)
            useToken(token)
        } catch {
            errorMessage = L10n.message(for: error)
        }
    }

    func logout() {
        pollTask?.cancel()
        Keychain.delete()
        token = nil
        snapshot = nil
        login = nil
        history = []
        phase = .loggedOut
    }

    private func useToken(_ token: String) {
        self.token = token
        phase = .ready
        startPolling()
        Task { login = await CopilotAPI.fetchLogin(token: token) }
    }

    // MARK: - Fetching

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: Self.refreshInterval * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        guard let token, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let s = try await CopilotAPI.fetchUsage(token: token)
            snapshot = s
            errorMessage = nil
            historyStore.insert(s)
            history = historyStore.points(since: s.cycleStart ?? Date().addingTimeInterval(-31 * 86_400))
            checkThresholds(s)
        } catch {
            errorMessage = L10n.message(for: error)
        }
    }

    /// One notification per threshold per cycle (remembered in UserDefaults).
    private func checkThresholds(_ s: UsageSnapshot) {
        guard !s.unlimited, let reset = s.resetDate else { return }
        let key = "notifiedThreshold-\(Int(reset.timeIntervalSince1970))"
        let alreadyNotified = UserDefaults.standard.double(forKey: key)

        guard let crossed = AlertPolicy.thresholdToNotify(fraction: s.fractionUsed,
                                                          alreadyNotified: alreadyNotified) else { return }

        UserDefaults.standard.set(crossed, forKey: key)
        let alert = Self.alertText(s, reset: reset)
        Notifier.send(title: alert.title, body: alert.body)
    }

    /// Threshold notification text (shared with the tutorial renderer).
    static func alertText(_ s: UsageSnapshot, reset: Date) -> (title: String, body: String) {
        let pct = L10n.percent(s.fractionUsed)
        let used = "\(L10n.credits(s.used)) / \(L10n.credits(s.entitlement))"
        let day = reset.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L10n.locale))
        return (tr("Copilot : \(pct) des AI credits utilisés", "Copilot: \(pct) of AI credits used"),
                tr("\(used) crédits. Remise à zéro le \(day).", "\(used) credits. Resets on \(day)."))
    }

#if DEBUG
    /// Tutorial rendering (scripts/make-tutorial.sh): fake state, no Keychain, network or notifications.
    init(tutorialPhase: Phase, snapshot: UsageSnapshot? = nil, history: [HistoryPoint] = [], login: String? = nil) {
        phase = tutorialPhase
        self.snapshot = snapshot
        self.history = history
        self.login = login
    }
#endif

    // MARK: - Launch at login

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = tr("Lancement au démarrage : ", "Launch at login: ") + error.localizedDescription
        }
        objectWillChange.send()
    }
}
