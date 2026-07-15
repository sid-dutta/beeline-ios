import SwiftUI
import BeelineCore

/// The user's own schedule: what's next, and the week laid out by day.
struct ClassesScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: Tab
    @State private var showingAdd = false

    private var today: Weekday { Weekday.from(date: Date()) }

    var body: some View {
        Group {
            if model.isEnrolledEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle("Classes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add class", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddClassSheet()
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No classes yet", systemImage: "calendar.badge.plus")
        } description: {
            Text("Add your sections and Beeline will show what's next and walk you there.")
        } actions: {
            Button("Add a class") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        List {
            if let next = model.nextClass() {
                Section {
                    NextClassCard(next: next) {
                        model.route(to: .room(buildingID: next.event.buildingID, room: next.event.room))
                        tab = .map
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(daysWithClasses, id: \.self) { day in
                Section {
                    ForEach(model.schedule.events(on: day)) { event in
                        Button {
                            model.route(to: .room(buildingID: event.buildingID, room: event.room))
                            tab = .map
                        } label: {
                            ClassRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(day.shortName.uppercased())
                        if day == today {
                            Text("TODAY")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.beelineNavy)
                        }
                    }
                }
            }

            Section {
                ForEach(model.enrolled) { section in
                    HStack {
                        Text(section.course)
                        Text("Section \(section.section)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            model.unenroll(section)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Enrolled sections")
            } footer: {
                Text("From the \(termLabel) schedule of classes.")
            }
        }
        .groupedList()
    }

    private var daysWithClasses: [Weekday] {
        // Start at today so the current day is at the top of the list.
        let ordered = (0..<7).compactMap { Weekday(rawValue: (today.rawValue - 1 + $0) % 7 + 1) }
        return ordered.filter { !model.schedule.events(on: $0).isEmpty }
    }

    private var termLabel: String {
        let term = model.pack.term
        guard term.count == 6, let year = Int(term.prefix(4)) else { return term }
        let season = switch term.suffix(2) {
        case "02": "Spring"
        case "05": "Summer"
        default: "Fall"
        }
        return "\(season) \(year)"
    }
}

struct ClassRow: View {
    @Environment(AppModel.self) private var model
    let event: ClassEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(Weekday.clock(event.start).replacingOccurrences(of: " ", with: "\u{00a0}"))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                Text(Weekday.clock(event.end))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 70, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.beelineGold)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.meeting.course)
                    .font(.body.weight(.medium))
                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.locate(room: event.room, in: event.buildingID).summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Search a course, pick a section.
struct AddClassSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if courses.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(courses, id: \.course) { entry in
                    Section(entry.course) {
                        Text(entry.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.sections(forCourse: entry.course), id: \.section) { s in
                            Button {
                                model.enroll(course: entry.course, section: s.section)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Section \(s.section)")
                                            .foregroundStyle(.primary)
                                        Text("\(s.meeting.days) · \(Weekday.clock(s.meeting.start)) · \(model.building(s.buildingID)?.shortName ?? "") \(s.room)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.enrolled.contains(EnrolledSection(course: entry.course, section: s.section)) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.beelineNavy)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .groupedList()
            .searchable(text: $query, prompt: "Course, e.g. CS 1332")
            .navigationTitle("Add Class")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var courses: [(course: String, title: String)] {
        guard !query.isEmpty else { return [] }
        return model.index.search(query, limit: 12).compactMap { result in
            if case .course(let id, let title, _) = result { return (id, title) }
            return nil
        }
    }
}

struct ClassesScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { ClassesScreen(tab: .constant(.classes)) }
            .environment(AppModel.preview())
    }
}
