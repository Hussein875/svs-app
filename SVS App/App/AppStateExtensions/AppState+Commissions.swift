import Foundation
import FirebaseAuth
import FirebaseFirestore

extension AppState {
    // MARK: - Firestore Commissions Listener

    func startCommissionsListenerIfNeeded() {
        guard commissionsListener == nil else { return }
        guard let me = currentUser else { return }

        var query: Query = db.collection("commissions")

        // Admin: alles; Nicht-Admin: nur eigene erstellte Prämien
        if me.role != .admin {
            query = query.whereField("createdByUid", isEqualTo: me.id)
        }

        query = query.order(by: "createdAt", descending: true)

        commissionsListener = query.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage =
                    "Prämien konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }

                let mapped: [CommissionEntry] = docs.compactMap { doc in
                    guard let dto = CommissionDTO(id: doc.documentID, data: doc.data()) else {
                        return nil
                    }
                    let uuid = UUID(uuidString: dto.id) ?? UUID(uuidString: doc.documentID)
                    guard let uuid else { return nil }

                    let status = CommissionStatus(rawValue: dto.statusRaw) ?? .submitted
                    let method = PayoutMethod(rawValue: dto.payoutMethodRaw) ?? .paypal

                    return CommissionEntry(
                        id: uuid,
                        recipientName: dto.recipientName,
                        recipientAddress: dto.recipientAddress,
                        amountEUR: Decimal(dto.amount),
                        payoutMethod: method,
                        payoutTarget: dto.payoutTarget,
                        status: status,
                        createdAt: dto.createdAt.dateValue(),
                        createdByUserId: dto.createdByUid,
                        paidAt: dto.paidAt?.dateValue(),
                        paidByUserId: dto.paidByUid
                    )
                }

                DispatchQueue.main.async { [weak self] in
                    self?.commissions = mapped
                }
            }
        }
    }

    private func upsertCommissionToFirestore(_ entry: CommissionEntry) {
        guard let actorUid = Auth.auth().currentUser?.uid else { return }
        let dto = CommissionDTO(from: entry, actorUid: actorUid)

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("commissions").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
            } catch {
                let msg = "Prämie konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func deleteCommissionFromFirestore(_ entry: CommissionEntry) {
        let docId = entry.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("commissions").document(docId).delete()
            } catch {
                let msg = "Prämie konnte nicht gelöscht werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }
    
    func userName(for userId: String) -> String {
        users.first(where: { $0.id == userId })?.name ?? "Unbekannt"
    }
    
    func usedVacationDays(for user: User) -> Int {
        let requestsForUser = leaveRequests.filter {
            $0.user.id == user.id &&
            $0.status == .approved &&
            $0.type == .vacation
        }
        return requestsForUser.reduce(0) { partial, req in
            let days = workingDays(from: req.startDate, to: req.endDate)
            return partial + max(days, 0)
        }
    }
    
    func remainingLeaveDays(for user: User) -> Int {
        let used = usedVacationDays(for: user)
        return max(user.annualLeaveDays - used, 0)
    }
    
    func reservedVacationDays(for user: User, excludingRequestId: UUID? = nil) -> Int {
        let requestsForUser = leaveRequests.filter { request in
            guard request.user.id == user.id,
                  request.type == .vacation,
                  request.status != .rejected else {
                return false
            }
            if let excludedRequestId = excludingRequestId {
                return request.id != excludedRequestId
            }
            return true
        }
        
        return requestsForUser.reduce(0) { partial, req in
            partial + max(workingDays(from: req.startDate, to: req.endDate), 0)
        }
    }
    
    func availableVacationDaysForRequests(for user: User, excludingRequestId: UUID? = nil) -> Int {
        let reserved = reservedVacationDays(for: user, excludingRequestId: excludingRequestId)
        return max(user.annualLeaveDays - reserved, 0)
    }
    
    
    func currencyString(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "EUR"
        nf.locale = Locale(identifier: "de_DE")
        return nf.string(from: amount as NSDecimalNumber) ?? "€\(amount)"
    }
    
    func createCommission(recipientName: String,
                          recipientAddress: String,
                          amountEUR: Decimal,
                          payoutMethod: PayoutMethod,
                          payoutTarget: String) {
        guard let creator = currentUser else { return }
        guard let admin = users.first(where: { $0.role == .admin }) else { return }
        
        let normalizedTarget: String = {
            switch payoutMethod {
            case .paypal:
                return payoutTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            case .iban:
                return payoutTarget
                    .replacingOccurrences(of: " ", with: "")
                    .uppercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }()
        
        let entry = CommissionEntry(
            id: UUID(),
            recipientName: recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
            recipientAddress: recipientAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            amountEUR: amountEUR,
            payoutMethod: payoutMethod,
            payoutTarget: normalizedTarget,
            status: .open,
            createdAt: Date(),
            createdByUserId: creator.id,
            paidAt: nil,
            paidByUserId: nil
        )
        
        commissions.append(entry)
        upsertCommissionToFirestore(entry)
        
        // Task beim Admin erzeugen
        let amountString = currencyString(amountEUR)
        var details = "Empfänger: \(entry.recipientName)\n"
        details += "Adresse: \(entry.recipientAddress)\n"
        details += "Betrag: \(amountString)\n"
        details += "Auszahlung: \(entry.payoutMethod.rawValue) – \(entry.payoutTarget)\n"
        details += "Gemeldet von: \(creator.name)\n"
        
        createTask(
            title: "Prämie zahlen – \(entry.recipientName)",
            details: details,
            dueDate: nil,
            assignedUser: admin,
            creator: creator
        )
    }
    
    func commissionHistory(for user: User) -> [CommissionEntry] {
        commissions
            .filter { $0.createdByUserId == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    func allCommissionHistory() -> [CommissionEntry] {
        commissions.sorted { $0.createdAt > $1.createdAt }
    }
    
    func markCommissionPaid(_ entry: CommissionEntry) {
        guard let admin = currentUser, admin.role == .admin else { return }
        guard let idx = commissions.firstIndex(where: { $0.id == entry.id }) else { return }
        commissions[idx].status = .paid
        commissions[idx].paidAt = Date()
        commissions[idx].paidByUserId = admin.id
        upsertCommissionToFirestore(commissions[idx])
    }
    
    func deleteCommission(_ entry: CommissionEntry) {
        guard let admin = currentUser, admin.role == .admin else { return }
        deleteCommissionFromFirestore(entry)
        commissions.removeAll { $0.id == entry.id }
    }
    

}
