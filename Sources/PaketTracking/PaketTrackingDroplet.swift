import Combine
import DroppyKit
import SwiftUI

@objc(PaketTrackingPrincipal)
public final class PaketTrackingPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { PaketTrackingDroplet() }
}

@MainActor
public final class PaketTrackingDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "paket-tracking"

    private enum Key {
        static let parcels = "parcels"
        static let dhlKey = "dhlKey"
        static let pinActivity = "pinActivity"
        static let interval = "intervalMinutes"
    }

    private var host: DropletHost?
    private var ticker: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var lastRefresh: Date?
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)

    @Published public private(set) var parcels: [Parcel] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var now = Date()

    public func activate(host: DropletHost) throws {
        self.host = host
        parcels = host.preferences.value(forKey: Key.parcels, as: [Parcel].self) ?? []
        pruneDelivered()
        publishActivity()
        ticker = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                self.publishActivity()
                self.refreshIfDue()
            }
        refresh()
    }

    public func deactivate() {
        ticker?.cancel()
        ticker = nil
        refreshTask?.cancel()
        refreshTask = nil
        activitySubject.send(nil)
        host = nil
    }

    public var dhlKey: String {
        get { host?.preferences.value(forKey: Key.dhlKey, default: "") ?? "" }
        set {
            host?.preferences.setValue(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.dhlKey)
            objectWillChange.send()
        }
    }

    public var pinsActivity: Bool {
        get { host?.preferences.value(forKey: Key.pinActivity, default: true) ?? true }
        set {
            host?.preferences.setValue(newValue, forKey: Key.pinActivity)
            objectWillChange.send()
            publishActivity()
        }
    }

    public var intervalMinutes: Double {
        get { host?.preferences.value(forKey: Key.interval, default: 15.0) ?? 15 }
        set {
            host?.preferences.setValue(newValue, forKey: Key.interval)
            objectWillChange.send()
        }
    }

    public var sortedParcels: [Parcel] {
        parcels.sorted { lhs, rhs in
            let l = lhs.sortRank(now: now), r = rhs.sortRank(now: now)
            return l == r ? lhs.displayName < rhs.displayName : l < r
        }
    }

    public var arrivingToday: [Parcel] {
        parcels.filter { $0.arrivesToday(now: now) }
    }

    public func add(carrier: ParcelCarrier, number: String, label: String) {
        let cleaned = number.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty, !parcels.contains(where: { $0.carrier == carrier && $0.number == cleaned }) else { return }
        parcels.append(Parcel(carrier: carrier, number: cleaned, label: label.trimmingCharacters(in: .whitespacesAndNewlines)))
        persist()
        refresh()
    }

    public func openSettings() -> Bool {
        host?.workspace.openSettings() ?? false
    }

    public func remove(_ id: String) {
        parcels.removeAll { $0.id == id }
        persist()
        publishActivity()
    }

    public func refresh() {
        guard refreshTask == nil, !parcels.isEmpty else { return }
        let pending = parcels.filter { $0.status != .delivered }
        guard !pending.isEmpty else { return }
        let key = dhlKey
        isRefreshing = true
        refreshTask = Task { [weak self] in
            let results = await withTaskGroup(of: (String, Result<ParcelUpdate, Error>).self) { group in
                for parcel in pending {
                    group.addTask {
                        do { return (parcel.id, .success(try await ParcelClient.fetch(parcel, dhlKey: key))) }
                        catch { return (parcel.id, .failure(error)) }
                    }
                }
                var collected: [(String, Result<ParcelUpdate, Error>)] = []
                for await item in group { collected.append(item) }
                return collected
            }
            guard let self, !Task.isCancelled else { return }
            self.apply(results)
        }
    }

    private func refreshIfDue() {
        let interval = intervalMinutes * 60
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < interval { return }
        refresh()
    }

    private func apply(_ results: [(String, Result<ParcelUpdate, Error>)]) {
        let stamp = Date()
        for (id, result) in results {
            guard let index = parcels.firstIndex(where: { $0.id == id }) else { continue }
            switch result {
            case .success(let update):
                parcels[index].status = update.status
                parcels[index].detail = update.detail
                parcels[index].eta = update.eta
                parcels[index].error = nil
                if update.status == .delivered, parcels[index].deliveredAt == nil { parcels[index].deliveredAt = stamp }
            case .failure(let error):
                parcels[index].error = (error as? LocalizedError)?.errorDescription ?? "Abruf fehlgeschlagen"
                host?.log.error("Tracking \(parcels[index].carrier.rawValue) failed: \(error.localizedDescription)")
            }
            parcels[index].checkedAt = stamp
        }
        lastRefresh = stamp
        now = stamp
        isRefreshing = false
        refreshTask = nil
        pruneDelivered()
        persist()
        publishActivity()
    }

    private func pruneDelivered() {
        let limit = Date().addingTimeInterval(-3 * 24 * 3600)
        parcels.removeAll { ($0.deliveredAt ?? .distantFuture) < limit }
    }

    private func persist() {
        host?.preferences.setValue(parcels, forKey: Key.parcels)
    }

    private func publishActivity() {
        let today = arrivingToday
        guard !today.isEmpty else {
            activitySubject.send(nil)
            return
        }
        let title = today.count == 1 ? "Ein Paket kommt heute" : "\(today.count) Pakete kommen heute"
        activitySubject.send(
            LiveActivityState(
                priority: 180,
                accessibilityTitle: title,
                isInteractive: false,
                joinsPersistentActivitySet: pinsActivity,
                compactPresentation: nil,
                expandedWidgetID: "parcels"
            )
        )
    }
}

extension PaketTrackingDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    public func makeCompactLeading() -> AnyView {
        AnyView(ParcelCompactGlyph(droplet: self))
    }

    public func makeCompactTrailing() -> AnyView {
        AnyView(ParcelCompactLabel(droplet: self))
    }

    public func makeExpanded(context: LiveActivityContext) -> AnyView {
        AnyView(EmptyView())
    }

    public func makeCompanionCompact(context: CompactLiveActivityContext) -> AnyView {
        makeCompactLeading()
    }

    public func makeCompanionDetail(context: LiveActivityContext) -> AnyView? { nil }
}

extension PaketTrackingDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: "parcels",
                title: "Pakete",
                systemImage: "shippingbox.fill",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 420,
                    preferredPairedWidth: 210,
                    contentHeight: .fixed(150)
                )
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(ParcelWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension PaketTrackingDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(ParcelSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Sendung hinzufügen", keywords: ["paket", "dhl", "dpd", "tracking"]),
            SettingsSearchEntry(title: "DHL-API-Schlüssel", keywords: ["dhl", "key"])
        ]
    }
}

func parcelStatusText(_ parcel: Parcel, now: Date) -> String {
    if parcel.error != nil { return "Fehler" }
    if parcel.arrivesToday(now: now) { return "Kommt heute" }
    if parcel.status == .inTransit, let eta = parcel.eta {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: eta)
    }
    return parcel.status.title
}
