import Foundation

@main
struct NativeQueueTests {
    @MainActor
    static func main() async {
        let queue = SerialAsyncQueue<Int>()
        var executionOrder: [Int] = []
        let operation: SerialAsyncQueue<Int>.Operation = { value in
            executionOrder.append(value)
            if value == 1 {
                try? await Task.sleep(for: .milliseconds(80))
            }
        }

        queue.enqueue(1, operation: operation)
        try? await Task.sleep(for: .milliseconds(15))
        queue.enqueue(2, operation: operation)
        queue.enqueue(3, operation: operation)

        let deadline = ContinuousClock.now + .seconds(2)
        while !queue.isIdle, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        precondition(queue.isIdle)
        precondition(executionOrder == [1, 2, 3])

        executionOrder.removeAll()
        queue.enqueue(4, operation: operation)
        queue.enqueue(5, operation: operation)
        queue.enqueue(6, operation: operation)
        queue.removeAll(where: { $0 == 5 })
        while !queue.isIdle, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(executionOrder == [4, 6])
        print("Serial automation queue ordering and reentrancy: PASS")
    }
}
