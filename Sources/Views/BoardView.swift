import SwiftUI

struct BoardView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    let projectID: UUID

    // Canvas transform
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Interaction state
    @State private var editing: BoardNode?
    @State private var showNew = false
    @State private var newTitle = ""
    @State private var connectingFrom: UUID?      // node id we're drawing a rope from

    private let cardW: CGFloat = 170
    private let cardH: CGFloat = 78

    private var board: Board { store.project(projectID)?.board ?? Board() }

    var body: some View {
        ZStack {
            (settings.bgColor ?? Color(hex: 0x0D0A1F)).ignoresSafeArea()
            dotGrid

            canvasContent
                .scaleEffect(scale)
                .offset(offset)
                .gesture(panGesture.simultaneously(with: zoomGesture))

            controls
        }
        .navigationTitle("Доска")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { resetView() } label: { Image(systemName: "scope") }
            }
        }
        .alert("Новая задача", isPresented: $showNew) {
            TextField("Заголовок", text: $newTitle)
            Button("Создать") {
                let t = newTitle.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty {
                    // place near current view center in canvas coords
                    let cx = (-offset.width / scale) + 140
                    let cy = (-offset.height / scale) + 160
                    store.addNode(projectID: projectID, title: t, x: Double(cx), y: Double(cy))
                }
                newTitle = ""
            }
            Button("Отмена", role: .cancel) { newTitle = "" }
        }
        .sheet(item: $editing) { node in
            NodeEditor(projectID: projectID, node: node)
        }
        .overlay(alignment: .top) { connectingBanner }
    }

    // MARK: - Canvas content (ropes + nodes)

    private var canvasContent: some View {
        ZStack(alignment: .topLeading) {
            // Ropes
            ForEach(board.edges) { edge in
                if let a = node(edge.from), let b = node(edge.to) {
                    RopeShape(from: center(a), to: center(b))
                        .stroke(settings.accentColor.opacity(0.8),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            // Live rope while connecting
            if let fromID = connectingFrom, let a = node(fromID) {
                RopeShape(from: center(a), to: center(a))
                    .stroke(settings.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6]))
            }
            // Nodes
            ForEach(board.nodes) { node in
                nodeView(node)
                    .position(x: CGFloat(node.x) + cardW/2, y: CGFloat(node.y) + cardH/2)
            }
        }
        .frame(width: 4000, height: 4000, alignment: .topLeading)
    }

    private func nodeView(_ node: BoardNode) -> some View {
        let isConnectSource = connectingFrom == node.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: node.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(node.done ? settings.accentColor : .secondary)
                    .onTapGesture { store.toggleNodeDone(node.id, projectID: projectID) }
                Text(node.title).font(.subheadline.bold())
                    .strikethrough(node.done).lineLimit(2)
                Spacer(minLength: 0)
            }
            if !node.detail.isEmpty {
                Text(node.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(width: cardW, height: cardH, alignment: .topLeading)
        .background(settings.cardColor ?? Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isConnectSource ? settings.accentColor : .white.opacity(0.08),
                        lineWidth: isConnectSource ? 2.5 : 1)
        )
        .overlay(alignment: .bottomTrailing) { connectHandle(node) }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .gesture(dragGesture(node))
        .onTapGesture {
            if let from = connectingFrom {
                if from != node.id { store.connectNodes(from, node.id, projectID: projectID) }
                connectingFrom = nil
            } else {
                editing = node
            }
        }
        .contextMenu {
            Button { connectingFrom = node.id } label: { Label("Соединить тросом", systemImage: "link") }
            Button { editing = node } label: { Label("Изменить", systemImage: "pencil") }
            Button(role: .destructive) { store.deleteNode(node.id, projectID: projectID) } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private func connectHandle(_ node: BoardNode) -> some View {
        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(5)
            .background(settings.accentGradient, in: Circle())
            .offset(x: 6, y: 6)
            .onTapGesture {
                if connectingFrom == node.id { connectingFrom = nil } else { connectingFrom = node.id }
            }
    }

    // MARK: - Gestures

    private func dragGesture(_ node: BoardNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let nx = node.x + Double(value.translation.width / scale)
                let ny = node.y + Double(value.translation.height / scale)
                store.moveNode(node.id, to: nx, ny, projectID: projectID)
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = min(max(lastScale * value, 0.3), 3) }
            .onEnded { _ in lastScale = scale }
    }

    // MARK: - Controls overlay

    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    zoomButton("plus.magnifyingglass") { setScale(scale + 0.2) }
                    zoomButton("minus.magnifyingglass") { setScale(scale - 0.2) }
                    Button { showNew = true } label: {
                        Image(systemName: "plus")
                            .font(.title2.bold()).foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(settings.accentGradient, in: Circle())
                            .shadow(color: settings.accentColor.opacity(0.5), radius: 8, y: 3)
                    }
                }
                .padding(20)
            }
        }
    }

    private func zoomButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder private var connectingBanner: some View {
        if connectingFrom != nil {
            HStack(spacing: 8) {
                Image(systemName: "link")
                Text("Выбери карточку, чтобы соединить тросом")
                Button("Отмена") { connectingFrom = nil }.font(.caption.bold())
            }
            .font(.caption).padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var dotGrid: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                let step: CGFloat = 28 * scale
                guard step > 6 else { return }
                let ox = offset.width.truncatingRemainder(dividingBy: step)
                let oy = offset.height.truncatingRemainder(dividingBy: step)
                var x = ox
                while x < size.width { var y = oy
                    while y < size.height {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                 with: .color(.gray.opacity(0.25)))
                        y += step }
                    x += step }
            }
        }
        .ignoresSafeArea()
    }

    private func node(_ id: UUID) -> BoardNode? { board.nodes.first { $0.id == id } }
    private func center(_ n: BoardNode) -> CGPoint { CGPoint(x: CGFloat(n.x) + cardW/2, y: CGFloat(n.y) + cardH/2) }
    private func setScale(_ s: CGFloat) { withAnimation(.easeOut(duration: 0.2)) { scale = min(max(s, 0.3), 3); lastScale = scale } }
    private func resetView() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        }
    }
}

// MARK: - Rope (curved connector)

struct RopeShape: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        // sagging rope: control points pulled downward for a cable look
        let dx = to.x - from.x
        let midSag = max(30, abs(dx) * 0.25)
        let c1 = CGPoint(x: from.x + dx * 0.33, y: max(from.y, to.y) + midSag)
        let c2 = CGPoint(x: from.x + dx * 0.66, y: max(from.y, to.y) + midSag)
        p.addCurve(to: to, control1: c1, control2: c2)
        return p
    }
}

// MARK: - Node editor

struct NodeEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let projectID: UUID
    let node: BoardNode

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
                Section {
                    Button(role: .destructive) {
                        store.deleteNode(node.id, projectID: projectID); dismiss()
                    } label: { Label("Удалить задачу", systemImage: "trash") }
                }
            }
            .navigationTitle("Карточка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        var n = node; n.title = title; n.detail = detail; n.done = done
                        store.updateNode(n, projectID: projectID); dismiss()
                    }.disabled(title.isEmpty)
                }
            }
            .onAppear { title = node.title; detail = node.detail; done = node.done }
        }
    }
}
