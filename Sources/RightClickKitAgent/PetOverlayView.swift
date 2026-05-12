import AppKit
import RightClickKitCore
import SwiftUI

private enum PetState: String, CaseIterable {
    case idle
    case running
    case waiting
    case review
    case failed
    case waving
    case jumping
    case runningLeft
    case runningRight
}

private extension PetState {
    init(activityState: ActivityMascotState) {
        switch activityState {
        case .idle:
            self = .idle
        case .running:
            self = .running
        case .waiting:
            self = .waiting
        case .review:
            self = .review
        case .failed:
            self = .failed
        }
    }
}

private struct SpriteFrame: Hashable {
    let row: Int
    let column: Int
    let duration: TimeInterval
}

private struct SpritePlayback {
    let frames: [SpriteFrame]
    let loopStartIndex: Int
}

private enum SpriteMetrics {
    static let cellWidth = 192
    static let cellHeight = 208
    static let aspectRatio = CGFloat(cellWidth) / CGFloat(cellHeight)
}

enum PetOverlayScale: String, CaseIterable {
    case tiny
    case small
    case original

    var title: String {
        switch self {
        case .tiny: "Tiny"
        case .small: "Small"
        case .original: "Original"
        }
    }

    var spriteWidth: CGFloat {
        switch self {
        case .tiny: 68
        case .small: 82
        case .original: 112.64
        }
    }

    var windowSize: CGSize {
        let spriteHeight = spriteWidth / SpriteMetrics.aspectRatio
        return CGSize(width: spriteWidth + 20, height: spriteHeight + 28)
    }
}

enum PetOverlayPreferences {
    private static let scaleKey = "RightClickKitAgent.petScale"

    static var scale: PetOverlayScale {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: scaleKey),
                  let scale = PetOverlayScale(rawValue: rawValue)
            else {
                return .small
            }
            return scale
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: scaleKey)
        }
    }
}

struct PetOverlayView: View {
    @State private var state: PetState = .idle
    @State private var activitySummary = ActivitySummary.empty
    @State private var scale = PetOverlayPreferences.scale
    @State private var dragStartDate: Date?
    @State private var hasDragged = false
    @State private var isPointerHovering = false
    @State private var isDragging = false
    @State private var activityPollTask: Task<Void, Never>?

    let onScaleChanged: (PetOverlayScale) -> Void
    let onHide: () -> Void
    let onShowActivity: () -> Void
    let onDragBegan: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    static func windowSize(for scale: PetOverlayScale) -> NSSize {
        let size = scale.windowSize
        return NSSize(width: size.width, height: size.height)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CodexSprite(state: state)
                .frame(width: scale.spriteWidth)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.16)) {
                        state = state == .waving ? .idle : .waving
                    }
                }
                .onHover { isHovered in
                    isPointerHovering = isHovered
                    guard !isDragging else { return }
                    if isHovered {
                        state = .jumping
                    } else if state == .jumping {
                        applyActivityState()
                    }
                }

            if activitySummary.badgeCount > 0 {
                Button(action: onShowActivity) {
                    badgeLabel
                }
                .buttonStyle(.plain)
                .help("Show RightClickKit activity")
                .offset(x: 3, y: 0)
            }
        }
        .frame(width: scale.windowSize.width, height: scale.windowSize.height)
        .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 4)
        .contextMenu {
            Button {
                AgentActions.openMainApp()
            } label: {
                Label("Configure Actions...", systemImage: "slider.horizontal.3")
            }
            Button {
                AgentActions.openLogs()
            } label: {
                Label("Open Logs", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                AgentActions.openFullDiskAccessSettings()
            } label: {
                Label("Full Disk Access...", systemImage: "lock.shield")
            }
            Button {
                AgentActions.openAccessibilitySettings()
            } label: {
                Label("Accessibility Access...", systemImage: "figure.stand")
            }
            Button {
                AgentActions.openNotificationSettings()
            } label: {
                Label("Notification Settings...", systemImage: "bell.badge")
            }
            Button {
                AgentActions.revealAgentForFullDiskAccess()
            } label: {
                Label("Reveal Agent for Access", systemImage: "app.badge")
            }
            Divider()
            Picker("Sprite Size", selection: $scale) {
                ForEach(PetOverlayScale.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            Divider()
            Button {
                onHide()
            } label: {
                Label("Hide Sprite", systemImage: "flame.slash")
            }
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit RightClickKit Agent", systemImage: "xmark.circle")
            }
        }
        .onAppear {
            refreshActivity()
            startActivityPolling()
        }
        .onDisappear {
            activityPollTask?.cancel()
            activityPollTask = nil
        }
        .onChange(of: scale) { _, newValue in
            PetOverlayPreferences.scale = newValue
            onScaleChanged(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: AgentActions.activityChangedNotification)) { _ in
            refreshActivity()
        }
    }

    private var badgeSize: CGFloat {
        max(20, scale.spriteWidth * 0.25)
    }

    private var badgeFontSize: CGFloat {
        max(10, badgeSize * 0.42)
    }

    private var badgeText: String {
        activitySummary.badgeCount > 99 ? "99+" : "\(activitySummary.badgeCount)"
    }

    private var badgeColor: Color {
        if activitySummary.runningCount > 0 {
            return Color(red: 0.12, green: 0.48, blue: 0.95)
        }
        if activitySummary.failedCount > 0 {
            return Color(red: 0.86, green: 0.18, blue: 0.14)
        }
        if activitySummary.waitingCount > 0 {
            return Color(red: 0.90, green: 0.55, blue: 0.12)
        }
        return Color(red: 0.95, green: 0.48, blue: 0.08)
    }

    private var badgeLabel: some View {
        Text(badgeText)
            .font(.system(size: badgeFontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(minWidth: badgeSize, minHeight: badgeSize)
            .foregroundStyle(.white)
            .background(badgeColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    private func startActivityPolling() {
        activityPollTask?.cancel()
        activityPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    refreshActivity()
                }
            }
        }
    }

    private func refreshActivity() {
        activitySummary = AgentActions.activitySummary()
        applyActivityState()
    }

    private func applyActivityState() {
        guard !isDragging else {
            return
        }

        if isPointerHovering, activitySummary.mascotState == .idle {
            state = .jumping
            return
        }

        state = PetState(activityState: activitySummary.mascotState)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragStartDate == nil {
                    dragStartDate = Date()
                    hasDragged = false
                    isDragging = true
                    onDragBegan()
                }

                let deltaX = value.translation.width
                let deltaY = value.translation.height
                if abs(deltaX) >= 4 || abs(deltaY) >= 4 {
                    hasDragged = true
                    if deltaX >= 4 {
                        state = .runningRight
                    } else if deltaX <= -4 {
                        state = .runningLeft
                    } else {
                        state = .running
                    }
                    onDragChanged()
                }
            }
            .onEnded { value in
                if hasDragged {
                    onDragEnded()
                    isDragging = false
                    applyActivityState()
                } else {
                    isDragging = false
                    state = .waving
                }
                dragStartDate = nil
                hasDragged = false
            }
    }
}

private struct CodexSprite: View {
    let state: PetState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameIndex = 0
    @State private var playbackToken = UUID()

    var body: some View {
        Group {
            if let frameImage {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .accessibilityLabel("Fireball pet")
            } else {
                MissingSpriteView()
                    .accessibilityLabel("Missing pet sprite")
            }
        }
        .aspectRatio(SpriteMetrics.aspectRatio, contentMode: .fit)
        .onAppear {
            restartPlayback()
        }
        .onChange(of: state) {
            restartPlayback()
        }
        .onChange(of: reduceMotion) {
            restartPlayback()
        }
    }

    private var playback: SpritePlayback {
        Self.playback(for: state, reduceMotion: reduceMotion)
    }

    private var currentFrame: SpriteFrame {
        playback.frames[min(frameIndex, playback.frames.count - 1)]
    }

    private var frameImage: NSImage? {
        SpriteAtlas.shared.image(for: currentFrame)
    }

    private func restartPlayback() {
        frameIndex = 0
        let token = UUID()
        playbackToken = token
        scheduleNextFrame(token: token)
    }

    private func scheduleNextFrame(token: UUID) {
        guard playback.frames.count > 1 else { return }

        let frame = currentFrame
        DispatchQueue.main.asyncAfter(deadline: .now() + frame.duration) {
            guard playbackToken == token else { return }

            var nextIndex = frameIndex + 1
            if nextIndex >= playback.frames.count {
                nextIndex = playback.loopStartIndex
            }

            frameIndex = nextIndex
            scheduleNextFrame(token: token)
        }
    }

    private static func playback(for state: PetState, reduceMotion: Bool) -> SpritePlayback {
        let stateFrames = frames(for: state)
        guard !reduceMotion else {
            return SpritePlayback(frames: [stateFrames[0]], loopStartIndex: 0)
        }

        if state == .idle {
            return SpritePlayback(frames: idleLoopFrames, loopStartIndex: 0)
        }

        let reactionFrames = stateFrames + stateFrames + stateFrames
        return SpritePlayback(
            frames: reactionFrames + idleLoopFrames,
            loopStartIndex: reactionFrames.count
        )
    }

    private static func frames(for state: PetState) -> [SpriteFrame] {
        switch state {
        case .idle:
            return idleFrames
        case .running:
            return rowFrames(row: 7, count: 6, frameDuration: 0.120, finalDuration: 0.220)
        case .waiting:
            return rowFrames(row: 6, count: 6, frameDuration: 0.150, finalDuration: 0.260)
        case .review:
            return rowFrames(row: 8, count: 6, frameDuration: 0.150, finalDuration: 0.280)
        case .failed:
            return rowFrames(row: 5, count: 8, frameDuration: 0.140, finalDuration: 0.240)
        case .waving:
            return rowFrames(row: 3, count: 4, frameDuration: 0.140, finalDuration: 0.280)
        case .jumping:
            return rowFrames(row: 4, count: 5, frameDuration: 0.140, finalDuration: 0.280)
        case .runningLeft:
            return rowFrames(row: 2, count: 8, frameDuration: 0.120, finalDuration: 0.220)
        case .runningRight:
            return rowFrames(row: 1, count: 8, frameDuration: 0.120, finalDuration: 0.220)
        }
    }

    private static var idleFrames: [SpriteFrame] {
        [
            SpriteFrame(row: 0, column: 0, duration: 0.280),
            SpriteFrame(row: 0, column: 1, duration: 0.110),
            SpriteFrame(row: 0, column: 2, duration: 0.110),
            SpriteFrame(row: 0, column: 3, duration: 0.140),
            SpriteFrame(row: 0, column: 4, duration: 0.140),
            SpriteFrame(row: 0, column: 5, duration: 0.320)
        ]
    }

    private static var idleLoopFrames: [SpriteFrame] {
        idleFrames.map {
            SpriteFrame(row: $0.row, column: $0.column, duration: $0.duration * 6)
        }
    }

    private static func rowFrames(
        row: Int,
        count: Int,
        frameDuration: TimeInterval,
        finalDuration: TimeInterval
    ) -> [SpriteFrame] {
        (0..<count).map { column in
            SpriteFrame(
                row: row,
                column: column,
                duration: column == count - 1 ? finalDuration : frameDuration
            )
        }
    }
}

@MainActor
private final class SpriteAtlas {
    static let shared = SpriteAtlas()

    private let atlas: CGImage?
    private var cache: [SpriteFrame: NSImage] = [:]

    private init() {
        atlas = Self.loadAtlas()
    }

    func image(for frame: SpriteFrame) -> NSImage? {
        if let cached = cache[frame] {
            return cached
        }

        guard let atlas,
              let crop = atlas.cropping(to: CGRect(
                x: frame.column * SpriteMetrics.cellWidth,
                y: frame.row * SpriteMetrics.cellHeight,
                width: SpriteMetrics.cellWidth,
                height: SpriteMetrics.cellHeight
              ))
        else {
            return nil
        }

        let image = NSImage(cgImage: crop, size: NSSize(width: SpriteMetrics.cellWidth, height: SpriteMetrics.cellHeight))
        cache[frame] = image
        return image
    }

    private static func loadAtlas() -> CGImage? {
        for url in atlasCandidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return cgImage
            }
        }
        return nil
    }

    private static var atlasCandidates: [URL] {
        [
            Bundle.main.url(forResource: "fireball-spritesheet-v4-BtU8R9Qp", withExtension: "webp"),
            Bundle.main.resourceURL?.appendingPathComponent("fireball-spritesheet-v4-BtU8R9Qp.webp"),
            AgentPaths.mainAppURL.appendingPathComponent("Contents/Resources/fireball-spritesheet-v4-BtU8R9Qp.webp")
        ].compactMap { $0 }
    }
}

private struct MissingSpriteView: View {
    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 56, weight: .bold))
            .foregroundStyle(.orange)
    }
}
