import Foundation
import FirebaseAuth
import FirebaseFirestore

extension AppState {
    func officeShiftEligibleUsers(isAdmin: Bool) -> [User] {
        let eligible = users
            .filter { $0.role == .admin || $0.role == .expert }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if isAdmin { return eligible }
        guard let me = currentUser else { return [] }
        return eligible.contains(where: { $0.id == me.id }) ? [me] : []
    }

    func officeShiftUsers(day: Date, shift: OfficeShiftKind) -> [User] {
        let key = OfficeShiftCalendar.dayKey(for: day)
        let slot = officeShiftSlots.first { $0.dayKey == key && $0.shift == shift }
        let ids = slot?.userIds ?? []
        return ids.compactMap { uid in users.first(where: { $0.id == uid }) }
    }

    func officeShiftSlot(day: Date, shift: OfficeShiftKind) -> OfficeShiftSlot? {
        let key = OfficeShiftCalendar.dayKey(for: day)
        return officeShiftSlots.first { $0.dayKey == key && $0.shift == shift }
    }

    struct OfficeShiftWeekTemplate {
        let weekdayIndex: Int
        let shift: OfficeShiftKind
        let userIds: [String]
    }

    func officeShiftWeekTemplate(monday: Date) -> [OfficeShiftWeekTemplate] {
        let days = OfficeShiftCalendar.weekdaysInWeek(starting: monday)
        return days.enumerated().flatMap { index, day in
            OfficeShiftKind.allCases.map { shift in
                OfficeShiftWeekTemplate(
                    weekdayIndex: index,
                    shift: shift,
                    userIds: officeShiftSlot(day: day, shift: shift)?.userIds ?? []
                )
            }
        }
    }

    @MainActor
    func copyOfficeShiftWeekToFutureWeeks(fromWeekMonday sourceMonday: Date) async -> (weeks: Int, slots: Int)? {
        guard currentUser?.role == .admin else {
            uiErrorMessage = "Nur Admins können den Plan kopieren."
            return nil
        }

        let template = officeShiftWeekTemplate(monday: sourceMonday)
        let targetMondays = OfficeShiftCalendar.futureWeekMondays(afterTemplateMonday: sourceMonday)
        guard !targetMondays.isEmpty else {
            uiErrorMessage = "Keine zukünftigen Wochen mehr in diesem Jahr."
            return nil
        }

        let actorUid = Auth.auth().currentUser?.uid ?? currentUser?.id ?? ""
        var batch = db.batch()
        var batchOps = 0
        var totalSlots = 0

        func commitBatchIfNeeded(force: Bool = false) async throws {
            guard force || batchOps >= 450 else { return }
            guard batchOps > 0 else { return }
            try await batch.commit()
            batch = db.batch()
            batchOps = 0
        }

        do {
            for targetMonday in targetMondays {
                let targetDays = OfficeShiftCalendar.weekdaysInWeek(starting: targetMonday)
                for entry in template {
                    guard entry.weekdayIndex < targetDays.count else { continue }
                    let day = targetDays[entry.weekdayIndex]
                    let docId = OfficeShiftCalendar.documentId(day: day, shift: entry.shift)
                    let ref = db.collection("officeShiftSlots").document(docId)
                    totalSlots += 1

                    if entry.userIds.isEmpty {
                        batch.deleteDocument(ref)
                    } else {
                        batch.setData([
                            "dayKey": OfficeShiftCalendar.dayKey(for: day),
                            "shiftRaw": entry.shift.rawValue,
                            "userIds": entry.userIds,
                            "location": OfficeShiftCalendar.locationName,
                            "updatedAt": FieldValue.serverTimestamp(),
                            "updatedByUid": actorUid
                        ], forDocument: ref, merge: true)
                    }

                    batchOps += 1
                    try await commitBatchIfNeeded()
                }
            }

            try await commitBatchIfNeeded(force: true)
            uiErrorMessage = nil
            showToast(
                .success,
                "Plan auf \(targetMondays.count) Wochen kopiert."
            )
            return (targetMondays.count, totalSlots)
        } catch {
            uiErrorMessage = "Kopieren fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func setOfficeShiftUsers(day: Date, shift: OfficeShiftKind, userIds: [String]) -> Bool {
        let normalizedDay = OfficeShiftCalendar.startOfDay(day)
        let uniqueIds = Array(Set(userIds.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }))

        guard uniqueIds.count <= OfficeShiftCalendar.maxAssigneesPerSlot else {
            uiErrorMessage = "Maximal \(OfficeShiftCalendar.maxAssigneesPerSlot) Mitarbeiter pro Schicht."
            return false
        }

        for otherShift in OfficeShiftKind.allCases where otherShift != shift {
            let otherIds = officeShiftSlot(day: normalizedDay, shift: otherShift)?.userIds ?? []
            for uid in uniqueIds where otherIds.contains(uid) {
                if let user = users.first(where: { $0.id == uid }) {
                    uiErrorMessage = "\(user.name) ist bereits in der anderen Schicht eingetragen."
                } else {
                    uiErrorMessage = "Mitarbeiter ist bereits in der anderen Schicht eingetragen."
                }
                return false
            }
        }

        let isAdmin = currentUser?.role == .admin
        if !isAdmin {
            guard let me = currentUser else {
                uiErrorMessage = "Kein Benutzer angemeldet."
                return false
            }
            guard me.role == .admin || me.role == .expert else {
                uiErrorMessage = "Nur Admin oder Sachverständige können Schichten eintragen."
                return false
            }

            let previousIds = officeShiftSlot(day: normalizedDay, shift: shift)?.userIds ?? []
            let added = Set(uniqueIds).subtracting(previousIds)
            let removed = Set(previousIds).subtracting(uniqueIds)
            let foreignChanges = added.contains(where: { $0 != me.id })
                || removed.contains(where: { $0 != me.id })
            if foreignChanges {
                uiErrorMessage = "Nur Admins können andere Mitarbeiter eintragen."
                return false
            }
        }

        let dayKey = OfficeShiftCalendar.dayKey(for: normalizedDay)
        let docId = OfficeShiftCalendar.documentId(day: normalizedDay, shift: shift)
        let actorUid = Auth.auth().currentUser?.uid ?? currentUser?.id ?? ""

        if uniqueIds.isEmpty {
            if officeShiftSlots.contains(where: { $0.id == docId }) {
                officeShiftSlots.removeAll { $0.id == docId }
                deleteOfficeShiftSlotFromFirestore(docId: docId)
            }
            uiErrorMessage = nil
            showToast(.success, "Schicht geleert.")
            return true
        }

        let slot = OfficeShiftSlot(
            dayKey: dayKey,
            day: normalizedDay,
            shift: shift,
            userIds: uniqueIds,
            updatedAt: Date(),
            updatedByUid: actorUid
        )

        if let index = officeShiftSlots.firstIndex(where: { $0.id == docId }) {
            officeShiftSlots[index] = slot
        } else {
            officeShiftSlots.append(slot)
        }

        upsertOfficeShiftSlotToFirestore(slot)
        uiErrorMessage = nil
        showToast(.success, "Schicht gespeichert.")
        return true
    }

    func startOfficeShiftSlotsListenerIfNeeded() {
        guard officeShiftSlotsListener == nil else { return }
        guard currentUser != nil else { return }

        officeShiftSlotsListener = db.collection("officeShiftSlots")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "Büroschichten: \(error.localizedDescription)"
                    }
                    return
                }

                guard let snapshot else { return }

                firestoreListenerQueue.async { [weak self] in
                    guard let self else { return }
                    let mapped = snapshot.documents.compactMap { self.mapOfficeShiftSlot(from: $0) }
                    DispatchQueue.main.async {
                        self.officeShiftSlots = mapped.sorted {
                            if $0.day != $1.day { return $0.day < $1.day }
                            return $0.shift.rawValue < $1.shift.rawValue
                        }
                    }
                }
            }
    }

    private func mapOfficeShiftSlot(from doc: QueryDocumentSnapshot) -> OfficeShiftSlot? {
        let data = doc.data()
        guard let dayKey = data["dayKey"] as? String, !dayKey.isEmpty else { return nil }
        guard let shiftRaw = data["shiftRaw"] as? String,
              let shift = OfficeShiftKind(rawValue: shiftRaw) else { return nil }

        let userIds = (data["userIds"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let day = officeShiftDay(fromDayKey: dayKey) ?? OfficeShiftCalendar.startOfDay(Date())
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        return OfficeShiftSlot(
            dayKey: dayKey,
            day: day,
            shift: shift,
            userIds: Array(userIds.prefix(OfficeShiftCalendar.maxAssigneesPerSlot)),
            updatedAt: updatedAt,
            updatedByUid: data["updatedByUid"] as? String
        )
    }

    private func officeShiftDay(fromDayKey dayKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = OfficeShiftCalendar.berlin
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = OfficeShiftCalendar.berlin.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return nil }
        return OfficeShiftCalendar.startOfDay(date)
    }

    private func upsertOfficeShiftSlotToFirestore(_ slot: OfficeShiftSlot) {
        let docId = slot.id
        let actorUid = Auth.auth().currentUser?.uid ?? currentUser?.id ?? ""

        let payload: [String: Any] = [
            "dayKey": slot.dayKey,
            "shiftRaw": slot.shift.rawValue,
            "userIds": slot.userIds,
            "location": OfficeShiftCalendar.locationName,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedByUid": actorUid
        ]

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("officeShiftSlots").document(docId).setData(payload, merge: true)
            } catch {
                await MainActor.run {
                    self.uiErrorMessage = "Schicht konnte nicht gespeichert werden: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteOfficeShiftSlotFromFirestore(docId: String) {
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("officeShiftSlots").document(docId).delete()
            } catch {
                await MainActor.run {
                    self.uiErrorMessage = "Schicht konnte nicht gelöscht werden: \(error.localizedDescription)"
                }
            }
        }
    }
}
