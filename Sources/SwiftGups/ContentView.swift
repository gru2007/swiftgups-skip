// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI

enum ContentTab: String, Hashable {
    case schedule, profile
}

struct ContentView: View {
    @State var viewModel = ViewModel.shared
    @AppStorage("appearance") var appearance = ""

    var body: some View {
        VStack {
            if viewModel.isFirstLaunch {
                WelcomeView()
                    .environment(viewModel)
            } else {
                MainAppView()
                    .environment(viewModel)
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State internal var userName = ""
    @State internal var selectedFaculty: Faculty? = nil
    @State internal var selectedGroup: Group? = nil
    @State internal var searchText = ""
    @State internal var showGroupSelection = false
    @State internal var refreshTrigger = false

    var body: some View {
            NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Text("🎓")
                            .font(.system(size: 80))
                        
                        Text("SwiftGups Lite (Beta)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Добро пожаловать в приложение для просмотра расписания ДВГУПС")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Registration Form
                    VStack(spacing: 20) {
                        // Name input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ваше имя")
                                .font(.headline)
                            
                            TextField("Введите ваше имя", text: $userName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)
                        }
                        
                        // Faculty selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Институт/Факультет")
                                .font(.headline)
                            
                            Menu {
                                ForEach(viewModel.faculties) { faculty in
                                    Button(action: {
                                        selectedFaculty = faculty
                                        selectedGroup = nil
                                        showGroupSelection = true
                                        Task {
                                            await viewModel.selectFaculty(faculty)
                                            // Wait a bit for groups to load, then trigger refresh
                                            try? await Task.sleep(for: .milliseconds(100))
                                            await MainActor.run {
                                                refreshTrigger.toggle()
                                            }
                                        }
                                    }) {
                                        HStack {
                                            Text(faculty.name)
                                            if selectedFaculty?.id == faculty.id {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedFaculty?.name ?? "Выберите институт/факультет")
                                        .foregroundColor(selectedFaculty != nil ? .primary : .secondary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.1))
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            }
                        }
                        
                        // Group selection
                        if showGroupSelection && selectedFaculty != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Группа")
                                        .font(.headline)
                                    Spacer()
                                    Text("(\(viewModel.availableGroups.count))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if viewModel.isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView("Загрузка групп...")
                                        Spacer()
                                    }
                                    .padding()
                                } else if !viewModel.availableGroups.isEmpty || viewModel.availableGroups.count > 0 {
                                    VStack(spacing: 8) {
                                        // Search field
                                        TextField("Поиск группы...", text: $searchText)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .padding(.horizontal)
                                        
                                        // Groups list
                                        ScrollView {
                                            VStack(spacing: 8) {
                                                ForEach(viewModel.filteredGroups(searchText: searchText)) { group in
                                                    Button(action: {
                                                        selectedGroup = group
                                                    }) {
                                                        HStack {
                                                            VStack(alignment: .leading, spacing: 4) {
                                                                Text(group.name)
                                                                    .font(.headline)
                                                                    .fontWeight(.semibold)
                                                                    .foregroundColor(selectedGroup?.id == group.id ? .white : .primary)
                                                                
                                                                Text(group.fullName)
                                                                    .font(.caption)
                                                                    .foregroundColor(selectedGroup?.id == group.id ? .white.opacity(0.8) : .secondary)
                                                                    .lineLimit(2)
                                                            }
                                                            
                                                            Spacer()
                                                            
                                                            if selectedGroup?.id == group.id {
                                                                Image(systemName: "checkmark")
                                                                    .foregroundColor(.white)
                                                                    .fontWeight(.bold)
                                                            }
                                                        }
                                                        .padding()
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .fill(selectedGroup?.id == group.id ? Color.blue : Color.gray.opacity(0.1))
                                                        )
                                                        .padding(.horizontal)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 300)
                                        .id("\(refreshTrigger)-\(viewModel.groupsUpdateCounter)") // Force refresh
                                    }
                                    .onChange(of: viewModel.availableGroups.count) { oldCount, newCount in
                                        if newCount > 0 {
                                            refreshTrigger.toggle()
                                        }
                                    }
                                } else {
                                    Text("Группы не найдены")
                                        .foregroundColor(.secondary)
                                        .padding()
                                }
                            }
                        }
                        
                        // Error message
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                        }
                        
                        // Continue button
                        Button(action: {
                            if let faculty = selectedFaculty,
                               let group = selectedGroup,
                               !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.createUser(
                                    name: userName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    facultyId: faculty.id,
                                    facultyName: faculty.name,
                                    groupId: group.id,
                                    groupName: group.name
                                )
                            }
                        }) {
                            Text("Продолжить")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isFormValid ? Color.blue : Color.gray)
                                )
                                .padding(.horizontal)
                        }
                        .disabled(!isFormValid)
                        
                        Spacer(minLength: 40)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarHidden(true)
        }
    }
    
    internal var isFormValid: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedFaculty != nil &&
        selectedGroup != nil
    }
}

// MARK: - Main App View

struct MainAppView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @AppStorage("selectedTab") var selectedTab = ContentTab.schedule

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ScheduleView()
            }
            .tabItem { Label("Расписание", systemImage: "calendar") }
            .tag(ContentTab.schedule)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Профиль", systemImage: "person") }
            .tag(ContentTab.profile)
        }
    }
}

// MARK: - Schedule View

struct ScheduleView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @State internal var showDatePicker = false
    @State internal var selectedLesson: Lesson? = nil
    @State internal var scheduleRefreshTrigger = false
    @State internal var forceUIUpdate = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date navigation
                VStack(alignment: .leading, spacing: 12) {
                    Text("Неделя")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            viewModel.previousWeek()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 4) {
                            Text(viewModel.currentWeekRange())
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Button("Текущая неделя") {
                                viewModel.goToCurrentWeek()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.nextWeek()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                    )
                    
                    Button(action: {
                        showDatePicker = true
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text("Выбрать дату")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                )
                
                // Schedule content
                VStack {
                    if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Загрузка расписания...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(40)
                    } else if let schedule = viewModel.currentSchedule, !schedule.days.isEmpty {
                        ScheduleContentView(schedule: schedule, selectedLesson: $selectedLesson)
                            .id("schedule-\(schedule.groupId)-\(scheduleRefreshTrigger)-\(viewModel.scheduleUpdateCounter)-\(schedule.days.count)-\(forceUIUpdate)")
                    } else if viewModel.currentSchedule != nil {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("Расписание пустое")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("На выбранную неделю нет занятий")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                        )
                    } else if viewModel.selectedGroup != nil {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("Расписание не найдено")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("На выбранную дату расписание отсутствует")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
                .onChange(of: viewModel.scheduleUpdateCounter) { oldValue, newValue in
                    if newValue > oldValue {
                        scheduleRefreshTrigger.toggle()
                        forceUIUpdate += 1
                    }
                }
                .onChange(of: viewModel.currentSchedule) { oldSchedule, newSchedule in
                    if newSchedule != nil {
                        scheduleRefreshTrigger.toggle()
                        forceUIUpdate += 1
                    }
                }
                
                // Error message
                if let errorMessage = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Расписание")
        .refreshable {
            await viewModel.refreshSchedule()
            await MainActor.run {
                forceUIUpdate += 1
                scheduleRefreshTrigger.toggle()
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet()
        }
        .sheet(item: $selectedLesson) { lesson in
            LessonDetailSheet(lesson: lesson)
        }
        .task {
            if viewModel.selectedGroup != nil && viewModel.currentSchedule == nil {
                await viewModel.loadSchedule()
            }
        }
        .onAppear {
            if viewModel.currentSchedule != nil {
                forceUIUpdate += 1
                scheduleRefreshTrigger.toggle()
            }
        }
    }
}

// MARK: - Schedule Content View

struct ScheduleContentView: View {
    let schedule: Schedule
    @Binding var selectedLesson: Lesson?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Расписание")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(schedule.groupName)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text("Период: \(Date.displayDateFormatter.string(from: schedule.startDate)) - \(Date.displayDateFormatter.string(from: schedule.endDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Days
            if schedule.days.isEmpty {
                Text("Нет занятий на этой неделе")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Дней в расписании: \(schedule.days.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                
                VStack(spacing: 16) {
                    ForEach(schedule.days) { day in
                        ScheduleDayView(day: day, selectedLesson: $selectedLesson)
                            .id("day-\(day.weekday)-\(day.lessons.count)")
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Schedule Day View

struct ScheduleDayView: View {
    let day: ScheduleDay
    @Binding var selectedLesson: Lesson?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(day.weekday)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(day.lessons.count) пар")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Text(Date.apiDateFormatter.string(from: day.date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let weekNumber = day.weekNumber {
                    Text("\(weekNumber)-я неделя")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((day.isEvenWeek ?? false) ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        )
                        .foregroundColor((day.isEvenWeek ?? false) ? .green : .orange)
                }
            }
            
            // Lessons
            if day.lessons.isEmpty {
                Text("Нет занятий")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Text("Пар: \(day.lessons.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(day.lessons.enumerated()), id: \.offset) { index, lesson in
                        LessonView(lesson: lesson)
                            .id("lesson-\(day.weekday)-\(index)-\(lesson.pairNumber)-\(lesson.subject)")
                            .onTapGesture {
                                selectedLesson = lesson
                            }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

// MARK: - Lesson View

struct LessonView: View {
    let lesson: Lesson
    
    internal var lessonTypeColor: Color {
        switch lesson.type {
        case .lecture: return .blue
        case .practice: return .green
        case .laboratory: return .orange
        case .unknown: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Lesson number and time
            VStack(alignment: .leading, spacing: 2) {
                Text("\(lesson.pairNumber) пара")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(lessonTypeColor)
                
                Text("\(lesson.timeStart)-\(lesson.timeEnd)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 60, alignment: .leading)
            
            // Lesson info
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(lesson.type.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(lessonTypeColor.opacity(0.2))
                    )
                    .foregroundColor(lessonTypeColor)
                
                if let teacher = lesson.teacher {
                    Text(teacher.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let room = lesson.room {
                    Text("📍 \(room)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let onlineLink = lesson.onlineLink {
                    Text("💻 \(onlineLink)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @Environment(ViewModel.self) var viewModel: ViewModel

    var body: some View {
        List {
            if let user = viewModel.currentUser {
                Section {
                    HStack {
                        Text("Имя")
                        Spacer()
                        Text(user.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Институт")
                        Spacer()
                        Text(user.facultyName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Группа")
                        Spacer()
                        Text(user.groupName)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Профиль")
                }
                
                Section {
                    Button("Сбросить данные") {
                        viewModel.resetUser()
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("Действия")
                }
            }
            
            Section {
                HStack {
                    Text("Powered by")
                    Link("Skip", destination: URL(string: "https://skip.tools")!)
                        .foregroundColor(.blue)
                    Text("and")
                    Link("Swift", destination: URL(string: "https://swift.org")!)
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Профиль")
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Environment(ViewModel.self) var viewModel: ViewModel
    @Environment(\.dismiss) internal var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Выберите дату")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                DatePicker(
                    "Дата",
                    selection: Binding(
                        get: { viewModel.selectedDate },
                        set: { viewModel.selectDate($0) }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .padding()
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }

    }
}

// MARK: - Lesson Detail Sheet

struct LessonDetailSheet: View {
    let lesson: Lesson
    @Environment(\.dismiss) internal var dismiss
    
    internal var lessonTypeColor: Color {
        switch lesson.type {
        case .lecture: return .blue
        case .practice: return .green
        case .laboratory: return .orange
        case .unknown: return .gray
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Заголовок
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.subject)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
            HStack {
                            Text(lesson.type.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(lessonTypeColor)
                            
                            Spacer()
                            
                            Text("\(lesson.pairNumber) пара")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(lessonTypeColor.opacity(0.1))
                    )
                    
                    // Основная информация
                    VStack(alignment: .leading, spacing: 16) {
                        // Время
                        InfoRow(
                            icon: "clock",
                            title: "Время",
                            value: "\(lesson.timeStart) - \(lesson.timeEnd)",
                            color: .blue
                        )
                        
                        // Аудитория
                        if let room = lesson.room, !room.isEmpty {
                            InfoRow(
                                icon: "location",
                                title: "Аудитория", 
                                value: room,
                                color: .green
                            )
                        }
                        
                        // Преподаватель
                        if let teacher = lesson.teacher {
                            InfoRow(
                                icon: "person",
                                title: "Преподаватель",
                                value: teacher.name,
                                color: .purple
                            )
                            
                            if let email = teacher.email {
                                InfoRow(
                                    icon: "envelope",
                                    title: "Email",
                                    value: email,
                                    color: .orange,
                                    isEmail: true
                                )
                            }
                        }
                        
                        // Онлайн-ссылка
                        if let onlineLink = lesson.onlineLink, !onlineLink.isEmpty {
                            InfoRow(
                                icon: "video",
                                title: "Дистанционно",
                                value: onlineLink,
                                color: .red,
                                isLink: true
                            )
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    )
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Детали пары")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    var isEmail: Bool = false
    var isLink: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
                .font(.system(size: 16, weight: .medium))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isEmail {
                    Button(action: {
                        if let emailURL = URL(string: "mailto:\(value)") {
                            #if os(iOS)
                            UIApplication.shared.open(emailURL)
                            #endif
                        }
                    }) {
                        Text(value)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .underline()
                    }
                } else if isLink {
                    Button(action: {
                        if let url = URL(string: value) {
                            #if os(iOS)
                            UIApplication.shared.open(url)
        #endif
                        }
                    }) {
                        Text(value)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .underline()
                            .lineLimit(2)
                    }
                } else {
                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(isLink ? 2 : 1)
                }
            }
            
            Spacer()
        }
    }
}
