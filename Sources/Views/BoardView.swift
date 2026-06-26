import SwiftUI

struct BoardView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID

    @State private var showNewColumn = false
    @State private var newColumnTitle = ""
    @State private var editingCard: EditingCard?

    private var board: Board { store.project(projectID)?.board ?? Board() }

    var body: some View {
        ZStack {
            if let bg = settings.bgColor { bg.ignoresSafeArea() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(board.columns) { column in
                        columnView(column)
                    }
                    addColumnButton
                }
                .padding(16)
            }
        }
        .navigationTitle("Доска")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Новая колонка", isPresented: $showNewColumn) {
            TextField("Название", text: $newColumnTitle)
            Button("Создать") {
                let t = newColumnTitle.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { store.addColumn(projectID: projectID, title: t) }
                newColumnTitle = ""
            }
            Button("Отмена", role: .cancel) { newColumnTitle = "" }
        }
        .sheet(item: $editingCard) { ec in
            CardEditor(projectID: projectID, columnID: ec.columnID, card: ec.card)
        }
    }

    private func columnView(_ column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(column.title).font(.headline)
                Spacer()
                Text("\(column.cards.count)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                Menu {
                    Button { editingCard = EditingCard(columnID: column.id, card: nil) } label: {
                        Label("Добавить карточку", systemImage: "plus")
                    }
                    Button(role: .destructive) { store.deleteColumn(column.id, projectID: projectID) } label: {
                        Label("Удалить колонку", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
            }

            ForEach(column.cards) { card in
                cardView(card, columnID: column.id)
            }

            Button { editingCard = EditingCard(columnID: column.id, card: nil) } label: {
                Label("Карточка", systemImage: "plus")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .top)
        .background(settings.cardColor ?? Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func cardView(_ card: BoardCard, columnID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: card.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(card.done ? settings.accentColor : .secondary)
                    .onTapGesture {
                        var c = card; c.done.toggle()
                        store.updateCard(c, columnID: columnID, projectID: projectID)
                    }
                Text(card.title)
                    .font(.subheadline)
                    .strikethrough(card.done)
                    .foregroundStyle(card.done ? .secondary : .primary)
                Spacer()
            }
            if !card.detail.isEmpty {
                Text(card.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settings.bgColor ?? Color(.tertiarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06)))
        .onTapGesture { editingCard = EditingCard(columnID: columnID, card: card) }
        .contextMenu {
            // Move to another column
            ForEach(board.columns.filter { $0.id != columnID }) { target in
                Button { store.moveCard(card.id, toColumn: target.id, projectID: projectID) } label: {
                    Label("В «\(target.title)»", systemImage: "arrow.right")
                }
            }
            Button(role: .destructive) { store.deleteCard(card.id, columnID: columnID, projectID: projectID) } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private var addColumnButton: some View {
        Button { showNewColumn = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.title2)
                Text("Колонка").font(.caption)
            }
            .foregroundStyle(settings.accentColor)
            .frame(width: 120, height: 90)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct EditingCard: Identifiable {
    let id = UUID()
    let columnID: UUID
    let card: BoardCard?
}

struct CardEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    let columnID: UUID
    let card: BoardCard?

    @State private var title = ""
    @State private var detail = ""
    @State private var done = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Задача") {
                    TextField("Заголовок", text: $title)
                    TextField("Описание (шаги, детали)", text: $detail, axis: .vertical).lineLimit(3...10)
                    Toggle("Выполнено", isOn: $done)
                }
            }
            .navigationTitle(card == nil ? "Новая карточка" : "Карточка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(title.isEmpty)
                }
            }
            .onAppear {
                if let c = card { title = c.title; detail = c.detail; done = c.done }
            }
        }
    }

    private func save() {
        if var c = card {
            c.title = title; c.detail = detail; c.done = done
            store.updateCard(c, columnID: columnID, projectID: projectID)
        } else {
            store.addCard(projectID: projectID, columnID: columnID, title: title, detail: detail)
        }
        dismiss()
    }
}
