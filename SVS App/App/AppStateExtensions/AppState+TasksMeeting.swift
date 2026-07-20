import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

extension AppState {
    // MARK: - Task Management

    func procurementOfficerUser() -> User? {
        TaskProcurement.resolveOfficer(in: users)
    }

    func createTask(title: String,
                    details: String,
                    dueDate: Date?,
                    assignedUser: User,
                    creator: User,
                    kind: TaskKind = .general) {
        let creatorUid = canonicalCurrentUid(fallback: creator) ?? creator.id
        let assignedUid = normalizedIdentity(assignedUser.id)

        let newTask = Task(
            id: UUID(),
            title: title,
            details: details,
            dueDate: dueDate,
            status: .open,
            kind: kind,
            assignedUserId: assignedUid.isEmpty ? assignedUser.id : assignedUid,
            creatorUserId: normalizedIdentity(creatorUid),
            createdAt: Date(),
            updatedAt: nil,
            updatedByUserId: nil
        )

        // Optimistic UI
        pendingTaskDeletionIds.remove(newTask.id)
        pendingTaskWritesById[newTask.id] = newTask
        mergeTaskSnapshotsAndPublish()
        createTaskInFirestore(newTask)
    }

    func updateTask(_ task: Task) {
        let permissionSource = tasks.first(where: { $0.id == task.id }) ?? task
        guard canEditTask(permissionSource, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht bearbeiten.")
            return
        }

        var patched = task
        patched.updatedAt = Date()
        patched.updatedByUserId = canonicalCurrentUid(fallback: currentUser) ?? currentUser?.id

        pendingTaskDeletionIds.remove(patched.id)
        pendingTaskWritesById[patched.id] = patched
        mergeTaskSnapshotsAndPublish()

        updateTaskInFirestore(patched)
    }

    func toggleTaskStatus(for task: Task) {
        guard canEditTask(task, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht ändern.")
            return
        }

        var updated = task
        updated.status = (task.status == .open) ? .done : .open
        updateTask(updated)
    }

    func deleteTask(_ task: Task) {
        guard canDeleteTask(task, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Task nicht löschen.")
            return
        }

        pendingTaskWritesById.removeValue(forKey: task.id)
        pendingTaskDeletionIds.insert(task.id)
        mergeTaskSnapshotsAndPublish()
        deleteTaskFromFirestore(task)
    }

    func canEditMeetingTopic(_ : MeetingTopic, by user: User?) -> Bool {
        user != nil
    }

    func canDeleteMeetingTopic(_ topic: MeetingTopic, by user: User?) -> Bool {
        guard let user else { return false }
        if user.role == .admin { return true }
        return currentIdentitySet(for: user).contains(normalizedIdentity(topic.createdByUserId))
    }

    func createMeetingTopic(title: String, details: String) {
        guard let creator = currentUser else { return }
        let creatorId = canonicalCurrentUid(fallback: creator) ?? creator.id
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            showToast(.error, "Bitte einen Titel für den Meeting-Punkt eingeben.")
            return
        }

        let topic = MeetingTopic(
            id: UUID(),
            title: cleanTitle,
            details: cleanDetails,
            status: .open,
            createdAt: Date(),
            createdByUserId: creatorId,
            updatedAt: nil,
            updatedByUserId: nil
        )

        pendingMeetingTopicDeletionIds.remove(topic.id)
        pendingMeetingTopicWritesById[topic.id] = topic
        mergeMeetingTopicSnapshotsAndPublish()
        showToast(.success, "Meeting-Punkt hinzugefügt.")
        upsertMeetingTopicToFirestore(topic)
    }

    func toggleMeetingTopicStatus(for topic: MeetingTopic) {
        guard canEditMeetingTopic(topic, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Meeting-Punkt nicht ändern.")
            return
        }

        var patched = topic
        patched.status = (topic.status == .open) ? .done : .open
        patched.updatedAt = Date()
        patched.updatedByUserId = canonicalCurrentUid(fallback: currentUser) ?? currentUser?.id

        pendingMeetingTopicDeletionIds.remove(patched.id)
        pendingMeetingTopicWritesById[patched.id] = patched
        mergeMeetingTopicSnapshotsAndPublish()
        upsertMeetingTopicToFirestore(patched)
    }

    func deleteMeetingTopic(_ topic: MeetingTopic) {
        guard canDeleteMeetingTopic(topic, by: currentUser) else {
            showToast(.error, "Sie dürfen diesen Meeting-Punkt nicht löschen.")
            return
        }

        pendingMeetingTopicWritesById.removeValue(forKey: topic.id)
        pendingMeetingTopicDeletionIds.insert(topic.id)
        mergeMeetingTopicSnapshotsAndPublish()
        deleteMeetingTopicFromFirestore(topic)
    }

    func canEditNextMeeting(by user: User?) -> Bool {
        user?.role == .admin
    }

    func canArchiveMeeting(by user: User?) -> Bool {
        user?.role == .admin
    }

    func canDeleteMeetingArchive(by user: User?) -> Bool {
        user?.role == .admin
    }

    @MainActor
    @discardableResult
    func updateMeetingArchiveProtocol(
        _ archive: MeetingArchive,
        protocolText: String
    ) async -> Bool {
        guard canDeleteMeetingArchive(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen das Protokoll bearbeiten.")
            return false
        }

        let cleaned = protocolText.trimmingCharacters(in: .whitespacesAndNewlines)
        let docId = archive.id.uuidString

        do {
            let functions = Functions.functions(region: "us-central1")
            _ = try await functions.httpsCallable("adminUpdateMeetingArchiveProtocol").call([
                "archiveId": docId,
                "protocolText": cleaned
            ])

            if let cacheIdx = meetingArchivesSnapshotCache.firstIndex(where: { $0.id == archive.id }) {
                meetingArchivesSnapshotCache[cacheIdx].protocolText = cleaned
            }
            if let listIdx = meetingArchives.firstIndex(where: { $0.id == archive.id }) {
                meetingArchives[listIdx].protocolText = cleaned
            }

            uiErrorMessage = nil
            showToast(.success, "Protokoll gespeichert.")
            return true
        } catch {
            let msg = meetingArchiveErrorMessage(
                prefix: "Protokoll konnte nicht gespeichert werden",
                error: error
            )
            uiErrorMessage = msg
            showToast(.error, msg)
            return false
        }
    }

    @MainActor
    func archiveCurrentMeeting() async {
        guard canArchiveMeeting(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen Meetings archivieren.")
            return
        }

        let topicsToArchive = meetingTopics
            .sorted {
                let lhs = $0.updatedAt ?? $0.createdAt
                let rhs = $1.updatedAt ?? $1.createdAt
                return lhs < rhs
            }

        guard !topicsToArchive.isEmpty else {
            showToast(.error, "Keine Meeting-Punkte zum Archivieren vorhanden.")
            return
        }

        let meetingDate = nextMeetingAt ?? Date()
        let actorUid = canonicalCurrentUid(fallback: currentUser)
            ?? currentUser?.id
            ?? ""
        let archiveId = UUID().uuidString
        let archiveRef = db.collection("meetingArchives").document(archiveId)
        let meetingMetaRef = db.collection("meetingMeta").document("schedule")

        let topicsPayload: [[String: Any]] = topicsToArchive.map { topic in
            var d: [String: Any] = [
                "id": topic.id.uuidString,
                "title": topic.title,
                "details": topic.details,
                "statusRaw": topic.status.rawValue,
                "createdAt": Timestamp(date: topic.createdAt),
                "createdByUserId": topic.createdByUserId
            ]
            if let updatedAt = topic.updatedAt {
                d["updatedAt"] = Timestamp(date: updatedAt)
            }
            if let updatedByUserId = topic.updatedByUserId, !updatedByUserId.isEmpty {
                d["updatedByUserId"] = updatedByUserId
            }
            return d
        }

        let protocolText = buildMeetingProtocol(
            topics: topicsToArchive,
            meetingDate: meetingDate
        )

        let archiveData: [String: Any] = [
            "meetingDate": Timestamp(date: meetingDate),
            "archivedAt": FieldValue.serverTimestamp(),
            "archivedByUserId": actorUid,
            "topicCount": topicsToArchive.count,
            "protocolText": protocolText,
            "topics": topicsPayload
        ]

        do {
            let batch = db.batch()
            batch.setData(archiveData, forDocument: archiveRef, merge: false)
            batch.setData([
                "nextMeetingAt": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp(),
                "updatedByUserId": actorUid
            ], forDocument: meetingMetaRef, merge: true)

            for topic in topicsToArchive {
                let topicRef = db.collection("meetingTopics")
                    .document(topic.id.uuidString)
                batch.deleteDocument(topicRef)
            }

            try await batch.commit()

            // Clear local active points immediately; listener will reconcile shortly.
            meetingTopicsSnapshotCache = []
            pendingMeetingTopicWritesById = [:]
            pendingMeetingTopicDeletionIds = []
            meetingTopics = []
            nextMeetingAt = nil

            uiErrorMessage = nil
            showToast(
                .success,
                "Meeting archiviert. \(topicsToArchive.count) Punkt(e) verschoben."
            )
        } catch {
            let msg = meetingArchiveErrorMessage(
                prefix: "Meeting konnte nicht archiviert werden",
                error: error
            )
            uiErrorMessage = msg
            showToast(.error, msg)
        }
    }

    func clearNextMeetingDate() {
        guard canEditNextMeeting(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen den Meeting-Termin löschen.")
            return
        }

        let actor = canonicalCurrentUid(fallback: currentUser)
        var payload: [String: Any] = [
            "nextMeetingAt": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let actor {
            payload["updatedByUserId"] = actor
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingMeta").document("schedule")
                    .setData(payload, merge: true)
                await MainActor.run {
                    self.nextMeetingAt = nil
                    self.uiErrorMessage = nil
                    self.showToast(.success, "Meeting-Termin gelöscht.")
                }
            } catch {
                let msg = "Meeting-Termin konnte nicht gelöscht werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    func deleteMeetingArchive(_ archive: MeetingArchive) {
        guard canDeleteMeetingArchive(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen archivierte Meetings löschen.")
            return
        }

        let docId = archive.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let functions = Functions.functions(region: "us-central1")
                _ = try await functions.httpsCallable("adminDeleteMeetingArchive").call([
                    "archiveId": docId
                ])
                await MainActor.run {
                    self.meetingArchivesSnapshotCache.removeAll { $0.id == archive.id }
                    self.meetingArchives.removeAll { $0.id == archive.id }
                    self.uiErrorMessage = nil
                    self.showToast(.success, "Archiviertes Meeting gelöscht.")
                }
            } catch {
                let msg = self.meetingArchiveErrorMessage(
                    prefix: "Archiviertes Meeting konnte nicht gelöscht werden",
                    error: error
                )
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    func saveNextMeeting(date: Date) {
        guard canEditNextMeeting(by: currentUser) else {
            showToast(.error, "Nur Admins dürfen den Meeting-Termin bearbeiten.")
            return
        }

        let actor = canonicalCurrentUid(fallback: currentUser)
        var payload: [String: Any] = [
            "nextMeetingAt": Timestamp(date: date),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let actor {
            payload["updatedByUserId"] = actor
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingMeta").document("schedule")
                    .setData(payload, merge: true)
                await MainActor.run {
                    self.nextMeetingAt = date
                    self.uiErrorMessage = nil
                    self.showToast(.success, "Nächstes Meeting aktualisiert.")
                }
            } catch {
                let msg = "Meeting-Termin konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    @MainActor
    func refreshMeetingTopicsFromServer() async {
        do {
            let topicsSnap = try await db.collection("meetingTopics")
                .order(by: "createdAt", descending: true)
                .getDocuments(source: .server)

            meetingTopicsSnapshotCache = mapMeetingTopicsFromDocs(topicsSnap.documents)
            mergeMeetingTopicSnapshotsAndPublish()
            uiErrorMessage = nil
        } catch {
            let msg = "Meeting-Punkte konnten nicht aktualisiert werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
            return
        }

        do {
            let archivesSnap = try await db.collection("meetingArchives")
                .order(by: "meetingDate", descending: true)
                .getDocuments(source: .server)

            meetingArchivesSnapshotCache = mapMeetingArchivesFromDocs(archivesSnap.documents)
            meetingArchives = meetingArchivesSnapshotCache
        } catch {
            // Archive read can be intentionally restricted by rules.
            // Do not fail the whole meeting refresh in that case.
            if isPermissionDeniedError(error) {
                meetingArchivesSnapshotCache = []
                meetingArchives = []
                return
            }

            let msg = "Meeting-Archiv konnte nicht aktualisiert werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
        }
    }

    private func buildMeetingProtocol(
        topics: [MeetingTopic],
        meetingDate: Date
    ) -> String {
        let dateText = meetingArchiveDateString(meetingDate)

        var lines: [String] = [
            "Meetingprotokoll vom \(dateText)",
            "",
            "Punkte (\(topics.count)):"
        ]

        for (index, topic) in topics.enumerated() {
            let statusText = topic.status == .done ? "Erledigt" : "Offen"
            var line = "\(index + 1). \(topic.title) [\(statusText)]"
            let cleanDetails = topic.details.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanDetails.isEmpty {
                line += " - \(cleanDetails)"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    private func meetingArchiveDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.string(from: date)
    }

    @MainActor
    func refreshTasksFromServer() async {
        guard let me = currentUser else { return }
        guard let meUid = canonicalCurrentUid(fallback: me), !meUid.isEmpty else { return }

        do {
            if me.role == .admin {
                let snap = try await db.collection("tasks")
                    .order(by: "createdAt", descending: true)
                    .getDocuments(source: .server)

                tasksAssignedSnapshotCache = mapTasksFromDocs(snap.documents)
                tasksCreatedByMeSnapshotCache = []
                mergeTaskSnapshotsAndPublish()
            } else {
                async let assignedSnap = db.collection("tasks")
                    .whereField("assignedUserId", isEqualTo: meUid)
                    .getDocuments(source: .server)

                async let createdSnap = db.collection("tasks")
                    .whereField("creatorUserId", isEqualTo: meUid)
                    .getDocuments(source: .server)

                let (assigned, created) = try await (assignedSnap, createdSnap)
                tasksAssignedSnapshotCache = mapTasksFromDocs(assigned.documents)
                tasksCreatedByMeSnapshotCache = mapTasksFromDocs(created.documents)
                mergeTaskSnapshotsAndPublish()
            }

            uiErrorMessage = nil
        } catch {
            let msg = "Tasks konnten nicht aktualisiert werden: \(error.localizedDescription)"
            uiErrorMessage = msg
            showToast(.error, msg)
        }
    }
    

    // MARK: - Firestore Tasks Listener

    private func mapTasksFromDocs(_ docs: [QueryDocumentSnapshot]) -> [Task] {
        docs.compactMap { doc in
            guard let dto = TaskDTO(id: doc.documentID, data: doc.data()) else { return nil }
            guard let uuid = UUID(uuidString: dto.id) else { return nil }

            let status = TaskStatus(rawValue: dto.statusRaw) ?? .open
            let kind = TaskKind(rawValue: dto.kindRaw ?? "") ?? .general

            return Task(
                id: uuid,
                title: dto.title,
                details: dto.details,
                dueDate: dto.dueDate?.dateValue(),
                status: status,
                kind: kind,
                assignedUserId: normalizedIdentity(dto.assignedUserId),
                creatorUserId: normalizedIdentity(dto.creatorUserId),
                createdAt: dto.createdAt.dateValue(),
                updatedAt: dto.updatedAt?.dateValue(),
                updatedByUserId: dto.updatedByUserId
            )
        }
    }

    private func mergeTaskSnapshotsAndPublish() {
        var byId: [UUID: Task] = [:]
        for task in tasksAssignedSnapshotCache { byId[task.id] = task }
        for task in tasksCreatedByMeSnapshotCache { byId[task.id] = task }

        // Snapshot has this task now -> no longer pending.
        for id in byId.keys {
            pendingTaskWritesById.removeValue(forKey: id)
            pendingTaskDeletionIds.remove(id)
        }

        // Keep local deletes hidden until server/listener catches up.
        for id in pendingTaskDeletionIds {
            byId.removeValue(forKey: id)
        }

        // Keep local creates/updates visible immediately.
        for (id, task) in pendingTaskWritesById where !pendingTaskDeletionIds.contains(id) {
            byId[id] = task
        }

        let merged = Array(byId.values).sorted { $0.createdAt > $1.createdAt }
        DispatchQueue.main.async { [weak self] in
            self?.tasks = merged
        }
    }

    func startTasksListenerIfNeeded() {
        guard tasksListener == nil else { return }
        guard tasksCreatedByMeListener == nil else { return }
        guard let me = currentUser else { return }
        guard let meUid = canonicalCurrentUid(fallback: me), !meUid.isEmpty else { return }

        // Admin: sieht alles in einem Listener.
        if me.role == .admin {
            let query = db.collection("tasks").order(by: "createdAt", descending: true)
            tasksListener = query.addSnapshotListener(includeMetadataChanges: false) {
                [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "Tasks konnten nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }

                let docs = snapshot?.documents ?? []
                self.firestoreListenerQueue.async { [weak self] in
                    guard let self else { return }
                    self.tasksAssignedSnapshotCache = self.mapTasksFromDocs(docs)
                    self.tasksCreatedByMeSnapshotCache = []
                    self.mergeTaskSnapshotsAndPublish()
                }
            }
            return
        }

        // Non-admin: merge two sources
        let assignedQuery = db.collection("tasks")
            .whereField("assignedUserId", isEqualTo: meUid)

        tasksListener = assignedQuery.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Tasks (für mich) konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.tasksAssignedSnapshotCache = self.mapTasksFromDocs(docs)
                self.mergeTaskSnapshotsAndPublish()
            }
        }

        let createdByMeQuery = db.collection("tasks")
            .whereField("creatorUserId", isEqualTo: meUid)

        tasksCreatedByMeListener = createdByMeQuery.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Tasks (von mir) konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []

            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.tasksCreatedByMeSnapshotCache = self.mapTasksFromDocs(docs)
                self.mergeTaskSnapshotsAndPublish()
            }
        }
    }

    private func createTaskInFirestore(_ task: Task) {
        let dto = TaskDTO(from: task)

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("tasks").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
            } catch {
                let msg = "Task konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.pendingTaskWritesById.removeValue(forKey: task.id)
                    self.mergeTaskSnapshotsAndPublish()
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func updateTaskInFirestore(_ task: Task) {
        let docId = task.id.uuidString

        var payload: [String: Any] = [
            "title": task.title,
            "details": task.details,
            "statusRaw": task.status.rawValue,
            "assignedUserId": task.assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let dueDate = task.dueDate {
            payload["dueDate"] = Timestamp(date: dueDate)
        } else {
            payload["dueDate"] = FieldValue.delete()
        }

        if let updatedBy = task.updatedByUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !updatedBy.isEmpty {
            payload["updatedByUserId"] = updatedBy
        } else {
            payload["updatedByUserId"] = FieldValue.delete()
        }

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("tasks").document(docId).updateData(payload)
            } catch {
                let msg = "Task konnte nicht gespeichert werden: \(error.localizedDescription)"
                await MainActor.run {
                    self.pendingTaskWritesById.removeValue(forKey: task.id)
                    self.mergeTaskSnapshotsAndPublish()
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func deleteTaskFromFirestore(_ task: Task) {
        let docId = task.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("tasks").document(docId).delete()
            } catch {
                // Kein Nutzer-Fehlerbanner hier: In manchen Fällen ist der Delete
                // serverseitig bereits durch, obwohl lokal ein Fehler zurückkommt.
                await MainActor.run {
                    self.uiErrorMessage = nil
                }
            }
        }
    }

        // MARK: - Firestore MeetingTopics / MeetingArchives Listener

    private func mapMeetingTopicsFromDocs(_ docs: [QueryDocumentSnapshot]) -> [MeetingTopic] {
        docs.compactMap { doc in
            guard let dto = MeetingTopicDTO(id: doc.documentID, data: doc.data()) else { return nil }
            guard let id = UUID(uuidString: dto.id) else { return nil }

            let status = MeetingTopicStatus(rawValue: dto.statusRaw) ?? .open

            return MeetingTopic(
                id: id,
                title: dto.title,
                details: dto.details,
                status: status,
                createdAt: dto.createdAt.dateValue(),
                createdByUserId: dto.createdByUserId,
                updatedAt: dto.updatedAt?.dateValue(),
                updatedByUserId: dto.updatedByUserId
            )
        }
    }

    private func mapMeetingArchivesFromDocs(_ docs: [QueryDocumentSnapshot]) -> [MeetingArchive] {
        docs.compactMap { doc in
            guard let dto = MeetingArchiveDTO(id: doc.documentID, data: doc.data()) else { return nil }
            guard let archiveId = UUID(uuidString: dto.id) else { return nil }

            let mappedTopics: [MeetingTopic] = dto.topics.compactMap { topicData in
                guard
                    let topicIdRaw = topicData["id"] as? String,
                    let topicId = UUID(uuidString: topicIdRaw),
                    let title = topicData["title"] as? String,
                    let statusRaw = topicData["statusRaw"] as? String,
                    let createdByUserId = topicData["createdByUserId"] as? String
                else {
                    return nil
                }

                let createdAt = (topicData["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                let status = MeetingTopicStatus(rawValue: statusRaw) ?? .open
                let details = (topicData["details"] as? String) ?? ""
                let updatedAt = (topicData["updatedAt"] as? Timestamp)?.dateValue()
                let updatedBy = topicData["updatedByUserId"] as? String

                return MeetingTopic(
                    id: topicId,
                    title: title,
                    details: details,
                    status: status,
                    createdAt: createdAt,
                    createdByUserId: createdByUserId,
                    updatedAt: updatedAt,
                    updatedByUserId: updatedBy
                )
            }

            return MeetingArchive(
                id: archiveId,
                meetingDate: dto.meetingDate.dateValue(),
                archivedAt: dto.archivedAt?.dateValue() ?? dto.meetingDate.dateValue(),
                archivedByUserId: dto.archivedByUserId,
                topicCount: dto.topicCount,
                protocolText: dto.protocolText,
                topics: mappedTopics
            )
        }
        .sorted { $0.meetingDate > $1.meetingDate }
    }

    private func mergeMeetingTopicSnapshotsAndPublish() {
        var byId: [UUID: MeetingTopic] = [:]

        for topic in meetingTopicsSnapshotCache {
            byId[topic.id] = topic
        }

        for id in byId.keys {
            pendingMeetingTopicWritesById.removeValue(forKey: id)
            pendingMeetingTopicDeletionIds.remove(id)
        }

        for id in pendingMeetingTopicDeletionIds {
            byId.removeValue(forKey: id)
        }

        for (id, topic) in pendingMeetingTopicWritesById where !pendingMeetingTopicDeletionIds.contains(id) {
            byId[id] = topic
        }

        let merged = Array(byId.values).sorted { $0.createdAt > $1.createdAt }
        DispatchQueue.main.async { [weak self] in
            self?.meetingTopics = merged
        }
    }

    func startMeetingTopicsListenerIfNeeded() {
        guard meetingTopicsListener == nil else { return }
        guard currentUser != nil else { return }

        let query = db.collection("meetingTopics").order(by: "createdAt", descending: true)
        meetingTopicsListener = query.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Meeting-Punkte konnten nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                self.meetingTopicsSnapshotCache = self.mapMeetingTopicsFromDocs(docs)
                self.mergeMeetingTopicSnapshotsAndPublish()
            }
        }
    }

    func startMeetingMetaListenerIfNeeded() {
        guard meetingMetaListener == nil else { return }
        guard currentUser != nil else { return }

        meetingMetaListener = db.collection("meetingMeta").document("schedule")
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    DispatchQueue.main.async {
                        self.uiErrorMessage = "Meeting-Termin konnte nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }

                guard
                    let data = snapshot?.data(),
                    let ts = data["nextMeetingAt"] as? Timestamp
                else {
                    DispatchQueue.main.async { [weak self] in
                        self?.nextMeetingAt = nil
                    }
                    return
                }

                let date = ts.dateValue()
                DispatchQueue.main.async { [weak self] in
                    self?.nextMeetingAt = date
                }
            }
    }

    func startMeetingArchivesListenerIfNeeded() {
        guard meetingArchivesListener == nil else { return }
        guard currentUser != nil else { return }

        let query = db.collection("meetingArchives").order(by: "meetingDate", descending: true)
        meetingArchivesListener = query.addSnapshotListener(includeMetadataChanges: false) {
            [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                if self.isPermissionDeniedError(error) {
                    DispatchQueue.main.async {
                        self.meetingArchivesSnapshotCache = []
                        self.meetingArchives = []
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.uiErrorMessage = "Meeting-Archiv konnte nicht geladen werden: \(error.localizedDescription)"
                }
                return
            }

            let docs = snapshot?.documents ?? []
            self.firestoreListenerQueue.async { [weak self] in
                guard let self else { return }
                let mapped = self.mapMeetingArchivesFromDocs(docs)
                DispatchQueue.main.async {
                    self.meetingArchivesSnapshotCache = mapped
                    self.meetingArchives = mapped
                }
            }
        }
    }

    private func meetingTopicErrorMessage(prefix: String, error: Error) -> String {
        if isPermissionDeniedError(error) {
            return "\(prefix): Zugriff verweigert. Bitte Firestore-Regeln für `meetingTopics` prüfen."
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    private func meetingArchiveErrorMessage(prefix: String, error: Error) -> String {
        if isPermissionDeniedError(error) {
            return "\(prefix): Zugriff verweigert. Bitte Firestore-Regeln für `meetingTopics` und `meetingArchives` prüfen."
        }
        return "\(prefix): \(error.localizedDescription)"
    }

    private func isPermissionDeniedError(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain &&
            ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    private func upsertMeetingTopicToFirestore(_ topic: MeetingTopic) {
        let dto = MeetingTopicDTO(from: topic)
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingTopics").document(dto.id)
                    .setData(dto.toDictionary(), merge: true)
            } catch {
                let msg = self.meetingTopicErrorMessage(
                    prefix: "Meeting-Punkt konnte nicht gespeichert werden",
                    error: error
                )
                await MainActor.run {
                    self.pendingMeetingTopicWritesById.removeValue(forKey: topic.id)
                    self.mergeMeetingTopicSnapshotsAndPublish()
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }

    private func deleteMeetingTopicFromFirestore(_ topic: MeetingTopic) {
        let docId = topic.id.uuidString
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                try await self.db.collection("meetingTopics").document(docId).delete()
            } catch {
                let msg = self.meetingTopicErrorMessage(
                    prefix: "Meeting-Punkt konnte nicht gelöscht werden",
                    error: error
                )
                await MainActor.run {
                    self.pendingMeetingTopicDeletionIds.remove(topic.id)
                    self.pendingMeetingTopicWritesById[topic.id] = topic
                    self.mergeMeetingTopicSnapshotsAndPublish()
                    self.uiErrorMessage = msg
                    self.showToast(.error, msg)
                }
            }
        }
    }
}
