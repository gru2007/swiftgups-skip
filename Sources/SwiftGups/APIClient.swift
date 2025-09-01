// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import SkipFuse
import Observation

/// API клиент для работы с расписанием ДВГУПС
@Observable public class DVGUPSAPIClient: @unchecked Sendable {
    
    // MARK: - Константы
    
    private let baseURL = "https://dvgups.ru/index.php"
    private let itemId = "1246"
    private let option = "com_timetable"
    private let view = "newtimetable"
    
    private let session: URLSession
    
    // MARK: - Инициализация
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Публичные методы
    
    /// Получает список групп для выбранного факультета
    public func fetchGroups(for facultyId: String, date: Date = Date()) async throws -> [Group] {
        let dateString = Date.apiDateFormatter.string(from: date)
        let requestBody = "FacID=\(facultyId)&GroupID=no&Time=\(dateString)"
        
        logger.info("🌐 APIClient.fetchGroups() - Faculty: \(facultyId), Date: \(dateString)")
        logger.info("📤 Request body: \(requestBody)")
        
        let htmlResponse = try await performRequest(body: requestBody)
        let groups = parseGroups(from: htmlResponse, facultyId: facultyId)
        
        logger.info("🔍 Parsed \(groups.count) groups from response")
        if groups.isEmpty {
            logger.warning("⚠️ No groups found in HTML response for faculty \(facultyId)")
            // Логируем часть HTML для отладки
            let preview = String(htmlResponse.prefix(500))
            logger.info("📄 HTML preview: \(preview)")
        }
        
        return groups
    }
    
    /// Получает расписание для конкретной группы
    public func fetchSchedule(for groupId: String, startDate: Date = Date(), endDate: Date? = nil) async throws -> Schedule {
        let dateString = Date.apiDateFormatter.string(from: startDate)
        let requestBody = "GroupID=\(groupId)&Time=\(dateString)"
        
        let htmlResponse = try await performRequest(body: requestBody)
        return try parseSchedule(from: htmlResponse, groupId: groupId, startDate: startDate, endDate: endDate)
    }
    
    /// Получает расписание по аудиториям для выбранной даты
    public func fetchScheduleByAuditorium(date: Date = Date()) async throws -> [ScheduleDay] {
        let dateString = Date.apiDateFormatter.string(from: date)
        let requestBody = "AudID=no&Time=\(dateString)"
        
        let htmlResponse = try await performRequest(body: requestBody)
        return parseScheduleDays(from: htmlResponse)
    }
    
    /// Получает расписание по преподавателям для выбранной даты
    public func fetchScheduleByTeacher(date: Date = Date()) async throws -> [ScheduleDay] {
        let dateString = Date.apiDateFormatter.string(from: date)
        let requestBody = "PrepID=no&Time=\(dateString)"
        
        let htmlResponse = try await performRequest(body: requestBody)
        return parseScheduleDays(from: htmlResponse)
    }
    
    // MARK: - Приватные методы
    
    /// Создает базовый URL для API запросов
    private func createBaseURL() -> URL? {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "Itemid", value: itemId),
            URLQueryItem(name: "option", value: option),
            URLQueryItem(name: "view", value: view)
        ]
        return components?.url
    }
    
    /// Выполняет HTTP POST запрос к API
    private func performRequest(body: String) async throws -> String {
        guard let url = createBaseURL() else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://dvgups.ru/", forHTTPHeaderField: "Referer")
        request.setValue("dvgups.ru", forHTTPHeaderField: "Host")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 20
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }
            
            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw APIError.noData
            }
            
            return htmlString
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                    // Часто возникает при активном VPN/блокировке
                    throw APIError.vpnOrBlockedNetwork
                default:
                    break
                }
            }
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Парсинг HTML
    
    /// Парсит список групп из HTML ответа
    private func parseGroups(from html: String, facultyId: String) -> [Group] {
        var groups: [Group] = []
        
        // Ищем все option теги с группами
        let optionPattern = #"<option value='(\d+)'>гр\.\s*([^-]+)\s*-\s*([^<]+)</option>"#
        let regex = try? NSRegularExpression(pattern: optionPattern, options: [])
        let nsString = html as NSString
        let results = regex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        logger.info("🔍 Found \(results.count) regex matches for groups pattern")
        
        if results.isEmpty {
            // Попробуем найти любые option теги для отладки
            let anyOptionPattern = #"<option[^>]*>(.*?)</option>"#
            let debugRegex = try? NSRegularExpression(pattern: anyOptionPattern, options: [])
            let debugResults = debugRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
            logger.info("🐛 Found \(debugResults.count) total option tags in response")
            
            // Показываем первые несколько option тегов для отладки
            for (index, match) in debugResults.prefix(5).enumerated() {
                if match.numberOfRanges > 0 {
                    let matchRange = match.range(at: 0)
                    let matchText = nsString.substring(with: matchRange)
                    logger.info("🐛 Option \(index + 1): \(matchText)")
                }
            }
        }
        
        for result in results {
            guard result.numberOfRanges == 4 else { continue }
            
            let groupIdRange = result.range(at: 1)
            let groupNameRange = result.range(at: 2)
            let fullNameRange = result.range(at: 3)
            
            guard groupIdRange.location != NSNotFound,
                  groupNameRange.location != NSNotFound,
                  fullNameRange.location != NSNotFound else { continue }
            
            let groupId = nsString.substring(with: groupIdRange)
            let groupName = nsString.substring(with: groupNameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let fullName = nsString.substring(with: fullNameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            let group = Group(id: groupId, name: groupName, fullName: fullName, facultyId: facultyId)
            groups.append(group)
            logger.info("✅ Parsed group: \(groupName) (ID: \(groupId))")
        }
        
        return groups.sorted { $0.name < $1.name }
    }
    
    /// Парсит расписание из HTML ответа
    private func parseSchedule(from html: String, groupId: String, startDate: Date, endDate: Date?) throws -> Schedule {
        let days = parseScheduleDays(from: html)
        
        // Получаем название группы из HTML (если возможно)
        let groupName = extractGroupName(from: html) ?? "Группа \(groupId)"
        
        return Schedule(
            groupId: groupId,
            groupName: groupName,
            startDate: startDate,
            endDate: endDate,
            days: days
        )
    }
    
    /// Парсит дни расписания из HTML ответа
    private func parseScheduleDays(from html: String) -> [ScheduleDay] {
        var days: [ScheduleDay] = []
        
        // Парсим заголовки дней (например: "01.09.2025 Понедельник (2-я неделя)")
        let dayHeaderPattern = #"<h3>(\d{2}\.\d{2}\.\d{4})\s+([А-Я][а-я]+)\s+\((\d+)-я неделя\)</h3>"#
        let dayRegex = try? NSRegularExpression(pattern: dayHeaderPattern, options: [])
        
        // Парсим таблицы с занятиями
        let tablePattern = #"<h3>.*?</h3><table.*?>(.*?)</table>"#
        let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators])
        
        let nsString = html as NSString
        let dayMatches = dayRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        let tableMatches = tableRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        guard dayMatches.count == tableMatches.count else {
            return days
        }
        
        for (index, dayMatch) in dayMatches.enumerated() {
            guard dayMatch.numberOfRanges == 4,
                  index < tableMatches.count else { continue }
            
            let dateRange = dayMatch.range(at: 1)
            let weekdayRange = dayMatch.range(at: 2)
            let weekNumberRange = dayMatch.range(at: 3)
            let tableContentRange = tableMatches[index].range(at: 1)
            
            guard dateRange.location != NSNotFound,
                  weekdayRange.location != NSNotFound,
                  weekNumberRange.location != NSNotFound,
                  tableContentRange.location != NSNotFound else { continue }
            
            let dateString = nsString.substring(with: dateRange)
            let weekdayString = nsString.substring(with: weekdayRange)
            let weekNumberString = nsString.substring(with: weekNumberRange)
            let tableContent = nsString.substring(with: tableContentRange)
            
            guard let date = Date.apiDateFormatter.date(from: dateString),
                  let weekNumber = Int(weekNumberString) else { continue }
            
            let lessons = parseLessons(from: tableContent)
            let isEvenWeek = weekNumber % 2 == 0
            
            let scheduleDay = ScheduleDay(
                date: date,
                weekday: weekdayString,
                weekNumber: weekNumber,
                isEvenWeek: isEvenWeek,
                lessons: lessons
            )
            
            days.append(scheduleDay)
        }
        
        return days.sorted { $0.date < $1.date }
    }
    
    /// Парсит занятия из HTML таблицы
    private func parseLessons(from tableHtml: String) -> [Lesson] {
        var lessons: [Lesson] = []
        
        // Упрощенный паттерн для парсинга строк таблицы
        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
        let nsString = tableHtml as NSString
        let rowResults = rowRegex?.matches(in: tableHtml, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for rowResult in rowResults {
            let rowContent = nsString.substring(with: rowResult.range(at: 1))
            
            // Парсим отдельные компоненты урока
            if let lesson = parseIndividualLesson(from: rowContent) {
                lessons.append(lesson)
            }
        }
        
        return lessons.sorted { $0.pairNumber < $1.pairNumber }
    }
    
    /// Парсит отдельный урок из HTML строки таблицы
    private func parseIndividualLesson(from rowContent: String) -> Lesson? {
        // Парсим номер пары
        let pairNumberPattern = #"<b[^>]*>\s*(\d+)-я пара\s*</b>"#
        let pairNumberRegex = try? NSRegularExpression(pattern: pairNumberPattern)
        let pairNumberMatch = pairNumberRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        guard let pairMatch = pairNumberMatch,
              let pairRange = Range(pairMatch.range(at: 1), in: rowContent) else {
            return nil
        }
        
        let pairNumber = Int(String(rowContent[pairRange])) ?? 0
        
        // Парсим время
        let timePattern = #"(\d{2}:\d{2}-\d{2}:\d{2})"#
        let timeRegex = try? NSRegularExpression(pattern: timePattern)
        let timeMatch = timeRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        guard let timeMatchResult = timeMatch,
              let timeRange = Range(timeMatchResult.range(at: 1), in: rowContent) else {
            return nil
        }
        
        let timeString = String(rowContent[timeRange])
        let timeComponents = timeString.split(separator: "-")
        guard timeComponents.count == 2 else { return nil }
        
        // Парсим предмет и тип занятия
        let subjectPattern = #"<div>\(([^)]+)\)\s*([^<]+)</div>"#
        let subjectRegex = try? NSRegularExpression(pattern: subjectPattern)
        let subjectMatch = subjectRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        var lessonType = LessonType.lecture
        var subject = ""
        
        if let subjectMatchResult = subjectMatch,
           let typeRange = Range(subjectMatchResult.range(at: 1), in: rowContent),
           let subjRange = Range(subjectMatchResult.range(at: 2), in: rowContent) {
            lessonType = LessonType(from: String(rowContent[typeRange]))
            subject = String(rowContent[subjRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Парсим дополнительную информацию (ZOOM, Discord, etc.)
        let additionalInfoPattern = #"<div>([^<]*(?:ZOOM|Discord|FreeConferenceCall|код доступа|Идентификатор)[^<]*)</div>"#
        let additionalInfoRegex = try? NSRegularExpression(pattern: additionalInfoPattern, options: [.caseInsensitive])
        let additionalInfoMatch = additionalInfoRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        var onlineInfo: String? = nil
        if let additionalInfoMatchResult = additionalInfoMatch,
           let infoRange = Range(additionalInfoMatchResult.range(at: 1), in: rowContent) {
            let info = String(rowContent[infoRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !info.isEmpty {
                onlineInfo = info
            }
        }
        
        // Парсим аудиторию - ищем в td с wrap
        let auditoriumPattern = #"<td[^>]*wrap[^>]*>([^<]*)</td>"#
        let auditoriumRegex = try? NSRegularExpression(pattern: auditoriumPattern)
        let auditoriumMatch = auditoriumRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        var auditorium: String? = nil
        if let auditoriumMatchResult = auditoriumMatch,
           let audRange = Range(auditoriumMatchResult.range(at: 1), in: rowContent) {
            let aud = String(rowContent[audRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !aud.isEmpty && aud != " " {
                auditorium = aud
            }
        }
        
        // Парсим преподавателя
        let teacherPattern = #"<div>([^<]+?)(?:\s*<a[^>]*href='mailto:([^']+)'[^>]*>&#9993;</a>)?</div>"#
        let teacherRegex = try? NSRegularExpression(pattern: teacherPattern)
        
        var teacher: Teacher? = nil
        let teacherMatches = teacherRegex?.matches(in: rowContent, options: [], range: NSRange(location: 0, length: rowContent.count)) ?? []
        
        // Берем последний матч - обычно это преподаватель
        if let lastTeacherMatch = teacherMatches.last,
           let nameRange = Range(lastTeacherMatch.range(at: 1), in: rowContent) {
            let teacherName = String(rowContent[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Проверяем что это не пустое поле и не другие данные
            if !teacherName.isEmpty && 
               teacherName != " " && 
               !teacherName.contains("wrap") &&
               !teacherName.contains("БО2") { // исключаем названия групп
                
                var teacherEmail: String? = nil
                if lastTeacherMatch.numberOfRanges > 2,
                   let emailRange = Range(lastTeacherMatch.range(at: 2), in: rowContent) {
                    let email = String(rowContent[emailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !email.isEmpty {
                        teacherEmail = email
                    }
                }
                
                teacher = Teacher(name: teacherName, email: teacherEmail)
            }
        }
        
        return Lesson(
            pairNumber: pairNumber,
            timeStart: String(timeComponents[0]),
            timeEnd: String(timeComponents[1]),
            type: lessonType,
            subject: subject,
            room: auditorium,
            teacher: teacher,
            groups: [],
            onlineLink: onlineInfo
        )
    }
    
    /// Извлекает название группы из HTML (если возможно)
    private func extractGroupName(from html: String) -> String? {
        // Ищем название группы в HTML
        let groupPattern = #"(?:гр\.\s*|группа\s*)([А-Я0-9]+[А-Я]{3})"#
        let regex = try? NSRegularExpression(pattern: groupPattern, options: [.caseInsensitive])
        let nsString = html as NSString
        
        if let match = regex?.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
           match.numberOfRanges > 1 {
            let groupNameRange = match.range(at: 1)
            return nsString.substring(with: groupNameRange)
        }
        
        return nil
    }
}
