// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import SkipFuse
import SkipSQL

/// Факультет/Институт
public struct Faculty: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
    
    /// Все доступные факультеты ДВГУПС
    public static let allFaculties = [
        Faculty(id: "8", name: "Естественно-научный институт"),
        Faculty(id: "5", name: "Институт воздушных сообщений и мультитранспортных технологий"),
        Faculty(id: "11", name: "Институт интегрированных форм обучения"),
        Faculty(id: "9", name: "Институт международного сотрудничества"),
        Faculty(id: "4", name: "Институт транспортного строительства"),
        Faculty(id: "1", name: "Институт тяги и подвижного состава"),
        Faculty(id: "2", name: "Институт управления, автоматизации и телекоммуникаций"),
        Faculty(id: "3", name: "Институт экономики"),
        Faculty(id: "10", name: "Медицинское училище"),
        Faculty(id: "34", name: "Российско-китайский транспортный институт"),
        Faculty(id: "7", name: "Социально-гуманитарный институт"),
        Faculty(id: "19", name: "Хабаровский техникум железнодорожного транспорта"),
        Faculty(id: "6", name: "Электроэнергетический институт"),
        Faculty(id: "-1", name: "АмИЖТ"),
        Faculty(id: "-2", name: "БамИЖТ"),
        Faculty(id: "-3", name: "ПримИЖТ"),
        Faculty(id: "-4", name: "СахИЖТ")
    ]
}

/// Группа студентов
public struct Group: Codable, Identifiable, Hashable, Sendable {
    public let id: String // GroupID из API
    public let name: String // Название группы (например, "БО241ИСТ")
    public let fullName: String // Полное название специальности
    public let facultyId: String // ID факультета
    
    public init(id: String, name: String, fullName: String, facultyId: String = "") {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.facultyId = facultyId
    }
}

/// Тип занятия
public enum LessonType: String, Codable, CaseIterable, Sendable {
    case lecture = "Лекции"
    case practice = "Практика"
    case laboratory = "Лабораторные работы"
    case unknown = "Неизвестно"
    
    public init(from rawValue: String) {
        switch rawValue.lowercased() {
        case "лекции":
            self = .lecture
        case "практика":
            self = .practice
        case "лабораторные работы":
            self = .laboratory
        default:
            self = .unknown
        }
    }
}

/// Преподаватель
public struct Teacher: Codable, Sendable, Equatable {
    public let name: String
    public let email: String?
    
    public init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

/// Пара (занятие)
public struct Lesson: Codable, Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let pairNumber: Int // Номер пары (1-6)
    public let timeStart: String // Время начала (например, "09:50")
    public let timeEnd: String // Время окончания (например, "11:20")
    public let type: LessonType // Тип занятия
    public let subject: String // Название предмета
    public let room: String? // Аудитория
    public let teacher: Teacher? // Преподаватель
    public let groups: [String] // Группы, которые присутствуют на занятии
    public let onlineLink: String? // Ссылка на онлайн-занятие
    public let isEvenWeek: Bool? // Четная/нечетная неделя (может быть не указано)
    
    public init(pairNumber: Int, timeStart: String, timeEnd: String, type: LessonType, 
         subject: String, room: String? = nil, teacher: Teacher? = nil, 
         groups: [String] = [], onlineLink: String? = nil, isEvenWeek: Bool? = nil) {
        self.pairNumber = pairNumber
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.type = type
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.groups = groups
        self.onlineLink = onlineLink
        self.isEvenWeek = isEvenWeek
    }
    
    public static func == (lhs: Lesson, rhs: Lesson) -> Bool {
        return lhs.pairNumber == rhs.pairNumber &&
               lhs.timeStart == rhs.timeStart &&
               lhs.timeEnd == rhs.timeEnd &&
               lhs.type == rhs.type &&
               lhs.subject == rhs.subject &&
               lhs.room == rhs.room &&
               lhs.teacher == rhs.teacher &&
               lhs.groups == rhs.groups &&
               lhs.onlineLink == rhs.onlineLink &&
               lhs.isEvenWeek == rhs.isEvenWeek
    }
}

/// День расписания
public struct ScheduleDay: Codable, Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let date: Date
    public let weekday: String // Например, "Понедельник"
    public let weekNumber: Int? // Номер недели (может быть не указан)
    public let isEvenWeek: Bool? // Четная/нечетная неделя
    public let lessons: [Lesson]
    
    public init(date: Date, weekday: String, weekNumber: Int? = nil, 
         isEvenWeek: Bool? = nil, lessons: [Lesson] = []) {
        self.date = date
        self.weekday = weekday
        self.weekNumber = weekNumber
        self.isEvenWeek = isEvenWeek
        self.lessons = lessons
    }
    
    public static func == (lhs: ScheduleDay, rhs: ScheduleDay) -> Bool {
        return lhs.date == rhs.date &&
               lhs.weekday == rhs.weekday &&
               lhs.weekNumber == rhs.weekNumber &&
               lhs.isEvenWeek == rhs.isEvenWeek &&
               lhs.lessons == rhs.lessons
    }
}

/// Расписание для группы
public struct Schedule: Codable, Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let groupId: String
    public let groupName: String
    public let facultyId: String
    public let startDate: Date // Начальная дата периода
    public let endDate: Date // Конечная дата периода
    public let days: [ScheduleDay]
    public let lastUpdated: Date
    
    public init(groupId: String, groupName: String, facultyId: String = "",
         startDate: Date, endDate: Date? = nil, 
         days: [ScheduleDay] = [], lastUpdated: Date = Date()) {
        self.groupId = groupId
        self.groupName = groupName
        self.facultyId = facultyId
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(7 * 24 * 60 * 60) // По умолчанию неделя
        self.days = days
        self.lastUpdated = lastUpdated
    }
    
    public static func == (lhs: Schedule, rhs: Schedule) -> Bool {
        return lhs.groupId == rhs.groupId &&
               lhs.groupName == rhs.groupName &&
               lhs.facultyId == rhs.facultyId &&
               lhs.startDate == rhs.startDate &&
               lhs.endDate == rhs.endDate &&
               lhs.days == rhs.days &&
               lhs.lastUpdated == rhs.lastUpdated
    }
}

/// Пользователь приложения (хранится в SQLite)
public struct User: Identifiable, SQLCodable, Sendable {
    public let id: UUID
    static let id = SQLColumn(name: "id", type: .text, primaryKey: true, nullable: false)
    
    public var name: String
    static let name = SQLColumn(name: "name", type: .text, nullable: false)
    
    public var facultyId: String
    static let facultyId = SQLColumn(name: "faculty_id", type: .text, nullable: false)
    
    public var facultyName: String
    static let facultyName = SQLColumn(name: "faculty_name", type: .text, nullable: false)
    
    public var groupId: String
    static let groupId = SQLColumn(name: "group_id", type: .text, nullable: false)
    
    public var groupName: String
    static let groupName = SQLColumn(name: "group_name", type: .text, nullable: false)
    
    public var createdAt: Date
    static let createdAt = SQLColumn(name: "created_at", type: .text, nullable: false)
    
    public var isFirstTime: Bool
    static let isFirstTime = SQLColumn(name: "is_first_time", type: .long, nullable: false)
    
    // SKIP @nobridge
    public static let table = SQLTable(name: "users", columns: [id, name, facultyId, facultyName, groupId, groupName, createdAt, isFirstTime])
    
    public init(id: UUID = UUID(), name: String = "", facultyId: String = "", facultyName: String = "", groupId: String = "", groupName: String = "", createdAt: Date = Date(), isFirstTime: Bool = true) {
        self.id = id
        self.name = name
        self.facultyId = facultyId
        self.facultyName = facultyName
        self.groupId = groupId
        self.groupName = groupName
        self.createdAt = createdAt
        self.isFirstTime = isFirstTime
    }
    
    // SKIP @nobridge
    public init(row: SQLRow, context: SQLContext) throws {
        self.id = try UUID(uuidString: Self.id.textValueRequired(in: row)) ?? UUID()
        self.name = try Self.name.textValueRequired(in: row)
        self.facultyId = try Self.facultyId.textValueRequired(in: row)
        self.facultyName = try Self.facultyName.textValueRequired(in: row)
        self.groupId = try Self.groupId.textValueRequired(in: row)
        self.groupName = try Self.groupName.textValueRequired(in: row)
        self.createdAt = try Self.createdAt.dateValueRequired(in: row)
        self.isFirstTime = try Self.isFirstTime.longValueRequired(in: row) != 0
    }
    
    // SKIP @nobridge
    public func encode(row: inout SQLRow) throws {
        row[Self.id] = SQLValue(self.id.uuidString)
        row[Self.name] = SQLValue(self.name)
        row[Self.facultyId] = SQLValue(self.facultyId)
        row[Self.facultyName] = SQLValue(self.facultyName)
        row[Self.groupId] = SQLValue(self.groupId)
        row[Self.groupName] = SQLValue(self.groupName)
        row[Self.createdAt] = SQLValue(self.createdAt.ISO8601Format())
        row[Self.isFirstTime] = SQLValue(self.isFirstTime ? 1 : 0)
    }
    
    public mutating func updateGroup(groupId: String, groupName: String) {
        self.groupId = groupId
        self.groupName = groupName
    }
    
    public mutating func updateFaculty(facultyId: String, facultyName: String) {
        self.facultyId = facultyId
        self.facultyName = facultyName
    }
}

// MARK: - Вспомогательные расширения

extension Date {
    /// Форматтер для парсинга дат из API (например, "01.09.2025")
    public static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()
    
    /// Форматтер для отображения дат пользователю
    public static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, EEEE"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()
}

extension String {
    /// Проверяет, содержит ли строка URL
    public var containsURL: Bool {
        // Простая проверка на наличие URL паттернов
        return self.lowercased().contains("http://") || 
               self.lowercased().contains("https://") ||
               self.lowercased().contains("www.")
    }
    
    /// Извлекает URLs из строки
    public var extractedURLs: [URL] {
        // Упрощенная версия для Skip
        var urls: [URL] = []
        
        // Ищем http/https URLs
        let components = self.components(separatedBy: .whitespacesAndNewlines)
        for component in components {
            if component.lowercased().starts(with: "http://") || component.lowercased().starts(with: "https://") {
                if let url = URL(string: component) {
                    urls.append(url)
                }
            } else if component.lowercased().starts(with: "www.") {
                if let url = URL(string: "https://\(component)") {
                    urls.append(url)
                }
            }
        }
        
        return urls
    }
}

/// Время пар (расписание звонков)
public struct LessonTime: Identifiable, Codable, Sendable {
    public let id = UUID()
    public let number: Int
    public let startTime: String
    public let endTime: String
    
    public var timeRange: String {
        return "\(startTime) - \(endTime)"
    }
    
    /// Стандартное расписание звонков ДВГУПС
    public static let schedule = [
        LessonTime(number: 1, startTime: "8:05", endTime: "9:35"),
        LessonTime(number: 2, startTime: "9:50", endTime: "11:20"),
        LessonTime(number: 3, startTime: "11:35", endTime: "13:05"),
        LessonTime(number: 4, startTime: "13:35", endTime: "15:05"),
        LessonTime(number: 5, startTime: "15:15", endTime: "16:45"),
        LessonTime(number: 6, startTime: "16:55", endTime: "18:25")
    ]
    
    public static func timeForPair(_ number: Int) -> LessonTime? {
        return schedule.first { $0.number == number }
    }
    
    public init(number: Int, startTime: String, endTime: String) {
        self.number = number
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Ошибки API
public enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case noData
    case parseError(String)
    case networkError(Error)
    case invalidResponse
    case groupNotFound
    case facultyNotFound
    case vpnOrBlockedNetwork
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .noData:
            return "Нет данных в ответе"
        case .parseError(let message):
            return "Ошибка парсинга: \(message)"
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        case .invalidResponse:
            return "Неверный формат ответа сервера"
        case .groupNotFound:
            return "Группа не найдена"
        case .facultyNotFound:
            return "Факультет не найден"
        case .vpnOrBlockedNetwork:
            return "Не удалось подключиться к серверу. Возможно включен VPN или сеть блокирует доступ к dvgups.ru. Отключите VPN/смените сервер и повторите попытку."
        }
    }
}
