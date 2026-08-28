import SwiftUI

struct SessionDraft: Identifiable {
    let id = UUID()
    let sessionID: UUID?
    let start: Date
    let end: Date

    init(day: Date) {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        sessionID = nil
        self.start = start
        end = start.addingTimeInterval(3600)
    }

    init(interval: WorkInterval) {
        sessionID = interval.sessionID
        start = interval.start
        end = interval.end
    }

    var isNew: Bool { sessionID == nil }
}

struct SessionEditor: View {
    let draft: SessionDraft
    let onSave: (Date, Date) -> Void
    let onCancel: () -> Void

    @State private var start: Date
    @State private var end: Date

    init(draft: SessionDraft, onSave: @escaping (Date, Date) -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        _start = State(initialValue: draft.start)
        _end = State(initialValue: draft.end)
    }

    private var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    private var isValid: Bool { SessionEdit.normalise(start: start, end: end) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isNew ? "Add session" : "Edit session")
                .font(.system(size: 14, weight: .semibold))

            Form {
                DatePicker("Start", selection: $start)
                DatePicker("End", selection: $end)
            }
            .formStyle(.grouped)
            .frame(height: 90)

            Text(isValid ? formatMinutes(minutes) : "The end must come after the start.")
                .font(.system(size: 11))
                .foregroundStyle(isValid ? .secondary : Color.red)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") { onSave(start, end) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
