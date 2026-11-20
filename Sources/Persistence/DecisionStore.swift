import Foundation
import SwiftData

@Observable
@MainActor
final class DecisionStore {
    private let modelContext: ModelContext

    // O(1) RAM-кэш для мгновенного чтения при 50 000+ активах
    private(set) var decisions: [String: DecisionStatus] = [:]
    private(set) var stagedSizes: [String: Int64] = [:]
    private(set) var stats: StatsSnapshot = .empty
    private(set) var isHydrated: Bool = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Hydration (Загрузка из БД в RAM при старте)

    func hydrate() {
        guard !isHydrated else { return }

        // 1. Загрузка всех решений в RAM
        let decisionDescriptor = FetchDescriptor<MediaDecisionRecord>()
        if let records = try? modelContext.fetch(decisionDescriptor) {
            var loadedDecisions: [String: DecisionStatus] = [:]
            loadedDecisions.reserveCapacity(records.count)
            for record in records {
                loadedDecisions[record.assetIdentifier] = record.status
            }
            self.decisions = loadedDecisions
        }

        // 2. Загрузка глобальной статистики
        let statsRecord = fetchOrCreateStatsRecord()
        self.stats = statsRecord.snapshot

        self.isHydrated = true
    }

    // MARK: - O(1) чтение из памяти

    func status(for assetID: String) -> DecisionStatus? {
        decisions[assetID]
    }

    var stagedAssetIDs: [String] {
        decisions.compactMap { $0.value == .stagedForTrash ? $0.key : nil }
    }

    var stagedCount: Int {
        stagedAssetIDs.count
    }

    var stagedTotalBytes: Int64 {
        stagedSizes.values.reduce(0, +)
    }

    func setStagedSize(for assetID: String, bytes: Int64) {
        if decisions[assetID] == .stagedForTrash {
            stagedSizes[assetID] = bytes
        }
    }

    // MARK: - Подсчёт прогресса группы (O(N) по группе, O(1) по каждому активу в RAM)

    func progress(for group: MediaGroup) -> GroupProgress {
        var kept = 0
        var staged = 0
        var stagedBytes: Int64 = 0

        for id in group.assetIDs {
            if let st = decisions[id] {
                switch st {
                case .kept:
                    kept += 1
                case .stagedForTrash:
                    staged += 1
                    stagedBytes += stagedSizes[id] ?? 0
                }
            }
        }

        return GroupProgress(
            totalCount: group.assetIDs.count,
            keptCount: kept,
            stagedCount: staged,
            stagedBytes: stagedBytes
        )
    }

    // MARK: - Запись решения

    func recordDecision(assetID: String, status: DecisionStatus, estimatedBytes: Int64 = 0) {
        let isFirstSwipe = (decisions[assetID] == nil)

        decisions[assetID] = status
        if status == .stagedForTrash {
            stagedSizes[assetID] = estimatedBytes
        } else {
            stagedSizes.removeValue(forKey: assetID)
        }

        // Правило статистики: первый свайп увеличивает totalReviewedCount
        if isFirstSwipe {
            let statsRecord = fetchOrCreateStatsRecord()
            statsRecord.totalReviewedCount += 1
            statsRecord.lastUpdated = Date()
            self.stats = statsRecord.snapshot
        }

        let targetID = assetID
        let descriptor = FetchDescriptor<MediaDecisionRecord>(
            predicate: #Predicate<MediaDecisionRecord> { $0.assetIdentifier == targetID }
        )

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.status = status
            existing.timestamp = Date()
        } else {
            let record = MediaDecisionRecord(assetIdentifier: assetID, status: status)
            modelContext.insert(record)
        }

        saveContext()
    }

    // MARK: - Откат последнего решения (Undo)

    func undoDecision(assetID: String) {
        guard decisions[assetID] != nil else { return }

        decisions.removeValue(forKey: assetID)
        stagedSizes.removeValue(forKey: assetID)

        // Правило статистики: Undo уменьшает totalReviewedCount
        let statsRecord = fetchOrCreateStatsRecord()
        statsRecord.totalReviewedCount = max(0, statsRecord.totalReviewedCount - 1)
        statsRecord.lastUpdated = Date()
        self.stats = statsRecord.snapshot

        let targetID = assetID
        let descriptor = FetchDescriptor<MediaDecisionRecord>(
            predicate: #Predicate<MediaDecisionRecord> { $0.assetIdentifier == targetID }
        )

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            modelContext.delete(existing)
        }

        saveContext()
    }

    // MARK: - Спасение из корзины

    func rescueFromTrash(assetID: String) {
        guard decisions[assetID] == .stagedForTrash else { return }

        // «Спасение» из Корзины -> переводит статус в .kept (totalReviewedCount не меняется)
        decisions[assetID] = .kept
        stagedSizes.removeValue(forKey: assetID)

        let targetID = assetID
        let descriptor = FetchDescriptor<MediaDecisionRecord>(
            predicate: #Predicate<MediaDecisionRecord> { $0.assetIdentifier == targetID }
        )

        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.status = .kept
            existing.timestamp = Date()
        }

        saveContext()
    }

    func rescueMultipleFromTrash(assetIDs: [String]) {
        for id in assetIDs {
            rescueFromTrash(assetID: id)
        }
    }

    // MARK: - Фиксация физического удаления из корзины

    func commitDeleted(assetIDs: [String], freedBytes: Int64) {
        guard !assetIDs.isEmpty else { return }

        for id in assetIDs {
            decisions.removeValue(forKey: id)
            stagedSizes.removeValue(forKey: id)

            let targetID = id
            let descriptor = FetchDescriptor<MediaDecisionRecord>(
                predicate: #Predicate<MediaDecisionRecord> { $0.assetIdentifier == targetID }
            )
            if let records = try? modelContext.fetch(descriptor) {
                for record in records {
                    modelContext.delete(record)
                }
            }
        }

        let statsRecord = fetchOrCreateStatsRecord()
        statsRecord.totalDeletedCount += assetIDs.count
        statsRecord.totalBytesFreed += freedBytes
        statsRecord.lastUpdated = Date()
        self.stats = statsRecord.snapshot

        saveContext()
    }

    // MARK: - Сброс прогресса

    func resetKeptDecisions(for specificIDs: [String]? = nil) {
        if let specificIDs = specificIDs {
            for id in specificIDs where decisions[id] == .kept {
                decisions.removeValue(forKey: id)

                let targetID = id
                let descriptor = FetchDescriptor<MediaDecisionRecord>(
                    predicate: #Predicate<MediaDecisionRecord> { $0.assetIdentifier == targetID }
                )
                if let records = try? modelContext.fetch(descriptor) {
                    for record in records {
                        modelContext.delete(record)
                    }
                }
            }
        } else {
            let keptIDs = decisions.filter { $0.value == .kept }.map { $0.key }
            for id in keptIDs {
                decisions.removeValue(forKey: id)
            }

            let keptRaw = DecisionStatus.kept.rawValue
            let descriptor = FetchDescriptor<MediaDecisionRecord>(
                predicate: #Predicate<MediaDecisionRecord> { $0.statusRaw == keptRaw }
            )
            if let records = try? modelContext.fetch(descriptor) {
                for record in records {
                    modelContext.delete(record)
                }
            }
        }

        saveContext()
    }

    // MARK: - Очистка удалённых извне активов (Pruning)

    func pruneMissingAssets(validIDs: Set<String>) {
        let missingIDs = decisions.keys.filter { !validIDs.contains($0) }
        guard !missingIDs.isEmpty else { return }

        for id in missingIDs {
            decisions.removeValue(forKey: id)
            stagedSizes.removeValue(forKey: id)

            let targetID = id
            let descriptor = FetchDescriptor<MediaDecisionRecord>(
                predicate: #Predicate<MediaDecisionRecord> { $0.assetIdentifier == targetID }
            )
            if let records = try? modelContext.fetch(descriptor) {
                for record in records {
                    modelContext.delete(record)
                }
            }
        }

        saveContext()
    }

    // MARK: - Вспомогательные методы

    private func fetchOrCreateStatsRecord() -> CleaningStatsRecord {
        let statsID = "global_stats"
        let descriptor = FetchDescriptor<CleaningStatsRecord>(
            predicate: #Predicate<CleaningStatsRecord> { $0.id == statsID }
        )
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        } else {
            let newRecord = CleaningStatsRecord(id: statsID)
            modelContext.insert(newRecord)
            return newRecord
        }
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("⚠️ DecisionStore: Ошибка сохранения контекста: \(error)")
        }
    }
}
