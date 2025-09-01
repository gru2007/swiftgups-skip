// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import SkipFuse
import SkipSQL
import SkipSQLPlus

/// The Observable ViewModel used by the application.
@Observable public class ViewModel: @unchecked Sendable {
    public static let shared = try! ViewModel(dbPath: URL.applicationSupportDirectory.appendingPathComponent("swiftgups.sqlite"))
    
    private let dbPath: URL
    internal var db: SQLContext
    private let apiClient: DVGUPSAPIClient
    
    // MARK: - State
    
    public var currentUser: User? = nil
    public var isFirstLaunch: Bool = true
    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    
    // Schedule state
    public var currentSchedule: Schedule? = nil
    public var selectedDate: Date = Date()
    public var selectedFaculty: Faculty? = nil
    public var selectedGroup: Group? = nil
    public var availableGroups: [Group] = []
    public var faculties: [Faculty] = Faculty.allFaculties
    public var groupsUpdateCounter: Int = 0
    public var scheduleUpdateCounter: Int = 0
    
    // MARK: - Initialization
    
    init(dbPath: URL) throws {
        logger.info("Initializing SwiftGups ViewModel with database: \(dbPath.path)")
        self.dbPath = dbPath
        self.apiClient = DVGUPSAPIClient()
        
        // Make sure the application support folder exists
        try FileManager.default.createDirectory(at: dbPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        self.db = try Self.connect(url: dbPath)
        try initializeSchema()
        try loadCurrentUser()
    }
    
    private static func connect(url: URL) throws -> SQLContext {
        #if os(Android)
        let db = try SQLContext(path: url.path, flags: [.create, .readWrite], configuration: .plus)
        #else
        let db = try SQLContext(path: url.path, flags: [.create, .readWrite])
        #endif
        
        #if DEBUG
        db.trace { logger.info("SQL: \($0)") }
        #endif
        return db
    }
    
    private func initializeSchema() throws {
        logger.info("db.userVersion: \(self.db.userVersion)")
        
        if db.userVersion == 0 {
            for ddl in User.table.createTableSQL() {
                try db.exec(ddl)
            }
            db.userVersion = 1
        }
    }
    
    // MARK: - User Management
    
    private func loadCurrentUser() throws {
        let users = try db.query(User.self).eval().load()
        if let user = users.first {
            self.currentUser = user
            self.isFirstLaunch = user.isFirstTime
            
            // Load user's faculty and group
            if let faculty = faculties.first(where: { $0.id == user.facultyId }) {
                self.selectedFaculty = faculty
            }
            
            if !user.groupId.isEmpty {
                self.selectedGroup = Group(id: user.groupId, name: user.groupName, fullName: user.groupName, facultyId: user.facultyId)
            }
            
            logger.info("✅ Loaded user: \(user.name), faculty: \(user.facultyName), group: \(user.groupName)")
        } else {
            logger.info("ℹ️ No user found, first launch")
            self.isFirstLaunch = true
        }
    }
    
    public func createUser(name: String, facultyId: String, facultyName: String, groupId: String, groupName: String) {
        do {
            let user = User(
                name: name,
                facultyId: facultyId,
                facultyName: facultyName,
                groupId: groupId,
                groupName: groupName,
                isFirstTime: false
            )
            
            // Delete any existing users (single user app)
            try db.delete(User.self)
            
            // Insert new user
            _ = try db.insert(user)
            
            self.currentUser = user
            self.isFirstLaunch = false
            
            // Update selected values
            if let faculty = faculties.first(where: { $0.id == facultyId }) {
                self.selectedFaculty = faculty
            }
            self.selectedGroup = Group(id: groupId, name: groupName, fullName: groupName, facultyId: facultyId)
            
            logger.info("✅ Created user: \(name)")
        } catch {
            logger.error("❌ Error creating user: \(error)")
            self.errorMessage = "Ошибка создания профиля: \(error.localizedDescription)"
        }
    }
    
    public func updateUser(_ user: User) {
        do {
            try db.update(user)
            self.currentUser = user
            logger.info("✅ Updated user: \(user.name)")
        } catch {
            logger.error("❌ Error updating user: \(error)")
            self.errorMessage = "Ошибка обновления профиля: \(error.localizedDescription)"
        }
    }
    
    public func resetUser() {
        do {
            try db.delete(User.self)
            self.currentUser = nil
            self.isFirstLaunch = true
            self.selectedFaculty = nil
            self.selectedGroup = nil
            self.availableGroups = []
            self.currentSchedule = nil
            logger.info("✅ Reset user data")
        } catch {
            logger.error("❌ Error resetting user: \(error)")
            self.errorMessage = "Ошибка сброса данных: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Schedule Management
    
    public func selectFaculty(_ faculty: Faculty) async {
        await MainActor.run {
            self.selectedFaculty = faculty
            self.selectedGroup = nil
            self.availableGroups = []
            self.currentSchedule = nil
        }
        
        // Load groups for selected faculty
        await loadGroups()
    }
    
    public func selectGroup(_ group: Group) {
        self.selectedGroup = group
        
        // Update user's group if user exists
        if var user = currentUser {
            user.updateGroup(groupId: group.id, groupName: group.name)
            updateUser(user)
        }
        
        // Load schedule for selected group
        Task { await loadSchedule() }
    }
    
    public func selectDate(_ date: Date) {
        self.selectedDate = date
        
        // Reload schedule for new date
        if selectedGroup != nil {
            Task { await loadSchedule() }
        }
    }
    
    public func loadGroups() async {
        guard let faculty = selectedFaculty else { return }
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let groups = try await apiClient.fetchGroups(for: faculty.id, date: selectedDate)
            
            await MainActor.run {
                self.availableGroups = groups
                self.isLoading = false
                self.groupsUpdateCounter += 1
                logger.info("✅ Loaded \(groups.count) groups for faculty \(faculty.name)")
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                logger.error("❌ Error loading groups: \(error)")
            }
        }
    }
    
    public func loadSchedule() async {
        guard let group = selectedGroup else { return }
        
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let schedule = try await apiClient.fetchSchedule(for: group.id, startDate: selectedDate)
            
            await MainActor.run {
                self.currentSchedule = schedule
                self.isLoading = false
                self.scheduleUpdateCounter += 1
                let totalLessons = schedule.days.reduce(0) { $0 + $1.lessons.count }
                logger.info("✅ Loaded schedule for group \(group.name): \(schedule.days.count) days, \(totalLessons) lessons total")
                
                // Debug log each day
                for day in schedule.days {
                    logger.info("📅 Day: \(day.weekday), Lessons: \(day.lessons.count)")
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
                logger.error("❌ Error loading schedule: \(error)")
            }
        }
    }
    
    public func refreshSchedule() async {
        if selectedGroup != nil {
            self.currentSchedule = nil // Clear first
            await loadSchedule()
            self.scheduleUpdateCounter += 1 // Force UI update
        }
    }
    
    // MARK: - Date Navigation
    
    public func nextWeek() {
        let nextWeek = selectedDate.addingTimeInterval(7 * 24 * 60 * 60)
        selectDate(nextWeek)
    }
    
    public func previousWeek() {
        let previousWeek = selectedDate.addingTimeInterval(-7 * 24 * 60 * 60)
        selectDate(previousWeek)
    }
    
    public func goToCurrentWeek() {
        selectDate(Date())
    }
    
    public func currentWeekRange() -> String {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        let endOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.end.addingTimeInterval(-1) ?? selectedDate
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        
        return "\(formatter.string(from: startOfWeek)) - \(formatter.string(from: endOfWeek))"
    }
    
    // MARK: - Helper Methods
    
    public func filteredGroups(searchText: String) -> [Group] {
        if searchText.isEmpty {
            return availableGroups
        }
        return availableGroups.filter { group in
            group.name.localizedCaseInsensitiveContains(searchText) ||
            group.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }
}

/// Public constructor for bridging testing
extension ViewModel {
    public static func create(withURL url: URL) throws -> ViewModel {
        try ViewModel(dbPath: url)
    }
}
