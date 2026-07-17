import Foundation

@MainActor
final class SerialAsyncQueue<Element> {
    typealias Operation = @MainActor (Element) async -> Void

    private var pending: [Element] = []
    private var worker: Task<Void, Never>?

    var first: Element? { pending.first }
    var isIdle: Bool { worker == nil && pending.isEmpty }

    func enqueue(_ element: Element, operation: @escaping Operation) {
        pending.append(element)
        startIfNeeded(operation: operation)
    }

    func removeAll(where shouldRemove: (Element) -> Bool) {
        pending.removeAll(where: shouldRemove)
    }

    deinit {
        worker?.cancel()
    }

    private func startIfNeeded(operation: @escaping Operation) {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }

            while !pending.isEmpty, !Task.isCancelled {
                let element = pending.removeFirst()
                await operation(element)
            }

            worker = nil
            if !pending.isEmpty {
                startIfNeeded(operation: operation)
            }
        }
    }
}
