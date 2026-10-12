import CopilotCreditsCore
import AppKit
import Charts
import SwiftUI

// MARK: - Panel root

struct ContentView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.phase {
            case .loggedOut:
                LoginView()
            case .awaitingDevice(let code):
                DeviceCodeView(code: code)
            case .ready:
                UsageView()
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            FooterView()
        }
        .padding(16)
        .frame(width: 340)
        // Height = content: otherwise the MenuBarExtra window keeps an arbitrary height
        // (e.g. after signing out) and the panel floats in a large empty frame.
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Sign-in

struct LoginView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copilot Credits").font(.headline)
            Text(tr("Connectez le compte GitHub qui porte votre siège Copilot pour suivre vos AI credits.",
                     "Sign in with the GitHub account that holds your Copilot seat to track your AI credits."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                store.startDeviceLogin()
            } label: {
                Label(tr("Se connecter à GitHub", "Sign in to GitHub"), systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(tr("Ou réutiliser le token de Copilot CLI", "Or reuse the Copilot CLI token")) {
                store.importFromCopilotCLI()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

struct DeviceCodeView: View {
    @EnvironmentObject var store: UsageStore
    let code: DeviceCode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Saisissez ce code sur GitHub", "Enter this code on GitHub")).font(.headline)

            Text(code.userCode)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                if let url = URL(string: code.verificationUri) { NSWorkspace.shared.open(url) }
            } label: {
                Label(tr("Copier le code et ouvrir GitHub", "Copy code and open GitHub"), systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("En attente de validation…", "Waiting for approval…")).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Annuler", "Cancel")) { store.cancelLogin() }
            }
            .font(.callout)
        }
    }
}

// MARK: - Usage

struct UsageView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        if let s = store.snapshot {
            details(s)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("Premier relevé…", "Fetching usage…")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func details(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Copilot \(s.plan.capitalized)").font(.headline)
                Spacer()
                if let login = store.login {
                    Text(login).font(.caption).foregroundStyle(.secondary)
                }
            }

            if s.unlimited {
                Text(tr("Crédits illimités sur ce siège.", "Unlimited credits on this seat.")).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.percent(s.fractionUsed))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(tr("utilisés", "used")).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(L10n.credits(s.used)) / \(L10n.credits(s.entitlement)) cr")
                        .monospacedDigit()
                }

                ProgressView(value: min(s.fractionUsed, 1))
                    .tint(Self.color(for: s.fractionUsed))

                VStack(spacing: 4) {
                    if let reset = s.resetDate {
                        let when = reset.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(L10n.locale))
                        let days = Self.daysUntil(reset)
                        row(tr("Remise à zéro", "Resets"),
                            tr("\(when) · dans \(days) j", "\(when) · in \(days) d"))
                    }
                    if let rate = s.dailyRate() {
                        row(tr("Rythme moyen", "Average pace"), tr("\(L10n.credits(rate)) cr / jour", "\(L10n.credits(rate)) cr / day"))
                    }
                    if let budget = s.budgetPerDay() {
                        row(tr("Pour tenir le quota", "To stay within quota"),
                            tr("≤ \(L10n.credits(budget)) cr / jour", "≤ \(L10n.credits(budget)) cr / day"))
                    }
                    if let projected = s.projectedUsage() {
                        row(tr("Projection fin de cycle", "End-of-cycle projection"), "~\(L10n.credits(projected)) cr",
                            color: projected > s.entitlement ? .orange : .primary)
                    }
                    if s.overage > 0 {
                        row(tr("Dépassement", "Overage"), "\(L10n.credits(s.overage)) cr", color: .orange)
                    }
                }
                .font(.callout)

                UsageChart(snapshot: s, points: store.history)

                if s.overagePermitted {
                    Text(tr("Dépassement autorisé par l'organisation : pas de blocage à 100 %.",
                             "Overage allowed by your organization: no hard stop at 100%."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).monospacedDigit()
        }
    }

    static func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.8: return .accentColor
        case ..<1.0: return .orange
        default: return .red
        }
    }

    static func daysUntil(_ date: Date) -> Int {
        max(0, Int((date.timeIntervalSinceNow / 86_400).rounded(.up)))
    }
}

/// Cycle usage curve + dashed projection + allocation line.
struct UsageChart: View {
    let snapshot: UsageSnapshot
    let points: [HistoryPoint]

    var body: some View {
        if points.count < 2 {
            Text(tr("Le graphique se construit au fil des relevés (toutes les 10 min).",
                     "The chart builds up as usage is fetched (every 10 min)."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(points) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Credits", p.used),
                        series: .value("Series", "Usage")
                    )
                    .foregroundStyle(Color.accentColor)
                }

                if let last = points.last, let reset = snapshot.resetDate,
                   let projected = snapshot.projectedUsage() {
                    LineMark(x: .value("Date", last.date), y: .value("Credits", last.used),
                             series: .value("Series", "Projection"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    LineMark(x: .value("Date", reset), y: .value("Credits", projected),
                             series: .value("Series", "Projection"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                RuleMark(y: .value("Allocation", snapshot.entitlement))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 120)
        }
    }

    private var xDomain: ClosedRange<Date> {
        let start = snapshot.cycleStart ?? points.first?.date ?? .now
        let end = snapshot.resetDate ?? .now
        return start < end ? start...end : start...start.addingTimeInterval(86_400)
    }
}

// MARK: - Panel footer

struct FooterView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack {
            if let s = store.snapshot {
                let time = s.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: L10n.locale))
                Text(tr("Relevé à \(time)", "Updated at \(time)"))
            }
            Spacer()

            if store.phase == .ready {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help(tr("Actualiser", "Refresh"))
            }

            Menu {
                Toggle(tr("Lancer au démarrage", "Launch at login"), isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Picker(tr("Langue", "Language"), selection: Binding(
                    get: { store.language },
                    set: { store.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                if store.phase == .ready {
                    Button(tr("Se déconnecter", "Sign out")) { store.logout() }
                }
                Divider()
                Button(tr("Quitter", "Quit")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
