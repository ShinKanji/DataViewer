import Foundation
import os

nonisolated enum ParallelWorkPolicy {
    static let maxConcurrency: Int = {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return min(max(cores, 2), 8)
    }()

    private static let logger = Logger(subsystem: "com.dataviewer.app", category: "ParallelWork")

    static func debugLog(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func measure<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
            debugLog("\(label) \(String(format: "%.2f", elapsedMs))ms")
        }
        return try work()
    }

    static func measureAsync<T>(_ label: String, _ work: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
            debugLog("\(label) \(String(format: "%.2f", elapsedMs))ms")
        }
        return try await work()
    }

    static func mapIndexedThrowing<T>(
        count: Int,
        _ body: @escaping @Sendable (Int) throws -> T
    ) throws -> [T] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [try body(0)]
        }

        let limit = min(maxConcurrency, count)
        var results = [T?](repeating: nil, count: count)
        var thrown: Error?
        let lock = NSLock()
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: limit)

        for index in 0..<count {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                defer {
                    semaphore.signal()
                    group.leave()
                }
                lock.lock()
                let shouldRun = thrown == nil
                lock.unlock()
                guard shouldRun else { return }

                do {
                    let value = try body(index)
                    lock.lock()
                    if thrown == nil {
                        results[index] = value
                    }
                    lock.unlock()
                } catch {
                    lock.lock()
                    if thrown == nil {
                        thrown = error
                    }
                    lock.unlock()
                }
            }
        }

        group.wait()
        if let thrown {
            throw thrown
        }
        return results.map { $0! }
    }

    static func map<T: Sendable, R: Sendable>(
        inputs: [T],
        maxConcurrentTasks: Int = maxConcurrency,
        transform: @escaping @Sendable (T) async -> R
    ) async -> [R] {
        guard !inputs.isEmpty else { return [] }
        if inputs.count == 1 {
            return [await transform(inputs[0])]
        }

        let limit = min(maxConcurrentTasks, inputs.count)
        return await withTaskGroup(of: (Int, R).self) { group in
            var results = Array<R?>(repeating: nil, count: inputs.count)
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < inputs.count else { return }
                let index = nextIndex
                let input = inputs[index]
                nextIndex += 1
                group.addTask {
                    let value = await transform(input)
                    return (index, value)
                }
            }

            for _ in 0..<limit {
                enqueueNext()
            }

            for await (finishedIndex, value) in group {
                results[finishedIndex] = value
                enqueueNext()
            }

            return results.map { $0! }
        }
    }

    static func mapThrowing<T: Sendable, R: Sendable>(
        inputs: [T],
        maxConcurrentTasks: Int = maxConcurrency,
        transform: @escaping @Sendable (T) async throws -> R
    ) async throws -> [R] {
        guard !inputs.isEmpty else { return [] }
        if inputs.count == 1 {
            return [try await transform(inputs[0])]
        }

        let limit = min(maxConcurrentTasks, inputs.count)
        return try await withThrowingTaskGroup(of: (Int, R).self) { group in
            var results = Array<R?>(repeating: nil, count: inputs.count)
            var nextIndex = 0

            func enqueueNext() {
                guard nextIndex < inputs.count else { return }
                let index = nextIndex
                let input = inputs[index]
                nextIndex += 1
                group.addTask {
                    let value = try await transform(input)
                    return (index, value)
                }
            }

            for _ in 0..<limit {
                enqueueNext()
            }

            while let (finishedIndex, value) = try await group.next() {
                results[finishedIndex] = value
                enqueueNext()
            }

            return results.map { $0! }
        }
    }
}
