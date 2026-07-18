import Darwin
import Foundation

actor CodexStateService {
    private enum ProcessWaitResult: Sendable {
        case terminated(Int32)
        case timedOut
    }

    private struct RolloutCacheEntry {
        let fileSize: Int
        let modificationDate: Date
        let seenAt: Int64
        let status: CodexTaskStatus
        let reasoningLevel: ReasoningLevel?
        let weeklyQuota: WeeklyQuota?
    }

    private struct DatabaseRow: Decodable {
        let id: String
        let title: String?
        let cwd: String?
        let rollout_path: String?
        let updated_at: Int64?
    }

    private struct QuotaRow: Decodable {
        let rollout_path: String
    }

    private struct QuotaCacheEntry {
        let fileSize: Int
        let modificationDate: Date
        let quota: WeeklyQuota?
    }

    struct Snapshot: Sendable {
        let tasks: [CodexTask]
        let reasoningLevel: ReasoningLevel?
        let weeklyQuota: WeeklyQuota?
        let lifetimeTokens: Int64?
    }

    private let codexHome: URL
    private var rolloutCache: [String: RolloutCacheEntry] = [:]
    private var quotaCache: [String: QuotaCacheEntry] = [:]
    private var cachedLiveMetrics: CodexAccountMetrics?
    private var lastLiveMetricsFetch = Date.distantPast

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome
    }

    func loadSnapshot(seen: [String: Int64], includeLiveQuota: Bool = true) async -> Snapshot {
        guard let database = newestDatabase() else {
            return Snapshot(tasks: [], reasoningLevel: nil, weeklyQuota: nil, lifetimeTokens: nil)
        }
        let sql = "select id,title,cwd,rollout_path,updated_at from threads where archived=0 and id not in (select child_thread_id from thread_spawn_edges) order by recency_at desc limit 6;"
        guard let data = runSQLite(database: database, sql: sql),
              let rows = try? JSONDecoder().decode([DatabaseRow].self, from: data) else {
            return Snapshot(tasks: [], reasoningLevel: nil, weeklyQuota: nil, lifetimeTokens: nil)
        }

        var reasoning: ReasoningLevel?
        let tasks = rows.map { row -> CodexTask in
            let path = row.rollout_path ?? ""
            let seenAt = seen[row.id] ?? 0
            let url = URL(fileURLWithPath: path)
            let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
            let fileSize = attributes[.size] as? Int ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast
            let cached = rolloutCache[path]
            let entry: RolloutCacheEntry
            if let cached,
               cached.fileSize == fileSize,
               cached.modificationDate == modificationDate,
               cached.seenAt == seenAt {
                entry = cached
            } else {
                let rollout = tail(of: url, maximumBytes: 4 * 1_024 * 1_024) ?? Data()
                entry = RolloutCacheEntry(
                    fileSize: fileSize,
                    modificationDate: modificationDate,
                    seenAt: seenAt,
                    status: CodexRolloutParser.status(from: rollout, seenAt: seenAt),
                    reasoningLevel: CodexRolloutParser.reasoningLevel(from: rollout),
                    weeklyQuota: CodexRolloutParser.weeklyQuota(from: rollout)
                )
                rolloutCache[path] = entry
            }
            if reasoning == nil { reasoning = entry.reasoningLevel }
            return CodexTask(
                id: row.id,
                title: row.title ?? "",
                cwd: row.cwd ?? "",
                rolloutPath: path,
                updatedAt: row.updated_at ?? 0,
                status: entry.status
            )
        }
        let storedQuota = latestStoredWeeklyQuota(database: database)
        let liveMetrics = includeLiveQuota ? await latestLiveAccountMetrics() : nil
        return Snapshot(
            tasks: tasks,
            reasoningLevel: reasoning,
            weeklyQuota: newestQuota(liveMetrics?.weeklyQuota, storedQuota),
            lifetimeTokens: liveMetrics?.lifetimeTokens
        )
    }

    private func latestLiveAccountMetrics() async -> CodexAccountMetrics? {
        let now = Date()
        guard now.timeIntervalSince(lastLiveMetricsFetch) >= 20 else { return cachedLiveMetrics }
        lastLiveMetricsFetch = now
        if let metrics = await fetchLiveAccountMetrics(observedAt: now) { cachedLiveMetrics = metrics }
        return cachedLiveMetrics
    }

    private func fetchLiveAccountMetrics(observedAt: Date) async -> CodexAccountMetrics? {
        guard let executable = codexExecutable() else { return nil }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let terminationEvents = AsyncStream<Int32> { continuation in
            process.terminationHandler = { completedProcess in
                continuation.yield(completedProcess.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
            let outputTask = Task<Data, Error> {
                var data = Data()
                var line = Data()
                var didSendAccountQueries = false
                var receivedAccountResponseIDs = Set<Int>()

                for try await byte in output.fileHandleForReading.bytes {
                    data.append(byte)
                    line.append(byte)

                    guard byte == 0x0A else { continue }
                    defer { line.removeAll(keepingCapacity: true) }
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let responseID = (object["id"] as? NSNumber)?.intValue else { continue }

                    if responseID == 1,
                       object["result"] != nil,
                       !didSendAccountQueries {
                        didSendAccountQueries = true
                        let accountQueries = [
                            #"{"method":"initialized"}"#,
                            #"{"id":2,"method":"account/rateLimits/read","params":null}"#,
                            #"{"id":3,"method":"account/usage/read","params":null}"#
                        ].joined(separator: "\n") + "\n"
                        input.fileHandleForWriting.write(Data(accountQueries.utf8))
                    } else if responseID == 2 || responseID == 3 {
                        receivedAccountResponseIDs.insert(responseID)
                        if receivedAccountResponseIDs.count == 2 {
                            try? input.fileHandleForWriting.close()
                        }
                    }
                }
                return data
            }
            let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codexmicro-plus-plus","version":"1.1.3"}}}"# + "\n"
            input.fileHandleForWriting.write(Data(initialize.utf8))

            let waitResult = await waitForTermination(terminationEvents, timeout: .seconds(5))
            guard case let .terminated(status) = waitResult, status == 0 else {
                try? input.fileHandleForWriting.close()
                if process.isRunning {
                    process.terminate()
                    try? await Task.sleep(for: .milliseconds(250))
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                outputTask.cancel()
                return nil
            }

            let data = try await outputTask.value
            let quota = CodexRolloutParser.liveWeeklyQuota(from: data, observedAt: observedAt)
            let lifetimeTokens = CodexRolloutParser.liveLifetimeTokens(from: data)
            guard quota != nil || lifetimeTokens != nil else { return nil }
            return CodexAccountMetrics(weeklyQuota: quota, lifetimeTokens: lifetimeTokens)
        } catch {
            if process.isRunning { process.terminate() }
            return nil
        }
    }

    private func waitForTermination(
        _ events: AsyncStream<Int32>,
        timeout: Duration
    ) async -> ProcessWaitResult {
        await withTaskGroup(of: ProcessWaitResult.self) { group in
            group.addTask {
                for await status in events {
                    return .terminated(status)
                }
                return .timedOut
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }

            let result = await group.next() ?? .timedOut
            group.cancelAll()
            return result
        }
    }

    private func codexExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    private func latestStoredWeeklyQuota(database: URL) -> WeeklyQuota? {
        let sql = "select rollout_path from threads where rollout_path is not null order by recency_at desc limit 80;"
        guard let data = runSQLite(database: database, sql: sql),
              let rows = try? JSONDecoder().decode([QuotaRow].self, from: data) else { return nil }

        var latest: WeeklyQuota?
        for row in rows {
            let path = row.rollout_path
            let url = URL(fileURLWithPath: path)
            let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
            let fileSize = attributes[.size] as? Int ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast
            let quota: WeeklyQuota?
            if let cached = quotaCache[path],
               cached.fileSize == fileSize,
               cached.modificationDate == modificationDate {
                quota = cached.quota
            } else {
                quota = CodexRolloutParser.weeklyQuota(
                    from: tail(of: url, maximumBytes: 512 * 1_024) ?? Data()
                )
                quotaCache[path] = QuotaCacheEntry(
                    fileSize: fileSize,
                    modificationDate: modificationDate,
                    quota: quota
                )
            }
            latest = newestQuota(latest, quota)
        }
        return latest
    }

    private func newestQuota(_ lhs: WeeklyQuota?, _ rhs: WeeklyQuota?) -> WeeklyQuota? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.observedAt >= rhs.observedAt ? lhs : rhs
    }

    private func newestDatabase() -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return urls
            .filter { $0.lastPathComponent.range(of: #"^state(?:_\d+)?\.sqlite$"#, options: .regularExpression) != nil }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first
    }

    private func runSQLite(database: URL, sql: String) -> Data? {
        guard let result = ProcessOutputReader.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/sqlite3"),
            arguments: ["-json", database.path, sql]
        ), result.status == 0 else { return nil }
        return result.data
    }

    private func tail(of url: URL, maximumBytes: Int) -> Data? {
        guard !url.path.isEmpty, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maximumBytes) ? size - UInt64(maximumBytes) : 0
        try? handle.seek(toOffset: offset)
        return try? handle.readToEnd()
    }
}
