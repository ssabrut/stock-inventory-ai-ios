//
//  SiriSessionState.swift
//  stock-inventory-ai-ios
//

import Foundation

/// One item parsed during an in-progress add-stock session (Siri or in-app
/// mic), before the user confirms and it's written to StockStore.
struct PendingStockItemDTO: Codable, Identifiable, Equatable {
    let id: UUID
    let itemName: String
    let quantity: Double
    let unit: String

    init(id: UUID = UUID(), itemName: String, quantity: Double, unit: String) {
        self.id = id
        self.itemName = itemName
        self.quantity = quantity
        self.unit = unit
    }
}

/// Shared session state for the "add stock" flow, written by AddStockIntent
/// (which runs out-of-process when triggered by Siri) and read by the main
/// app's floating overlay (StockSessionOverlay) so it can mirror a live Siri
/// session in real time.
///
/// Backed by App Group UserDefaults (same App Group as PersistenceController)
/// since this is small, transient, non-relational state — Core Data would
/// mean writing throwaway rows before the user ever confirms. Cross-process
/// updates are pushed via Darwin notifications: UserDefaults(suiteName:)
/// doesn't notify other processes on change, only KVO within the same one.
enum SiriSessionState {
    private static let suiteName = PersistenceController.appGroupID
    private static let key = "siriSessionState.v1"
    private static let darwinNotificationName = "com.meeko.stock-inventory-ai-ios.sessionChanged" as CFString

    private struct Snapshot: Codable {
        var isActive: Bool
        var source: String
        var items: [PendingStockItemDTO]
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    enum Source: String {
        case siri
        case manual
    }

    static var isActive: Bool {
        snapshot.isActive
    }

    static var items: [PendingStockItemDTO] {
        snapshot.items
    }

    static var source: Source {
        Source(rawValue: snapshot.source) ?? .manual
    }

    private static var snapshot: Snapshot {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return Snapshot(isActive: false, source: Source.manual.rawValue, items: [])
        }
        return decoded
    }

    private static func write(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        notifyOtherProcesses()
    }

    static func begin(source: Source) {
        write(Snapshot(isActive: true, source: source.rawValue, items: []))
    }

    static func append(_ item: PendingStockItemDTO, source: Source) {
        var current = snapshot
        current.isActive = true
        current.source = source.rawValue
        current.items.append(item)
        write(current)
    }

    static func remove(id: UUID) {
        var current = snapshot
        current.items.removeAll { $0.id == id }
        write(current)
    }

    /// Ends the session, clearing pending items. Called on confirm, cancel,
    /// or when the loop finishes (whether or not the user actually commits
    /// to StockStore) so the overlay doesn't linger showing a stale session.
    static func end() {
        write(Snapshot(isActive: false, source: Source.manual.rawValue, items: []))
    }

    // MARK: - Cross-process notification

    /// Posts a Darwin notification so the main app process wakes up and
    /// re-reads UserDefaults even when AddStockIntent runs in a separate
    /// App Intents extension process. Darwin notifications carry no payload,
    /// they're just a "something changed, go re-read shared state" signal.
    private static func notifyOtherProcesses() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName),
            nil, nil, true
        )
    }

    /// Registers `onChange` to fire whenever this or another process updates
    /// the session (including this process's own writes, since observers use
    /// the same Darwin notification path uniformly).
    private static let observerToken = UnsafeRawPointer(bitPattern: 1)!

    static func observe(_ onChange: @escaping () -> Void) {
        changeHandler = onChange
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observerToken,
            { _, _, _, _, _ in
                DispatchQueue.main.async { SiriSessionState.changeHandler?() }
            },
            darwinNotificationName,
            nil,
            .deliverImmediately
        )
    }

    static func stopObserving() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observerToken,
            CFNotificationName(darwinNotificationName),
            nil
        )
        changeHandler = nil
    }

    private static var changeHandler: (() -> Void)?
}
