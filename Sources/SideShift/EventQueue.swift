import Foundation

/// Sends events in order, one at a time, and keeps the ones it could not send on disk for the next try.
/// A rejected event is dropped; an event that failed to send is retried with backoff. The queue holds at most
/// `capacity` events and drops the oldest past that, so an app offline for weeks does not grow without bound.
actor EventQueue {
    private let store: InstallStore
    private let transport: Transport
    private let capacity: Int
    private var events: [AppEvent]
    private var flushing = false
    private var failures = 0
    private var retryTask: Task<Void, Never>?

    init(store: InstallStore, transport: Transport, capacity: Int = 500) {
        self.store = store
        self.transport = transport
        self.capacity = capacity
        self.events = store.loadQueue()
    }

    var pending: [AppEvent] { events }

    func enqueue(_ event: AppEvent) async {
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        store.saveQueue(events)
        await flush()
    }

    /// Drops every queued event that carries consent, after the person withdrew it.
    func dropConsentedEvents() {
        events.removeAll { $0.consent }
        store.saveQueue(events)
    }

    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let next = events.first {
            switch await transport.send(next) {
            case .delivered, .rejected:
                if events.first == next { events.removeFirst() }
                failures = 0
                store.saveQueue(events)
            case .retry:
                failures += 1
                scheduleRetry()
                return
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = min(300.0, pow(2.0, Double(min(failures, 8))))
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }
}
