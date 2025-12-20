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

    @Published var lastUserId: UUID? = nil {
        didSet {
            if let id = lastUserId {
                UserDefaults.standard.set(id.uuidString, forKey: "lastUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastUserId")
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

        // Krankheit wird sofort genehmigt, alles andere zunächst "Offen"
        let initialStatus: LeaveStatus = (type == .sick) ? .approved : .pending

        let request = LeaveRequest(
            id: UUID(),
            user: user,
            startDate: start,
            endDate: end,
            type: type,
            reason: "",
            status: initialStatus
        )
        leaveRequests.append(request)
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
            leaveRequests[index] = updated
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
        Group {
            if appState.currentUser == nil {
                LoginView()
            } else {
                MainView()
            }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedUser: User? = nil
    @State private var pin: String = ""
    @State private var showError: Bool = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Logo + Titel
                VStack(spacing: 8) {
                    Image("svs_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 70)
                        .padding(.horizontal, 40)

                    Text("SVS Mitarbeiter-App")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Mitarbeiter wählen und mit PIN bestätigen.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 16)

                // Zuletzt verwendeter Benutzer (optional)
                if let lastId = appState.lastUserId,
                   let lastUser = appState.users.first(where: { $0.id == lastId }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zuletzt verwendet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        Button {
                            selectedUser = lastUser
                            pin = ""
                        } label: {
                            HStack(spacing: 12) {
                                InitialsAvatarView(name: lastUser.name, color: lastUser.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lastUser.name)
                                        .font(.body.weight(.semibold))
                                    Text(roleLabel(for: lastUser.role))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                // Mitarbeiterliste
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mitarbeiter")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(appState.users) { user in
                                Button {
                                    selectedUser = user
                                    pin = ""
                                } label: {
                                    let selected = selectedUser?.id == user.id
                                    HStack(spacing: 12) {
                                        InitialsAvatarView(name: user.name, color: user.color)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.name)
                                                .font(.body.weight(selected ? .semibold : .regular))
                                            Text(roleLabel(for: user.role))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 260)
                }

                // PIN-Bereich
                if let selected = selectedUser {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PIN eingeben")
                            .font(.headline)

                        Text("Für \(selected.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SecureField("PIN", text: $pin)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            if pin == selected.pin {
                                appState.currentUser = selected
                                appState.lastUserId = selected.id
                                pin = ""
                                selectedUser = nil
                            } else {
                                showError = true
                            }
                        } label: {
                            Text("Anmelden")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.isEmpty)
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 8)
            }
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

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Übersicht")) {
                    NavigationLink {
                        AdminRequestsScreen()
                            .environmentObject(appState)
                    } label: {
                        Label("Anträge", systemImage: "doc.text.magnifyingglass")
                    }

                    NavigationLink {
                        AdminUsersScreen()
                            .environmentObject(appState)
                    } label: {
                        Label("Mitarbeiter", systemImage: "person.2")
                    }
                }
            }
            .navigationTitle("Admin")
        }
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

struct AdminRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var editingRequest: LeaveRequest?

    private var openRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { $0.type == .vacation && $0.status == .pending }
            .sorted { $0.startDate > $1.startDate }
    }

    // Beantwortete Anträge (inkl. Krankheit) – nach Monat gruppiert
    private var answeredRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { !($0.type == .vacation && $0.status == .pending) }
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
        NavigationView {
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
            .navigationTitle("Freigaben")
            .sheet(item: $editingRequest) { request in
                NavigationView {
                    EditLeaveRequestView(request: request)
                }
            }
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

    private var isVacation: Bool { request.type == .vacation }
    private var accent: Color {
        request.type == .sick ? Color.gray : colorForLeaveStatus(request.status)
    }

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

// MARK: - Admin Users Screen

struct AdminUsersScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddUser = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Mitarbeiter & Resturlaub")) {
                    ForEach(appState.users) { user in
                        NavigationLink(destination: EditUserView(user: user)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(user.name)
                                        .font(.headline)
                                        .foregroundColor(user.color)
                                    Spacer()
                                    Text(roleText(for: user.role))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                let used = appState.usedVacationDays(for: user)
                                let remaining = appState.remainingLeaveDays(for: user)
                                Text("Jahresurlaub: \(user.annualLeaveDays) Tage")
                                    .font(.caption)
                                Text("Genutzt: \(used) Tage")
                                    .font(.caption2)
                                Text("Resturlaub: \(remaining) Tage")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Mitarbeiter")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddUser = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddUser) {
                NavigationView {
                    AddUserView()
                }
            }
        }
    }

    private func roleText(for role: UserRole) -> String {
        switch role {
        case .admin:
            return "Admin"
        case .employee:
            return "Mitarbeiter"
        case .expert:
            return "Sachverständiger"
        }
    }
}

struct EditUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var user: User

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
        NavigationView {
            VStack {
                MonthHeader(currentMonth: $currentMonth)

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

                List {
                    Section(header: Text("Anträge am \(formatted(selectedDate))")) {
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
            .navigationTitle("Urlaubskalender")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: NewLeaveRequestView()) {
                        Image(systemName: "plus.circle.fill")
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
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(title.capitalized)
                .font(.headline)
            Spacer()
            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeekday = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)?.start
        else {
            return []
        }

        var dates: [Date] = []
        for offset in 0..<42 { // 6 Wochen
            if let date = calendar.date(byAdding: .day, value: offset, to: firstWeekday) {
                dates.append(date)
            }
        }
        return dates
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
                    let approvedRequests = appState.requests(for: date).filter { $0.status == .approved }
                    let approvedColors = approvedRequests.map { $0.user.color }
                    let isHoliday = isPublicHolidayBremen(date)

                    DayCell(
                        date: date,
                        isCurrentMonth: Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month),
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        approvedColors: approvedColors,
                        isHoliday: isHoliday
                    )
                    .onTapGesture {
                        selectedDate = date
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
        let day = Calendar.current.component(.day, from: date)

        Text("\(day)")
            .font(.callout)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(4)
            .background(
                Group {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor.opacity(0.25))
                    } else if !approvedColors.isEmpty {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Circle().fill(Color.clear)
                    }
                }
            )
            .foregroundColor(
                isHoliday ? .red : (isCurrentMonth ? .primary : .secondary)
            )
    }

    private var gradientColors: [Color] {
        if approvedColors.count == 1 {
            let c = approvedColors[0]
            return [c.opacity(0.8), c.opacity(0.4)]
        } else {
            return approvedColors.map { $0.opacity(0.8) }
        }
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

// Zählt nur Werktage (Montag–Freitag) zwischen zwei Daten, inkl. Start- und Enddatum
func workingDays(from start: Date, to end: Date) -> Int {
    let calendar = Calendar.current
    var date = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)
    var count = 0

    while date <= endDay {
        let weekday = calendar.component(.weekday, from: date)
        // 1 = Sonntag, 7 = Samstag
        // Zusätzlich: deutsche Feiertage nicht mitzählen
        if weekday != 1 && weekday != 7 && !isPublicHolidayBremen(date) {
            count += 1
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
        date = next
    }

    return max(count, 0)
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
        NavigationView {
            List {
                Section(header: MyRequestsHeaderView(counts: counts)) {
                    if myRequests.isEmpty {
                        Text("Noch keine Anträge")
                            .foregroundColor(.secondary)
                    } else {
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
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Urlaubsanträge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: NewLeaveRequestView()) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(item: $editingRequest) { request in
                NavigationView {
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
                if counts.pending == 0 && counts.approved == 0 && counts.rejected == 0 {
                    Text("Noch keine Anträge")
                }
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
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var selectedType: LeaveType = .vacation
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
                    if let user = appState.currentUser {
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
                }

                // Aktion
                Section {
                    Button(buttonTitle) {
                        let ok = appState.createLeaveRequest(start: startDate,
                                                             end: endDate,
                                                             type: selectedType)
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
            }
        }
        .navigationTitle("Neuer Antrag")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Provisionen

struct ProvisionenView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationView {
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
            .navigationTitle("Provisionen")
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
        NavigationView {
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
            .navigationTitle("Aufgaben")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNewTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
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
        NavigationView {
            DashboardWebView(url: URL(string: "https://dashboard.sv-souleiman.de")!)
                .navigationTitle("Dashboard")
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
        NavigationView {
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
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
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
            .navigationTitle("Menü")
        }
    }
}
