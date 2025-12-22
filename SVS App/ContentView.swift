import SwiftUI
import Combine
import WebKit

// MARK: - Models

enum UserRole: String, Codable {
    case admin
    case employee
    case expert
}

struct User: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var role: UserRole
    var pin: String
    var colorName: String
    var annualLeaveDays: Int

    var color: Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "yellow": return .yellow
        default: return .gray
        }
    }
}

enum LeaveType: String, Codable {
    case vacation = "Urlaub"
    case sick = "Krankheit"

    // Backward-compatible decoding for legacy stored values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)

        switch raw {
        case LeaveType.vacation.rawValue:
            self = .vacation
        case LeaveType.sick.rawValue:
            self = .sick
        // Legacy values (older app versions)
        case "Fortbildung", "Homeoffice", "Sonstiges":
            self = .vacation
        default:
            self = .vacation
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

enum LeaveStatus: String, CaseIterable, Codable {
    case pending = "Offen"
    case approved = "Genehmigt"
    case rejected = "Abgelehnt"
}

struct LeaveRequest: Identifiable, Codable {
    let id: UUID
    var user: User
    var startDate: Date
    var endDate: Date
    var type: LeaveType
    var reason: String
    var status: LeaveStatus

    // Audit
    var createdAt: Date
    var createdByUserId: UUID
    var updatedAt: Date?
    var updatedByUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, user, startDate, endDate, type, reason, status
        case createdAt, createdByUserId, updatedAt, updatedByUserId
    }

    // Backward-compatible decoding for older stored entries
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        user = try c.decode(User.self, forKey: .user)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        type = try c.decode(LeaveType.self, forKey: .type)
        reason = (try c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        status = try c.decode(LeaveStatus.self, forKey: .status)

        // If missing, default to the user as creator and now as creation date
        createdAt = (try c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        createdByUserId = (try c.decodeIfPresent(UUID.self, forKey: .createdByUserId)) ?? user.id
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedByUserId = try c.decodeIfPresent(UUID.self, forKey: .updatedByUserId)
    }

    init(id: UUID,
         user: User,
         startDate: Date,
         endDate: Date,
         type: LeaveType,
         reason: String,
         status: LeaveStatus,
         createdAt: Date,
         createdByUserId: UUID,
         updatedAt: Date? = nil,
         updatedByUserId: UUID? = nil) {
        self.id = id
        self.user = user
        self.startDate = startDate
        self.endDate = endDate
        self.type = type
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.createdByUserId = createdByUserId
        self.updatedAt = updatedAt
        self.updatedByUserId = updatedByUserId
    }
}

// MARK: - Tasks Models

enum TaskStatus: String, Codable {
    case open
    case done
}

struct Task: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var details: String
    var dueDate: Date?
    var status: TaskStatus
    var assignedUserId: UUID
    var creatorUserId: UUID
    var createdAt: Date
}

// MARK: - Toast

enum ToastKind {
    case success
    case error
}

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let kind: ToastKind
    let message: String
}

private struct ToastBanner: View {
    let toast: AppToast

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .success: return .green
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint)
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
        .padding(.horizontal, 16)
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var users: [User] {
        didSet { saveUsers() }
    }
    @Published var currentUser: User?
    @Published var leaveRequests: [LeaveRequest] {
        didSet { saveLeaveRequests() }
    }
    @Published var tasks: [Task] = [] {
        didSet { saveTasks() }
    }
    @Published var uiErrorMessage: String? = nil

    // Session: keep user logged in across app launches
    @Published var sessionUserId: UUID? = nil {
        didSet {
            if let id = sessionUserId {
                UserDefaults.standard.set(id.uuidString, forKey: "sessionUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "sessionUserId")
            }
        }
    }
    
    @Published var lastUserId: UUID? = nil {
        didSet {
            if let id = lastUserId {
                UserDefaults.standard.set(id.uuidString, forKey: "lastUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastUserId")
            }
        }
    }
    
    @Published var toast: AppToast? = nil
    
    func showToast(_ kind: ToastKind, _ message: String) {
        toast = AppToast(kind: kind, message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.toast?.message == message {
                self?.toast = nil
            }
        }
    }

    init() {
        // Users laden / Default Users
        if let data = UserDefaults.standard.data(forKey: "users"),
           let decoded = try? JSONDecoder().decode([User].self, from: data) {
            self.users = decoded
        } else {
            self.users = [
                User(id: UUID(), name: "Hussein", role: .admin,   pin: "1111", colorName: "blue",   annualLeaveDays: 30),
                User(id: UUID(), name: "Ahmet",   role: .employee, pin: "2222", colorName: "green",  annualLeaveDays: 30),
                User(id: UUID(), name: "Hadi",    role: .employee, pin: "3333", colorName: "orange", annualLeaveDays: 30),
                User(id: UUID(), name: "Osama",   role: .employee, pin: "4444", colorName: "purple", annualLeaveDays: 30)
            ]
        }
        self.currentUser = nil

        // Leave Requests laden
        if let data = UserDefaults.standard.data(forKey: "leaveRequests"),
           let decoded = try? JSONDecoder().decode([LeaveRequest].self, from: data) {
            // Alte Einträge mit "Sonstiges" auf "Urlaub" mappen
            self.leaveRequests = decoded
        } else {
            self.leaveRequests = []
        }

        // Tasks laden
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           let decoded = try? JSONDecoder().decode([Task].self, from: data) {
            self.tasks = decoded
        } else {
            self.tasks = []
        }

        // Letzten eingeloggten Benutzer laden
        if let idString = UserDefaults.standard.string(forKey: "lastUserId"),
           let id = UUID(uuidString: idString) {
            self.lastUserId = id
        } else {
            self.lastUserId = nil
        }
        
        // Session-Login laden (User bleibt eingeloggt)
        if let sessionIdString = UserDefaults.standard.string(forKey: "sessionUserId"),
           let sessionId = UUID(uuidString: sessionIdString) {
            self.sessionUserId = sessionId
        } else {
            self.sessionUserId = nil
        }

        // Auto-Restore: wenn Session vorhanden, direkt einloggen
        if let sid = self.sessionUserId,
           let u = self.users.first(where: { $0.id == sid }) {
            self.currentUser = u
        }
    }

    private func saveLeaveRequests() {
        if let data = try? JSONEncoder().encode(leaveRequests) {
            UserDefaults.standard.set(data, forKey: "leaveRequests")
        }
    }

    private func saveUsers() {
        if let data = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(data, forKey: "users")
        }
    }

    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: "tasks")
        }
    }

    func addUser(name: String, role: UserRole, pin: String, colorName: String, annualLeaveDays: Int) {
        let newUser = User(id: UUID(), name: name, role: role, pin: pin, colorName: colorName, annualLeaveDays: annualLeaveDays)
        users.append(newUser)
    }

    func updateUser(_ user: User) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        }
        // Benutzer auch in bestehenden Anträgen aktualisieren
        leaveRequests = leaveRequests.map { request in
            if request.user.id == user.id {
                var updated = request
                updated.user = user
                return updated
            } else {
                return request
            }
        }
    }

    func deleteUser(_ user: User) {
        users.removeAll { $0.id == user.id }
    }

    private func normalizeDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func rangesOverlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        let aS = normalizeDay(aStart)
        let aE = normalizeDay(aEnd)
        let bS = normalizeDay(bStart)
        let bE = normalizeDay(bEnd)
        return aS <= bE && bS <= aE
    }

    /// Prüft, ob für den Benutzer im Zeitraum bereits ein kollidierender Antrag existiert.
    /// Regeln:
    /// - Abgelehnte Einträge blockieren nie.
    /// - Urlaub darf sich nicht mit anderem Urlaub überschneiden (Status != .rejected).
    /// - Krankheit darf Urlaub überlappen, aber nicht mit anderer Krankheit am selben Zeitraum (Status != .rejected).
    /// Optional kann ein `excludingRequestId` gesetzt werden (z. B. beim Bearbeiten).
    private func hasOverlappingLeave(for userId: UUID,
                                    start: Date,
                                    end: Date,
                                    newType: LeaveType,
                                    excludingRequestId: UUID? = nil) -> Bool {
        return leaveRequests.contains { req in
            guard req.user.id == userId else { return false }
            if let ex = excludingRequestId, req.id == ex { return false }

            // Abgelehnte Einträge blockieren nie
            guard req.status != .rejected else { return false }

            // Nur gleiche Typen blockieren (Urlaub blockt Urlaub, Krankheit blockt Krankheit)
            guard req.type == newType else { return false }

            return rangesOverlap(req.startDate, req.endDate, start, end)
        }
    }

    @discardableResult
    func createLeaveRequest(start: Date, end: Date, type: LeaveType) -> Bool {
        guard let user = currentUser else {
            uiErrorMessage = "Kein Benutzer angemeldet."
            return false
        }
        // Standard: Mitarbeiter legt für sich selbst an (Urlaub = Offen, Krankheit = direkt)
        return createLeaveRequest(start: start, end: end, type: type, for: user, approveImmediately: false)
    }

    /// Admin kann Anträge für andere Benutzer anlegen.
    /// - Urlaub: optional sofort genehmigen.
    /// - Krankheit: wird immer sofort eingetragen (Genehmigt), unabhängig vom Toggle.
    @discardableResult
    func createLeaveRequest(start: Date,
                            end: Date,
                            type: LeaveType,
                            for user: User,
                            approveImmediately: Bool) -> Bool {

        if type == .vacation {
            let requestedDays = workingDays(from: start, to: end)
            let available = availableVacationDaysForRequests(for: user)
            if requestedDays > available {
                uiErrorMessage = "Nicht genügend Resturlaub. Verfügbar: \(available) Tag(e), angefragt: \(requestedDays) Tag(e)."
                return false
            }
        }
        
        // Validierung: Überschneidungen prüfen
        if hasOverlappingLeave(for: user.id, start: start, end: end, newType: type) {
            switch type {
            case .sick:
                if Calendar.current.isDate(start, inSameDayAs: end) {
                    uiErrorMessage = "Für diesen Tag haben Sie sich bereits krank gemeldet."
                } else {
                    uiErrorMessage = "In diesem Zeitraum haben Sie sich bereits krank gemeldet."
                }
            case .vacation:
                uiErrorMessage = "Dieser Zeitraum überschneidet sich mit einem bestehenden Urlaubsantrag."
            }
            return false
        }

        // Status:
        // - Krankheit: immer direkt eingetragen
        // - Urlaub: entweder offen oder direkt genehmigt (Admin-Option)
        let initialStatus: LeaveStatus
        if type == .sick {
            initialStatus = .approved
        } else {
            initialStatus = approveImmediately ? .approved : .pending
        }

        let creatorId = currentUser?.id ?? user.id
        let request = LeaveRequest(
            id: UUID(),
            user: user,
            startDate: start,
            endDate: end,
            type: type,
            reason: "",
            status: initialStatus,
            createdAt: Date(),
            createdByUserId: creatorId,
            updatedAt: nil,
            updatedByUserId: nil
        )
        leaveRequests.append(request)
        let successText: String
        if type == .sick {
            successText = "Krankmeldung erfolgreich gespeichert."
        } else {
            successText = (initialStatus == .approved) ? "Urlaub erfolgreich eingetragen." : "Urlaubsantrag erfolgreich erstellt."
        }
        showToast(.success, successText)
        uiErrorMessage = nil
        return true
    }

    func requests(for date: Date) -> [LeaveRequest] {
        leaveRequests.filter { request in
            let cal = Calendar.current
            return cal.startOfDay(for: request.startDate) <= cal.startOfDay(for: date)
            && cal.startOfDay(for: request.endDate) >= cal.startOfDay(for: date)
        }
    }

    func myRequests() -> [LeaveRequest] {
        guard let user = currentUser else { return [] }
        return leaveRequests.filter { $0.user.id == user.id }
    }

    func updateStatus(for requestID: UUID, to newStatus: LeaveStatus) {
        if let index = leaveRequests.firstIndex(where: { $0.id == requestID }) {
            leaveRequests[index].status = newStatus
            leaveRequests[index].updatedAt = Date()
            leaveRequests[index].updatedByUserId = currentUser?.id
        }
    }

    /// Bearbeitungs-/Löschrechte für Abwesenheiten:
    /// - Admin: darf immer bearbeiten/löschen
    /// - Mitarbeiter/Sachverständige: nur eigene *Urlaubs*-Anträge solange sie **Offen** sind
    ///   (genehmigte/abgelehnte Anträge sowie Krankheitseinträge sind für Nicht-Admins nicht mehr änderbar)
    func canEditOrDelete(_ request: LeaveRequest, by user: User?) -> Bool {
        guard let user = user else { return false }
        if user.role == .admin { return true }

        // Nicht-Admins dürfen nur eigene offenen Urlaubsanträge ändern
        guard user.id == request.user.id else { return false }
        return request.type == .vacation && request.status == .pending
    }

    @discardableResult
    func updateLeaveRequest(_ updated: LeaveRequest) -> Bool {
        if updated.type == .vacation {
            let requestedDays = workingDays(from: updated.startDate, to: updated.endDate)
            let available = availableVacationDaysForRequests(for: updated.user, excludingRequestId: updated.id)
            if requestedDays > available {
                uiErrorMessage = "Nicht genügend Resturlaub. Verfügbar: \(available) Tag(e), angefragt: \(requestedDays) Tag(e)."
                return false
            }
        }
        // Validierung: nach Bearbeitung darf es keine Überschneidung mit anderen Einträgen geben
        if hasOverlappingLeave(for: updated.user.id,
                              start: updated.startDate,
                              end: updated.endDate,
                              newType: updated.type,
                              excludingRequestId: updated.id) {
            uiErrorMessage = "Dieser Zeitraum überschneidet sich mit einer bestehenden Abwesenheit. Änderungen wurden nicht gespeichert."
            return false
        }

        if let index = leaveRequests.firstIndex(where: { $0.id == updated.id }) {
            var patched = updated
            patched.updatedAt = Date()
            patched.updatedByUserId = currentUser?.id
            leaveRequests[index] = patched
            uiErrorMessage = nil
            return true
        }

        uiErrorMessage = "Der Antrag konnte nicht gefunden werden."
        return false
    }

    func deleteLeaveRequest(_ request: LeaveRequest) {
        leaveRequests.removeAll { $0.id == request.id }
    }

    // MARK: - Task Management

    func createTask(title: String,
                    details: String,
                    dueDate: Date?,
                    assignedUser: User,
                    creator: User) {
        let newTask = Task(
            id: UUID(),
            title: title,
            details: details,
            dueDate: dueDate,
            status: .open,
            assignedUserId: assignedUser.id,
            creatorUserId: creator.id,
            createdAt: Date()
        )
        tasks.append(newTask)
    }

    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
    }

    func toggleTaskStatus(for task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].status = (tasks[index].status == .open) ? .done : .open
        }
    }

    func deleteTask(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
    }

    func userName(for userId: UUID) -> String {
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
        let requestsForUser = leaveRequests.filter {
            $0.user.id == user.id &&
            $0.type == .vacation &&
            $0.status != .rejected &&
            (excludingRequestId == nil || $0.id != excludingRequestId!)
        }

        return requestsForUser.reduce(0) { partial, req in
            partial + max(workingDays(from: req.startDate, to: req.endDate), 0)
        }
    }

    func availableVacationDaysForRequests(for user: User, excludingRequestId: UUID? = nil) -> Int {
        let reserved = reservedVacationDays(for: user, excludingRequestId: excludingRequestId)
        return max(user.annualLeaveDays - reserved, 0)
    }
}



// MARK: - Shared UI Helpers

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 4)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

struct SecondaryTextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
            .foregroundColor(.secondary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

fileprivate func shortDateString(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .short
    return df.string(from: date)
}

fileprivate func mediumDateString(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df.string(from: date)
}

fileprivate func dateRangeString(_ start: Date, _ end: Date) -> String {
    if Calendar.current.isDate(start, inSameDayAs: end) {
        return shortDateString(start)
    } else {
        return "\(shortDateString(start)) – \(shortDateString(end))"
    }
}

fileprivate func colorForLeaveStatus(_ status: LeaveStatus) -> Color {
    switch status {
    case .approved: return .green
    case .pending:  return .orange
    case .rejected: return .red
    }
}

fileprivate func statusBadgeView(_ status: LeaveStatus) -> some View {
    Text(status.rawValue)
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(colorForLeaveStatus(status).opacity(0.15))
        )
        .foregroundColor(colorForLeaveStatus(status))
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if appState.currentUser == nil {
                    LoginView()
                } else {
                    MainView()
                }
            }

            if let toast = appState.toast {
                ToastBanner(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toast)
    }
}

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedUser: User? = nil
    @State private var pin: String = ""
    @State private var showError: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    // Header (kompakt)
                    VStack(spacing: 8) {
                        Image("svs_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 54)
                            .padding(.top, 8)

                        Text("SVS Mitarbeiter-App")
                            .font(.title3.weight(.semibold))

                        Text("Mitarbeiter auswählen und mit PIN anmelden")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }

                    // Selected User Card + PIN (immer sichtbar, sobald gewählt)
                    if let selected = selectedUser {
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                InitialsAvatarView(name: selected.name, color: selected.color)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selected.name)
                                        .font(.headline)
                                    Text(roleLabel(for: selected.role))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    // Auswahl zurücksetzen
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedUser = nil
                                        pin = ""
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 10) {
                                SecureField("PIN", text: $pin)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    if pin == selected.pin {
                                        appState.currentUser = selected
                                        appState.lastUserId = selected.id
                                        appState.sessionUserId = selected.id
                                        pin = ""
                                        selectedUser = nil
                                    } else {
                                        showError = true
                                    }
                                } label: {
                                    Text("Anmelden")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(pin.isEmpty)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Schnellzugriff: zuletzt verwendet (kompakt)
                    if let lastId = appState.lastUserId,
                       let lastUser = appState.users.first(where: { $0.id == lastId }),
                       selectedUser == nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedUser = lastUser
                                pin = ""
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                Text("Zuletzt: ")
                                    .foregroundColor(.secondary)
                                Text(lastUser.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }

                    // Mitarbeiter-Auswahl (2 Spalten, scrollt nur bei Bedarf)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mitarbeiter")
                            .font(.headline)
                            .padding(.horizontal)

                        let columns = [GridItem(.flexible()), GridItem(.flexible())]

                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(appState.users) { user in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            selectedUser = user
                                            pin = ""
                                        }
                                    } label: {
                                        let selected = selectedUser?.id == user.id
                                        HStack(spacing: 10) {
                                            InitialsAvatarView(name: user.name, color: user.color)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(user.name)
                                                    .font(.subheadline.weight(selected ? .semibold : .regular))
                                                    .foregroundColor(.primary)
                                                Text(roleLabel(for: user.role))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14)
                                                .fill(selected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(selected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                        }
                        .frame(maxHeight: max(220, geo.size.height * 0.36))
                    }

                    Spacer(minLength: 6)
                }
                .padding(.top, 6)
            }
            .alert("Falsche PIN", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    pin = ""
                }
            } message: {
                Text("Die eingegebene PIN ist nicht korrekt.")
            }
        }
    }
}

// MARK: - Main View (Tabs)

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // Urlaub
            CalendarScreen()
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }

            MyRequestsScreen()
                .tabItem {
                    Label("Meine Anträge", systemImage: "doc.text")
                }

            // Admin-spezifische Tabs
            if let user = appState.currentUser {
                if user.role == .admin {
                    AdminConsoleView()
                        .tabItem {
                            Label("Admin", systemImage: "shield.lefthalf.filled")
                        }
                }

                // Provisionen nur für Admin & Sachverständige
                if user.role == .admin || user.role == .expert {
                    ProvisionenView()
                        .tabItem {
                            Label("Provisionen", systemImage: "eurosign")
                        }
                }
            }

            // Für alle sichtbar
            TasksView()
                .tabItem {
                    Label("Aufgaben", systemImage: "checklist")
                }

            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
                }

            // Menü Tab
            MenuView()
                .tabItem {
                    Label("Menü", systemImage: "gearshape")
                }
        }
    }
}

// MARK: - Edit Leave Request View

// MARK: - Admin Console

struct AdminConsoleView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewRequestSheet: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    HStack(alignment: .firstTextBaseline) {
                        Text("Admin")
                            .font(.largeTitle.weight(.bold))

                        Spacer()

                        Button {
                            showNewRequestSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Antrag erstellen")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // KPI Cards (2 only, neutral accent)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        AdminStatCard(
                            title: "Offene Anträge",
                            value: "\(openVacationRequestsCount)",
                            systemImage: "doc.text",
                            accent: .secondary
                        )

                        AdminStatCard(
                            title: "Heute abwesend",
                            value: "\(todayAbsentCount)",
                            systemImage: "calendar.badge.clock",
                            accent: .secondary
                        )
                    }
                    .padding(.horizontal, 18)


                    VStack(alignment: .leading, spacing: 10) {
                        Text("Übersicht")
                            .font(.headline)
                            .padding(.horizontal, 18)

                        VStack(spacing: 10) {
                            NavigationLink {
                                AdminRequestsScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Anträge verwalten",
                                            subtitle: "Genehmigen, ablehnen und filtern",
                                            systemImage: "doc.text.magnifyingglass")
                            }

                            NavigationLink {
                                AdminUsersScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Mitarbeiter",
                                            subtitle: "Urlaub, Rollen und Login verwalten",
                                            systemImage: "person.2")
                            }
                        }
                        .padding(.horizontal, 18)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.top, 2)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showNewRequestSheet) {
                NavigationStack {
                    NewLeaveRequestView()
                        .environmentObject(appState)
                }
            }
        }
    }
    
    private struct AdminStatCard: View {
        let title: String
        let value: String
        let systemImage: String
        let accent: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage).foregroundColor(.secondary)
                    Spacer()
                }
                Text(value).font(.title2.weight(.bold))
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
        }
    }

    private struct AdminNavRow: View {
        let title: String
        let subtitle: String
        let systemImage: String

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.secondarySystemBackground))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption.weight(.semibold))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .contentShape(Rectangle())
        }
    }

    private var openVacationRequestsCount: Int {
        appState.leaveRequests.filter { $0.type == .vacation && $0.status == .pending }.count
    }

    private var todayAbsentCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let todays = appState.requests(for: today).filter { $0.status == .approved }
        return Set(todays.map { $0.user.id }).count
    }
}

struct EditLeaveRequestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var request: LeaveRequest
    @State private var inlineError: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if let inlineError {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(inlineError)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                    .id("errorBanner")
                }

                Section(header: Text("Zeitraum")) {
                    DatePicker("Von", selection: $request.startDate, displayedComponents: .date)
                    DatePicker("Bis", selection: $request.endDate, in: request.startDate..., displayedComponents: .date)
                }

                Section(header: Text("Art der Abwesenheit")) {
                    // Nur Urlaub und Krankheit zur Auswahl anbieten
                    let allowedTypes: [LeaveType] = [.vacation, .sick]

                    Picker("Art", selection: $request.type) {
                        ForEach(allowedTypes, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    if appState.canEditOrDelete(request, by: appState.currentUser) {
                        Button("Änderungen speichern") {
                            let ok = appState.updateLeaveRequest(request)
                            if ok {
                                inlineError = nil
                                dismiss()
                            } else {
                                inlineError = appState.uiErrorMessage
                            }
                        }

                        Button("Antrag löschen", role: .destructive) {
                            appState.deleteLeaveRequest(request)
                            dismiss()
                        }
                    } else {
                        Text("Dieser Antrag wurde bereits entschieden und kann nicht mehr bearbeitet werden.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: inlineError) { value in
                guard value != nil else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo("errorBanner", anchor: .top)
                }
            }
            .onChange(of: request.startDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: request.endDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: request.type) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
        }
        .navigationTitle("Antrag bearbeiten")
        .onAppear {
            if request.type == .sick {
                request.status = .approved
            }
        }
    }
}


// MARK: - Admin Requests Screen

enum AdminQuickFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case today = "Heute"
    case thisWeek = "Diese Woche"

    var id: String { rawValue }
}

struct AdminRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var editingRequest: LeaveRequest?
    @State private var searchText: String = ""
    @State private var filterMode: AdminQuickFilter = .all

    private func matchesSearch(_ request: LeaveRequest) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return request.user.name.lowercased().contains(q.lowercased())
    }

    private func matchesQuickFilter(_ request: LeaveRequest) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: request.startDate)
        let end = cal.startOfDay(for: request.endDate)
        let today = cal.startOfDay(for: Date())

        switch filterMode {
        case .all:
            return true
        case .today:
            return start <= today && today <= end
        case .thisWeek:
            guard let week = cal.dateInterval(of: .weekOfYear, for: today) else { return true }
            let wStart = cal.startOfDay(for: week.start)
            let wEnd = cal.startOfDay(for: week.end.addingTimeInterval(-1))
            return start <= wEnd && wStart <= end
        }
    }

    private var openRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { $0.type == .vacation && $0.status == .pending }
            .filter { matchesSearch($0) && matchesQuickFilter($0) }
            .sorted { $0.startDate > $1.startDate }
    }

    // Beantwortete Anträge (inkl. Krankheit) – nach Monat gruppiert
    private var answeredRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { !($0.type == .vacation && $0.status == .pending) }
            .filter { matchesSearch($0) && matchesQuickFilter($0) }
            .sorted { $0.startDate > $1.startDate }
    }

    private var answeredRequestsByMonth: [(monthStart: Date, requests: [LeaveRequest])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: answeredRequests) { req in
            let comps = cal.dateComponents([.year, .month], from: req.startDate)
            return cal.date(from: comps) ?? cal.startOfDay(for: req.startDate)
        }

        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted { $0.startDate > $1.startDate }
            return (monthStart: key, requests: items)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Anträge")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Menu {
                        Picker("Filter", selection: $filterMode) {
                            ForEach(AdminQuickFilter.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                List {
                    if openRequests.isEmpty && answeredRequests.isEmpty {
                        Section {
                            Text("Keine Anträge vorhanden")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        if !openRequests.isEmpty {
                            Section(header: Text("Offen")) {
                                ForEach(openRequests) { request in
                                    adminRequestRow(for: request)
                                }
                            }
                        }

                        if !answeredRequestsByMonth.isEmpty {
                            ForEach(answeredRequestsByMonth, id: \.monthStart) { group in
                                Section(header: Text(monthTitle(group.monthStart))) {
                                    ForEach(group.requests) { request in
                                        adminRequestRow(for: request)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .searchable(text: $searchText, prompt: "Mitarbeiter suchen")
                .sheet(item: $editingRequest) { request in
                    NavigationStack {
                        EditLeaveRequestView(request: request)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    @ViewBuilder
    private func adminRequestRow(for request: LeaveRequest) -> some View {
        AdminLeaveRequestCard(
            request: request,
            onApprove: { appState.updateStatus(for: request.id, to: .approved) },
            onReject: { appState.updateStatus(for: request.id, to: .rejected) },
            onResetToOpen: { appState.updateStatus(for: request.id, to: .pending) },
            onEdit: { editingRequest = request },
            onDelete: { appState.deleteLeaveRequest(request) }
        )
        .environmentObject(appState)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions {
            if appState.canEditOrDelete(request, by: appState.currentUser) {
                Button {
                    editingRequest = request
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    appState.deleteLeaveRequest(request)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }
}

private struct AdminLeaveRequestCard: View {
    let request: LeaveRequest
    let onApprove: () -> Void
    let onReject: () -> Void
    let onResetToOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var appState: AppState

    private var isVacation: Bool { request.type == .vacation }
    private var accent: Color {
        request.type == .sick ? Color.gray : colorForLeaveStatus(request.status)
    }
    @State private var showAudit: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent.opacity(0.9))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(request.user.name)
                            .font(.headline)
                            .foregroundColor(request.user.color)

                        Spacer()

                        // Krankheit: kein Status-Badge
                        if request.type != .sick {
                            statusBadgeView(request.status)
                        }
                    }

                    Text(dateRangeString(request.startDate, request.endDate))
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        Image(systemName: request.type == .sick ? "cross.case" : "beach.umbrella")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(request.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }

            // Aktionen:
            if isVacation {
                if request.status == .pending {
                    HStack(spacing: 8) {
                        Button("Genehmigen", action: onApprove)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                        Button("Ablehnen", action: onReject)
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                } else {
                    Button {
                        onResetToOpen()
                    } label: {
                        Label("Auf Offen setzen", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            }

            // AUDIT (einklappbar)
            let createdBy = appState.userName(for: request.createdByUserId)
            let updatedBy = request.updatedByUserId.map { appState.userName(for: $0) }
            let hasUpdate = (request.updatedAt != nil && updatedBy != nil)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showAudit.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showAudit ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(showAudit ? "Audit ausblenden" : "Audit anzeigen")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Optional: kleine Kurzinfo, damit man ohne Aufklappen Kontext hat
                    Text(shortDateString(request.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if showAudit {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erstellt von: \(createdBy) • \(shortDateString(request.createdAt))")
                    if let uAt = request.updatedAt, let uBy = updatedBy {
                        Text("Geändert: \(uBy) • \(shortDateString(uAt))")
                    } else if !hasUpdate {
                        Text("Noch nicht geändert")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}

enum AdminUserRoleFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case admins = "Admins"
    case employees = "Mitarbeiter"
    case experts = "Sachverständige"
    var id: String { rawValue }
}

enum AdminUserSortMode: String, CaseIterable, Identifiable {
    case name = "Name"
    case remainingAsc = "Resturlaub ↑"
    case remainingDesc = "Resturlaub ↓"
    var id: String { rawValue }
}

// MARK: - Admin Users Screen

struct AdminUsersScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddUser = false
    @State private var searchText: String = ""
    @State private var roleFilter: AdminUserRoleFilter = .all
    @State private var sortMode: AdminUserSortMode = .name
    
    private func matchesSearch(_ user: User) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return user.name.lowercased().contains(q.lowercased())
    }

    private func matchesRole(_ user: User) -> Bool {
        switch roleFilter {
        case .all: return true
        case .admins: return user.role == .admin
        case .employees: return user.role == .employee
        case .experts: return user.role == .expert
        }
    }

    private var filteredUsers: [User] {
        let base = appState.users
            .filter { matchesRole($0) }
            .filter { matchesSearch($0) }

        switch sortMode {
        case .name:
            return base.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .remainingAsc:
            return base.sorted { appState.remainingLeaveDays(for: $0) < appState.remainingLeaveDays(for: $1) }
        case .remainingDesc:
            return base.sorted { appState.remainingLeaveDays(for: $0) > appState.remainingLeaveDays(for: $1) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Mitarbeiter")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        showAddUser = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neuen Mitarbeiter erstellen")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Rolle", selection: $roleFilter) {
                        ForEach(AdminUserRoleFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Menu {
                            Picker("Sortierung", selection: $sortMode) {
                                ForEach(AdminUserSortMode.allCases) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                        } label: {
                            Label("Sortieren", systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(filteredUsers.count) Mitarbeiter")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 18)

                List {
                    Section(header: Text("Mitarbeiter & Resturlaub")) {
                        ForEach(filteredUsers) { user in
                            NavigationLink {
                                EditUserView(user: user).environmentObject(appState)
                            } label: {
                                AdminUserCard(user: user).environmentObject(appState)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .searchable(text: $searchText, prompt: "Mitarbeiter suchen")
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showAddUser) {
                NavigationStack {
                    AddUserView()
                        .environmentObject(appState)
                }
            }
        }
    }
    
    private struct AdminUserCard: View {
        let user: User
        @EnvironmentObject var appState: AppState

        private var used: Int { appState.usedVacationDays(for: user) }
        private var remaining: Int { appState.remainingLeaveDays(for: user) }
        private var warning: Bool { remaining <= 5 }

        var body: some View {
            HStack(spacing: 12) {
                Circle().fill(user.color).frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.name)
                            .font(.headline)
                            .foregroundColor(user.color)

                        Spacer()

                        Text(roleText(for: user.role))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 10) {
                        Text("Urlaub: \(user.annualLeaveDays)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("Genutzt: \(used)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("Rest: \(remaining)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(warning ? .red : .secondary)

                        if warning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }

                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke((warning ? Color.red : user.color).opacity(0.12), lineWidth: 1)
            )
        }

        private func roleText(for role: UserRole) -> String {
            switch role {
            case .admin: return "Admin"
            case .employee: return "Mitarbeiter"
            case .expert: return "Sachverständiger"
            }
        }
    }
}

struct EditUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var user: User

    @State private var showNewRequest: Bool = false
    @State private var showPinResetAlert: Bool = false

    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]

    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: binding(for: \.name))
                Picker("Rolle", selection: binding(for: \.role)) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("Sachverständiger").tag(UserRole.expert)
                }
            }

            Section(header: Text("Login")) {
                TextField("PIN", text: binding(for: \.pin))
                    .keyboardType(.numberPad)

                Button {
                    user.pin = "0000"
                    showPinResetAlert = true
                } label: {
                    Label("PIN auf 0000 setzen", systemImage: "key")
                }
                .font(.subheadline)
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: binding(for: \.annualLeaveDays), in: 0...365) {
                    Text("Jahresurlaub: \(user.annualLeaveDays) Tage")
                }
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: binding(for: \.colorName)) {
                    ForEach(availableColors, id: \.self) { color in
                        Text(color.capitalized).tag(color)
                    }
                }
            }

            if appState.currentUser?.role == .admin {
                Section(header: Text("Aktionen")) {
                    Button {
                        showNewRequest = true
                    } label: {
                        Label("Antrag für diesen Mitarbeiter erstellen", systemImage: "plus.circle")
                    }
                }
            }

            Section {
                Button("Änderungen speichern") {
                    appState.updateUser(user)
                    dismiss()
                }

                Button("Mitarbeiter löschen", role: .destructive) {
                    appState.deleteUser(user)
                    dismiss()
                }
            }
        }
        .navigationTitle("Mitarbeiter bearbeiten")
        .sheet(isPresented: $showNewRequest) {
            NavigationStack {
                NewLeaveRequestView(preselectedUserId: user.id)
                    .environmentObject(appState)
            }
        }
        .alert("PIN geändert", isPresented: $showPinResetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Der PIN wurde auf 0000 gesetzt. Bitte speichern.")
        }
    }

    private func binding<Value>(for keyPath: WritableKeyPath<User, Value>) -> Binding<Value> {
        Binding(
            get: { user[keyPath: keyPath] },
            set: { user[keyPath: keyPath] = $0 }
        )
    }
}

struct AddUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var role: UserRole = .employee
    @State private var pin: String = ""
    @State private var annualLeaveDays: Int = 30
    @State private var colorName: String = "gray"

    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]

    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: $name)
                Picker("Rolle", selection: $role) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("Sachverständiger").tag(UserRole.expert)
                }
            }

            Section(header: Text("Login")) {
                TextField("PIN", text: $pin)
                    .keyboardType(.numberPad)
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: $annualLeaveDays, in: 0...365) {
                    Text("Jahresurlaub: \(annualLeaveDays) Tage")
                }
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: $colorName) {
                    ForEach(availableColors, id: \.self) { color in
                        Text(color.capitalized).tag(color)
                    }
                }
            }

            Section {
                Button("Mitarbeiter erstellen") {
                    appState.addUser(name: name,
                                     role: role,
                                     pin: pin,
                                     colorName: colorName,
                                     annualLeaveDays: annualLeaveDays)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || pin.isEmpty)
            }
        }
        .navigationTitle("Neuer Mitarbeiter")
    }
}

// MARK: - Calendar Screen

struct CalendarScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Date()

    var body: some View {
        VStack(spacing: 12) {
            // Clean Header
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Kalender")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        let now = Date()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentMonth = now
                        }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = now
                        }
                    } label: {
                        Text("Heute")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }

                MonthHeader(currentMonth: $currentMonth)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mitarbeiter")
                    .font(.subheadline)
                    .padding(.horizontal)
                UserLegendView()
                    .padding(.horizontal)
            }

            CalendarGrid(currentMonth: currentMonth,
                         selectedDate: $selectedDate)
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.25), value: currentMonth)

            List {
                Section(header: Text("\(formatted(selectedDate))")) {
                    if let holiday = germanHolidayName(selectedDate) {
                        Text(holiday)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    let requests = appState.requests(for: selectedDate).filter { $0.status == .approved }
                    if requests.isEmpty {
                        Text("Keine Anträge")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(requests) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.user.name)
                                    .font(.headline)
                                    .foregroundColor(r.user.color)
                                Text("\(dateRange(r.startDate, r.endDate))")
                                    .font(.subheadline)
                                Text(r.type.rawValue)
                                    .font(.caption)
                                // Bei Krankheit keinen Status-Text anzeigen
                                if r.type != .sick {
                                    Text(r.status.rawValue)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func formatted(_ date: Date) -> String {
        mediumDateString(date)
    }

    func dateRange(_ start: Date, _ end: Date) -> String {
        dateRangeString(start, end)
    }
}

// MARK: - Month Header

struct MonthHeader: View {
    @Binding var currentMonth: Date

    private var title: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: currentMonth)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    moveMonth(by: -1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(title.capitalized)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    moveMonth(by: 1)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)
        )
    }

    func moveMonth(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }
}

// MARK: - User Legend

struct UserLegendView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(appState.users, id: \.id) { user in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(user.color)
                            .frame(width: 10, height: 10)
                        Text(user.name)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Calendar Grid

struct CalendarGrid: View {
    @EnvironmentObject var appState: AppState
    let currentMonth: Date
    @Binding var selectedDate: Date

    private var days: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Montag

        guard let monthInterval = cal.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        let startOfMonth = cal.startOfDay(for: monthInterval.start)
        let endOfMonth = cal.date(byAdding: .day, value: -1, to: monthInterval.end).map { cal.startOfDay(for: $0) } ?? startOfMonth

        func startOfWeek(_ date: Date) -> Date {
            let weekday = cal.component(.weekday, from: date)
            let diff = (weekday - cal.firstWeekday + 7) % 7
            return cal.date(byAdding: .day, value: -diff, to: date).map { cal.startOfDay(for: $0) } ?? date
        }

        func endOfWeek(_ date: Date) -> Date {
            let weekday = cal.component(.weekday, from: date)
            let diff = (cal.firstWeekday + 6 - weekday + 7) % 7
            return cal.date(byAdding: .day, value: diff, to: date).map { cal.startOfDay(for: $0) } ?? date
        }

        let gridStart = startOfWeek(startOfMonth)
        let gridEnd = endOfWeek(endOfMonth)

        let totalDays = (cal.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 0) + 1
        let weeks = max(4, min(6, Int(ceil(Double(totalDays) / 7.0))))

        return (0..<(weeks * 7)).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)

        VStack {
            HStack {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { d in
                    Text(d)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(days, id: \.self) { date in
                    let isCurrentMonth = Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)

                    let approvedRequests = isCurrentMonth
                        ? appState.requests(for: date).filter { $0.status == .approved }
                        : []

                    let approvedColors = approvedRequests.map { $0.user.color }
                    let isHoliday = isCurrentMonth ? isPublicHolidayBremen(date) : false

                    DayCell(
                        date: date,
                        isCurrentMonth: isCurrentMonth,
                        isSelected: isCurrentMonth && Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        approvedColors: approvedColors,
                        isHoliday: isHoliday
                    )
                    .contentShape(Rectangle())
                    .allowsHitTesting(isCurrentMonth)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = date
                        }
                    }
                }
            }
        }
    }
}

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let approvedColors: [Color]
    let isHoliday: Bool
    
    var body: some View {
        // Tage außerhalb des aktuellen Monats: bewusst „leer“ darstellen
        if !isCurrentMonth {
            return AnyView(
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 36)
            )
        }
        
        let day = Calendar.current.component(.day, from: date)
        
        return AnyView(
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(isHoliday ? .red : .primary)
                    .padding(.top, 1)
                
                // Indicator-Bars (Apple-like)
                indicators
                    .frame(height: 5) // kleiner als vorher
            }
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isSelected)
        )
    }
    
    
    private var indicators: some View {
        let unique = Array(orderedUniqueColors(approvedColors))
        let maxBars = 3
        let shown = Array(unique.prefix(maxBars))
        let hasMore = unique.count > maxBars
        
        return HStack(spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, c in
                Capsule()
                    .fill(c.opacity(isCurrentMonth ? 0.95 : 0.35))
                    .frame(height: 3)
            }
            
            if hasMore {
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 3, height: 3)
            }
            
            // Wenn keine Anträge: unsichtbar, aber gleicher Platz
            if shown.isEmpty && !hasMore {
                Capsule().fill(Color.clear).frame(height: 3)
            }
        }
        .padding(.horizontal, 6)
    }
    
    private func orderedUniqueColors(_ colors: [Color]) -> [Color] {
        var result: [Color] = []
        for c in colors {
            if !result.contains(where: { $0.description == c.description }) {
                result.append(c)
            }
        }
        return result
    }
}
    
    
    // MARK: - Feiertage (Deutschland)
    
    func germanHolidayName(_ date: Date) -> String? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        func makeDate(_ month: Int, _ day: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            return calendar.date(from: components)
        }
        
        func sameDay(_ d1: Date?, _ d2: Date) -> Bool {
            guard let d1 = d1 else { return false }
            return calendar.isDate(d1, inSameDayAs: d2)
        }
        
        // Feste Feiertage (bundesweit)
        let newYear        = makeDate(1, 1)
        let labourDay      = makeDate(5, 1)
        let germanUnity    = makeDate(10, 3)
        let reformationDay = makeDate(10, 31)
        let christmasDay   = makeDate(12, 25)
        let boxingDay      = makeDate(12, 26)
        
        if sameDay(newYear, date)        { return "Neujahr" }
        if sameDay(labourDay, date)      { return "Tag der Arbeit" }
        if sameDay(germanUnity, date)    { return "Tag der Deutschen Einheit" }
        if sameDay(reformationDay, date) { return "Reformationstag" }
        if sameDay(christmasDay, date)   { return "1. Weihnachtstag" }
        if sameDay(boxingDay, date)      { return "2. Weihnachtstag" }
        
        // Bewegliche Feiertage rund um Ostern
        guard let easter = easterSunday(year: year) else { return nil }
        let goodFriday   = calendar.date(byAdding: .day, value: -2, to: easter)
        let easterMonday = calendar.date(byAdding: .day, value:  1, to: easter)
        let ascension    = calendar.date(byAdding: .day, value: 39, to: easter)
        let whitMonday   = calendar.date(byAdding: .day, value: 50, to: easter)
        
        if sameDay(goodFriday, date)     { return "Karfreitag" }
        if sameDay(easter, date)         { return "Ostersonntag" }
        if sameDay(easterMonday, date)   { return "Ostermontag" }
        if sameDay(ascension, date)      { return "Christi Himmelfahrt" }
        if sameDay(whitMonday, date)     { return "Pfingstmontag" }
        
        return nil
    }
    
    func isPublicHolidayBremen(_ date: Date) -> Bool {
        return germanHolidayName(date) != nil
    }
    
    func easterSunday(year: Int) -> Date? {
        // Meeus/Jones/Butcher Algorithmus
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

 func workingDays(from start: Date, to end: Date) -> Int {
    let cal = Calendar.current
    var date = cal.startOfDay(for: start)
    let endDate = cal.startOfDay(for: end)
    var count = 0

    while date <= endDate {
        let weekday = cal.component(.weekday, from: date)
        let isWeekday = weekday >= 2 && weekday <= 6

        if isWeekday && !isPublicHolidayBremen(date) {
            count += 1
        }
        date = cal.date(byAdding: .day, value: 1, to: date)!
    }
    return count
}



// MARK: - My Requests Screen

struct MyRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var editingRequest: LeaveRequest?

    private var myRequests: [LeaveRequest] {
        appState.myRequests()
    }

    private var counts: (pending: Int, approved: Int, rejected: Int) {
        let vacationRequests = myRequests.filter { $0.type != .sick }
        let pending = vacationRequests.filter { $0.status == .pending }.count
        let approved = vacationRequests.filter { $0.status == .approved }.count
        let rejected = vacationRequests.filter { $0.status == .rejected }.count
        return (pending, approved, rejected)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Header (match Kalender style)
                HStack(alignment: .firstTextBaseline) {
                    Text("Meine Anträge")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    NavigationLink(destination: NewLeaveRequestView()) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neuen Antrag erstellen")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Group {
                    if myRequests.isEmpty {
                        // Clean empty state (no List top inset / no huge header gap)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Noch keine Anträge")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.secondarySystemBackground))
                                .frame(height: 68)
                                .overlay(
                                    HStack {
                                        Text("Noch keine Anträge")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 18)
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color(.systemGroupedBackground))
                    } else {
                        List {
                            ForEach(myRequests) { r in
                                MyLeaveRequestCard(request: r) {
                                    if appState.canEditOrDelete(r, by: appState.currentUser) {
                                        editingRequest = r
                                    }
                                }
                                .swipeActions {
                                    if appState.canEditOrDelete(r, by: appState.currentUser) {
                                        Button {
                                            editingRequest = r
                                        } label: {
                                            Label("Bearbeiten", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            appState.deleteLeaveRequest(r)
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(item: $editingRequest) { request in
                NavigationStack {
                    EditLeaveRequestView(request: request)
                }
            }
        }
    }
}

private struct MyRequestsHeaderView: View {
    let counts: (pending: Int, approved: Int, rejected: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meine Anträge")
                .font(.headline)

            HStack(spacing: 8) {
                if counts.pending > 0 { Text("Offen: \(counts.pending)") }
                if counts.approved > 0 { Text("Genehmigt: \(counts.approved)") }
                if counts.rejected > 0 { Text("Abgelehnt: \(counts.rejected)") }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

private struct MyLeaveRequestCard: View {
    let request: LeaveRequest
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Farb-Leiste links
                RoundedRectangle(cornerRadius: 3)
                    .fill(request.type == .sick ? Color.gray.opacity(0.35) : colorForLeaveStatus(request.status).opacity(0.9))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dateRangeString(request.startDate, request.endDate))
                            .font(.headline)

                        Spacer()

                        // Status nur bei Urlaub anzeigen
                        if request.type != .sick {
                            statusBadgeView(request.status)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: request.type == .sick ? "cross.case" : "beach.umbrella")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(request.type.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    (request.type == .sick ? Color.gray : colorForLeaveStatus(request.status)).opacity(0.18),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - New Leave Request Form

struct NewLeaveRequestView: View {

    private let preselectedUserId: UUID?

    init(preselectedUserId: UUID? = nil) {
        self.preselectedUserId = preselectedUserId
        _selectedUserId = State(initialValue: preselectedUserId)
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var selectedType: LeaveType = .vacation
    @State private var selectedUserId: UUID? = nil
    @State private var approveImmediately: Bool = true
    @State private var inlineError: String? = nil

    private var buttonTitle: String {
        switch selectedType {
        case .vacation:
            return "Urlaub beantragen"
        case .sick:
            return "Krankheit melden"
        }
    }

    private var typeHint: String {
        switch selectedType {
        case .vacation:
            return "Urlaubsanträge müssen von einem Admin genehmigt werden."
        case .sick:
            return "Krankheit wird direkt eingetragen und muss nicht genehmigt werden."
        }
    }

    private var dayCount: Int {
        let days = workingDays(from: startDate, to: endDate)
        return max(days, 1)
    }

    private var isAdmin: Bool {
        appState.currentUser?.role == .admin
    }

    private var selectedUser: User? {
        if let id = selectedUserId {
            return appState.users.first(where: { $0.id == id })
        }
        // Default: aktueller User
        return appState.currentUser
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                // Fehlerhinweis immer oben anzeigen
                if let inlineError {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(inlineError)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                    }
                    .id("errorBanner")
                }

                // Überblick
                Section(header: Text("Überblick")) {
                    if let user = selectedUser {
                        HStack(spacing: 12) {
                            InitialsAvatarView(name: user.name, color: user.color)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("stellt einen neuen Abwesenheitsantrag.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(dayCount) Tag\(dayCount == 1 ? "" : "e")")
                                .font(.subheadline.weight(.semibold))
                            Text("von \(shortDateString(startDate)) bis \(shortDateString(endDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }

                // Admin: Mitarbeiter-Auswahl
                if isAdmin {
                    Section(header: Text("Mitarbeiter")) {
                        Picker("Für", selection: Binding(
                            get: { selectedUserId ?? appState.currentUser?.id },
                            set: { selectedUserId = $0 }
                        )) {
                            ForEach(appState.users) { u in
                                Text(u.name).tag(Optional(u.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Zeitraum
                Section(header: Text("Zeitraum")) {
                    DatePicker("Von", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { newStart in
                            if endDate < newStart {
                                endDate = newStart
                            }
                        }
                    DatePicker("Bis", selection: $endDate, in: startDate..., displayedComponents: .date)

                    Text("Dauer: \(dayCount) Tag\(dayCount == 1 ? "" : "e")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Art der Abwesenheit
                Section(header: Text("Art der Abwesenheit")) {
                    // Nur Urlaub und Krankheit zur Auswahl anbieten
                    let allowedTypes: [LeaveType] = [.vacation, .sick]

                    Picker("Art", selection: $selectedType) {
                        ForEach(allowedTypes, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !typeHint.isEmpty {
                        Text(typeHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isAdmin && selectedType == .vacation {
                        Toggle("Direkt genehmigen", isOn: $approveImmediately)
                    }
                }

                // Aktion
                Section {
                    Button(buttonTitle) {
                        guard let targetUser = selectedUser else {
                            inlineError = "Bitte einen Mitarbeiter auswählen."
                            return
                        }

                        let ok = appState.createLeaveRequest(start: startDate,
                                                             end: endDate,
                                                             type: selectedType,
                                                             for: targetUser,
                                                             approveImmediately: (selectedType == .vacation) ? (isAdmin && approveImmediately) : false)
                        if ok {
                            inlineError = nil
                            dismiss()
                        } else {
                            inlineError = appState.uiErrorMessage
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Abbrechen", role: .cancel) {
                        dismiss()
                    }
                }
            }
            .onChange(of: inlineError) { value in
                guard value != nil else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo("errorBanner", anchor: .top)
                }
            }
            .onChange(of: startDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: endDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: selectedType) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
                if selectedType == .sick {
                    approveImmediately = false
                }
            }
        }
        .navigationTitle("Neuer Antrag")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedUserId == nil {
                selectedUserId = preselectedUserId ?? appState.currentUser?.id
            }
            // Bei Krankheit macht "Direkt genehmigen" keinen Sinn
            if selectedType == .sick {
                approveImmediately = false
            }
        }
    }
}

// MARK: - Provisionen

struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Provisionen")
                        .font(.largeTitle.weight(.bold))

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                VStack(spacing: 12) {
                    Text("Provisionen")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Dieser Bereich wird später erweitert.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Tasks

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewTask = false
    @State private var editingTask: Task? = nil

    private var currentUser: User? { appState.currentUser }

    // Aufgaben-Sichten für Admin / Mitarbeiter
    private var myOpenTasks: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id && $0.status == .open }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var myDoneTasks: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var otherOpenTasks: [Task] {
        guard let user = currentUser, user.role == .admin else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId != user.id && $0.status == .open }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var otherDoneTasks: [Task] {
        guard let user = currentUser, user.role == .admin else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId != user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Aufgaben")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        showNewTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neue Aufgabe")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Group {
                    // Leer, wenn wirklich gar keine Aufgaben existieren
                    if myOpenTasks.isEmpty && otherOpenTasks.isEmpty && myDoneTasks.isEmpty && otherDoneTasks.isEmpty {
                        VStack(spacing: 12) {
                            Text("Noch keine Aufgaben")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Erstellen Sie eine neue Aufgabe mit dem Plus-Button oben rechts.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                    } else {
                        List {
                            if let user = currentUser, user.role == .admin {
                                // Admin: Meine offenen Aufgaben
                                if !myOpenTasks.isEmpty {
                                    Section(header: Text("Meine Aufgaben – Offen")) {
                                        ForEach(myOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: true,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                        }
                                    }
                                }

                                // Admin: Offene Aufgaben anderer
                                if !otherOpenTasks.isEmpty {
                                    Section(header: Text("Andere Aufgaben – Offen")) {
                                        ForEach(otherOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: true,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                        }
                                    }
                                }

                                // Link zu erledigten Aufgaben (nur wenn es welche gibt)
                                if !myDoneTasks.isEmpty || !otherDoneTasks.isEmpty {
                                    Section {
                                        NavigationLink {
                                            CompletedTasksView()
                                                .environmentObject(appState)
                                        } label: {
                                            HStack {
                                                Image(systemName: "checkmark.circle")
                                                Text("Erledigte Aufgaben anzeigen")
                                            }
                                        }
                                    }
                                }
                            } else {
                                // Mitarbeiter / Sachverständige: nur eigene offene Aufgaben
                                if !myOpenTasks.isEmpty {
                                    Section(header: Text("Offen")) {
                                        ForEach(myOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: false,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                        }
                                    }
                                }

                                // Link zu eigenen erledigten Aufgaben
                                if !myDoneTasks.isEmpty {
                                    Section {
                                        NavigationLink {
                                            CompletedTasksView()
                                                .environmentObject(appState)
                                        } label: {
                                            HStack {
                                                Image(systemName: "checkmark.circle")
                                                Text("Erledigte Aufgaben anzeigen")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showNewTask) {
                NewTaskView(mode: .new, task: nil)
                    .environmentObject(appState)
            }
            .sheet(item: $editingTask) { task in
                NewTaskView(mode: .edit, task: task)
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Completed Tasks View

struct CompletedTasksView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingTask: Task? = nil

    private var currentUser: User? { appState.currentUser }

    private var myDoneTasks: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var otherDoneTasks: [Task] {
        guard let user = currentUser, user.role == .admin else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId != user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if let user = currentUser, user.role == .admin {
                if !myDoneTasks.isEmpty {
                    Section(header: Text("Meine erledigten Aufgaben")) {
                        ForEach(myDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: true,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                        }
                    }
                }

                if !otherDoneTasks.isEmpty {
                    Section(header: Text("Erledigte Aufgaben anderer")) {
                        ForEach(otherDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: true,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                        }
                    }
                }

                if myDoneTasks.isEmpty && otherDoneTasks.isEmpty {
                    Text("Keine erledigten Aufgaben vorhanden")
                        .foregroundColor(.secondary)
                }
            } else {
                if !myDoneTasks.isEmpty {
                    Section(header: Text("Erledigte Aufgaben")) {
                        ForEach(myDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: false,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                        }
                    }
                } else {
                    Text("Keine erledigten Aufgaben vorhanden")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Erledigte Aufgaben")
        .sheet(item: $editingTask) { task in
            NewTaskView(mode: .edit, task: task)
                .environmentObject(appState)
        }
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: Task
    let isAdmin: Bool
    let assignedUserName: String
    let onEdit: () -> Void
    let onToggleStatus: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleStatus) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.status == .done ? .green : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .done, color: .secondary)

                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let due = task.dueDate {
                        Text("Fällig: \(formattedShort(due))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if isAdmin {
                        Text("für \(assignedUserName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Menu {
                Button("Bearbeiten", action: onEdit)
                Button("Löschen", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formattedShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        return df.string(from: date)
    }
}

// MARK: - New Task View

struct NewTaskView: View {
    enum Mode {
        case new
        case edit
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let task: Task?

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var assignedUser: User?
    @State private var status: TaskStatus = .open

    private var isEditing: Bool { task != nil }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Aufgabe")) {
                    TextField("Titel", text: $title)

                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section(header: Text("Fälligkeit")) {
                    Toggle("Fälligkeitsdatum setzen", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    }
                }

                if let current = appState.currentUser {
                    Section(header: Text("Zuständig")) {
                        if current.role == .admin {
                            Picker("Mitarbeiter", selection: Binding(
                                get: { assignedUser?.id ?? current.id },
                                set: { id in
                                    assignedUser = appState.users.first(where: { $0.id == id }) ?? current
                                })
                            ) {
                                ForEach(appState.users) { user in
                                    Text(user.name).tag(user.id)
                                }
                            }
                        } else {
                            Text(current.name)
                            Text("Aufgaben, die Sie erstellen, werden automatisch Ihnen zugewiesen.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if isEditing {
                    Section(header: Text("Status")) {
                        Picker("Status", selection: $status) {
                            Text("Offen").tag(TaskStatus.open)
                            Text("Erledigt").tag(TaskStatus.done)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(isEditing ? "Aufgabe bearbeiten" : "Neue Aufgabe")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || appState.currentUser == nil)
                }
            }
            .onAppear {
                configureInitialState()
            }
        }
    }

    private func configureInitialState() {
        guard let current = appState.currentUser else { return }

        if let task = task {
            title = task.title
            details = task.details
            if let due = task.dueDate {
                dueDate = due
                hasDueDate = true
            } else {
                hasDueDate = false
            }
            assignedUser = appState.users.first(where: { $0.id == task.assignedUserId }) ?? current
            status = task.status
        } else {
            // Neue Aufgabe
            title = ""
            details = ""
            hasDueDate = false
            dueDate = Date()
            assignedUser = current
            status = .open
        }
    }

    private func save() {
        guard let current = appState.currentUser else { return }
        let assigned = assignedUser ?? current
        let due: Date? = hasDueDate ? dueDate : nil

        switch mode {
        case .new:
            appState.createTask(title: title,
                                details: details,
                                dueDate: due,
                                assignedUser: assigned,
                                creator: current)
        case .edit:
            if var existing = task {
                existing.title = title
                existing.details = details
                existing.dueDate = due
                existing.assignedUserId = assigned.id
                existing.status = status
                appState.updateTask(existing)
            }
        }

        dismiss()
    }
}

// MARK: - Dashboard (WebView)

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dashboard")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                DashboardWebView(url: URL(string: "https://dashboard.sv-souleiman.de")!)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct DashboardWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        if uiView.url != url {
            uiView.load(request)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

// Kleine Avatar-View mit Initialen
struct InitialsAvatarView: View {
    let name: String
    let color: Color

    private var initials: String {
        let components = name
            .split(separator: " ")
            .compactMap { $0.first.map(String.init) }
        let joined = components.prefix(2).joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(width: 32, height: 32)
    }
}

// Hilfsfunktion für Rollenlabel (LoginView)

private func roleLabel(for role: UserRole) -> String {
    switch role {
    case .admin:
        return "Admin"
    case .employee:
        return "Mitarbeiter"
    case .expert:
        return "Sachverständiger"
    }
}

// MARK: - Menü

    struct MenuView: View {
        @EnvironmentObject var appState: AppState
        
        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Menü")
                            .font(.largeTitle.weight(.bold))
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    
                    List {
                        Section(header: Text("Benutzer")) {
                            if let user = appState.currentUser {
                                HStack {
                                    Text("Eingeloggt als:")
                                    Spacer()
                                    Text(user.name)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        
                        Section(header: Text("Aktionen")) {
                            Button(role: .destructive) {
                                appState.currentUser = nil
                                appState.sessionUserId = nil
                            } label: {
                                Label("Ausloggen", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                        
                        Section(header: Text("App-Info")) {
                            HStack {
                                Text("Version")
                                Spacer()
                                Text("1.0")
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Entwickelt für")
                                Spacer()
                                Text("SV Souleiman")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

