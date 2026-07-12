//
//  VehicleIdentificationStore.swift
//  SVS App
//
//  Lokale FIN- und Erstzulassungs-Speicherung aus Fahrzeugschein-Scans.
//

import Foundation

struct StoredVehicleIdentification: Codable, Equatable, Identifiable {
    var licensePlate: String
    var vin: String
    var firstRegistrationDate: Date?
    var updatedAt: Date

    var id: String { licensePlate }
}

enum VehicleIdentificationStore {
    private static let defaultsKey = "vehicle.identification.byPlate.v2"

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    static func normalizeVin(_ raw: String) -> String {
        raw
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseFirstRegistrationDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let iso = isoDateFormatter.date(from: trimmed) {
            return iso
        }
        if let german = germanDateFormatter.date(from: trimmed) {
            return german
        }

        if let match = trimmed.range(
            of: #"\d{2}\.\d{2}\.\d{4}"#,
            options: .regularExpression
        ) {
            return germanDateFormatter.date(from: String(trimmed[match]))
        }

        return nil
    }

    /// Liest Erstzulassung (Feld B) aus Fahrzeugschein-Text — nicht Feld 6 (Baudatum).
    static func parseErstzulassungDateFromScheinText(_ rawText: String) -> Date? {
        let normalized = rawText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let patterns = [
            #"(?i)(?:feld\s*)?b\b[^0-9]{0,80}(\d{2}\.\d{2}\.\d{4})"#,
            #"(?i)erstzulassung(?:\s+des\s+fahrzeugs)?[^0-9]{0,60}(\d{2}\.\d{2}\.\d{4})"#,
            #"(?i)datum\s+der\s+erstzulassung[^0-9]{0,40}(\d{2}\.\d{2}\.\d{4})"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  match.numberOfRanges > 1,
                  let dateRange = Range(match.range(at: 1), in: normalized),
                  let matchRange = Range(match.range, in: normalized) else {
                continue
            }

            let matchText = String(normalized[matchRange])
            if isForbiddenErstzulassungContext(matchText) {
                continue
            }

            if let date = parseFirstRegistrationDate(String(normalized[dateRange])) {
                return date
            }
        }

        return nil
    }

    private static func isForbiddenErstzulassungContext(_ snippet: String) -> Bool {
        let lowered = snippet.lowercased()
        if lowered.contains("datum zu 4") { return true }
        if lowered.contains("produktion") { return true }
        if lowered.contains("baujahr") { return true }
        if lowered.contains("baudatum") { return true }
        if lowered.contains("nächste hu") { return true }
        if lowered.contains("datum dieser zulassung") { return true }
        if lowered.range(of: #"\bzu\s*k\b"#, options: .regularExpression) != nil { return true }
        if snippet.range(of: #"(?:^|\s)6\b"#, options: .regularExpression) != nil,
           lowered.contains("datum") {
            return true
        }
        return false
    }

    static func formatFirstRegistrationDate(_ date: Date) -> String {
        germanDateFormatter.string(from: date)
    }

    private static func normalizePlate(_ raw: String) -> String {
        GermanLicensePlateFormatter.format(raw)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    static func remember(
        licensePlate: String,
        vin: String? = nil,
        firstRegistrationDate: Date? = nil
    ) {
        let plateKey = normalizePlate(licensePlate)
        guard !plateKey.isEmpty else { return }

        let normalizedVin = vin.map(normalizeVin)
        let hasVin = normalizedVin?.count == 17
        guard hasVin || firstRegistrationDate != nil else { return }

        var map = loadMap()
        var record = map[plateKey] ?? StoredVehicleIdentification(
            licensePlate: GermanLicensePlateFormatter.format(licensePlate),
            vin: "",
            firstRegistrationDate: nil,
            updatedAt: Date()
        )

        if hasVin, let normalizedVin {
            record.vin = normalizedVin
        }
        if let firstRegistrationDate {
            record.firstRegistrationDate = firstRegistrationDate
        }
        record.licensePlate = GermanLicensePlateFormatter.format(licensePlate)
        record.updatedAt = Date()

        map[plateKey] = record
        persist(map)
    }

    static func record(for licensePlate: String) -> StoredVehicleIdentification? {
        let plateKey = normalizePlate(licensePlate)
        guard !plateKey.isEmpty else { return nil }
        return loadMap()[plateKey]
    }

    static func vin(for licensePlate: String) -> String? {
        let value = record(for: licensePlate)?.vin
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func firstRegistrationDate(for licensePlate: String) -> Date? {
        record(for: licensePlate)?.firstRegistrationDate
    }

    static func allRecords() -> [StoredVehicleIdentification] {
        loadMap()
            .values
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func loadMap() -> [String: StoredVehicleIdentification] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(
                [String: StoredVehicleIdentification].self,
                from: data
              ) else {
            return [:]
        }
        return decoded
    }

    private static func persist(_ map: [String: StoredVehicleIdentification]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
