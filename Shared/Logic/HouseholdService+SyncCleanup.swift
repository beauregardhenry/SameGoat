import CoreData

// Cleaning up the duplicates that two devices can create before iCloud merges them.
extension HouseholdService {
    // MARK: Sync duplicates

    /// Two parents can approve the same chore or reward request on different devices
    /// before either syncs. Each device then records its own point entry and, for a
    /// repeating chore, its own next copy. Balances already count one entry per source;
    /// this deletes the extras so every device ends up with the same records.
    /// The keeper is chosen the same way on every device, so the deletions never collide.
    func resolveSyncDuplicates(in household: Household) throws {
        let entries = (household.entries as? Set<PointEntry>) ?? []
        let keptEntries = Set(PointEntry.unique(entries).map(\.objectID))
        for entry in entries where !keptEntries.contains(entry.objectID) {
            context.delete(entry)
        }

        let copies = ((household.chores as? Set<Chore>) ?? []).filter { $0.sourceChoreID != nil }
        for group in Dictionary(grouping: copies, by: \.sourceChoreID).values where group.count > 1 {
            // Keep the copy the kid has made the most progress on.
            let keeper = group.max { a, b in
                a.status.progress != b.status.progress ? a.status.progress < b.status.progress : syncOrder(b, a)
            }
            for chore in group where chore !== keeper {
                context.delete(chore)
            }
        }

        // Two devices checking in the same person for the same day: keep the one that counts.
        let keptMoods = Set(FamilyMood.checkIns(in: household).map(\.objectID))
        for mood in (household.moods as? Set<MoodCheckIn>) ?? [] where !keptMoods.contains(mood.objectID) {
            context.delete(mood)
        }
        try save()
    }
}
