import AppKit
import SwiftUI

/// State shown on the island.
@MainActor
final class IslandModel: ObservableObject {
    @Published var workspace = 1
    @Published var nowPlaying: MediaController.NowPlaying?
    @Published var expanded = false
    /// Width of the physical notch to leave hollow in the collapsed strip;
    /// zero means no notch — render as a compact pill instead.
    @Published var notchGap: CGFloat = 0

    /// Collapsed wing widths: the right wing grows to carry the track title
    /// when media is loaded, Dynamic-Island-style.
    var leftWingWidth: CGFloat { 44 }
    var rightWingWidth: CGFloat { nowPlaying == nil ? 44 : 172 }

    var onHoverChanged: ((Bool) -> Void)?
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
}

/// A Dynamic-Island-style black panel hugging the notch (or a top-center
/// pill on notchless screens): workspace number on the left wing, playback
/// glyph on the right, expanding on hover into track info and controls.
@MainActor
final class NotchIsland {

    let model = IslandModel()
    private var panel: NSPanel?
    private var collapseWork: DispatchWorkItem?

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Physical notch width, or nil on displays without one.
    private var notchWidth: CGFloat? {
        guard let screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        return right.minX - left.maxX
    }

    private var collapsedFrame: NSRect {
        guard let screen else { return .zero }
        if let notchWidth {
            // Wings hug the housing at exact notch height. The hollow must
            // stay centered on the physical notch, so the panel's origin
            // shifts when the wings are asymmetric.
            let height = screen.safeAreaInsets.top
            let width = model.leftWingWidth + notchWidth + model.rightWingWidth
            return NSRect(x: screen.frame.midX - model.leftWingWidth - notchWidth / 2,
                          y: screen.frame.maxY - height,
                          width: width, height: height)
        }
        // No notch: a compact pill overlapping the menu bar's center.
        let width: CGFloat = model.nowPlaying == nil ? 96 : 224
        return NSRect(x: screen.frame.midX - width / 2,
                      y: screen.frame.maxY - 24,
                      width: width, height: 24)
    }

    /// Re-fit the collapsed strip when its content changes (track appears
    /// or goes away) — no-op while expanded.
    func noteContentChanged() {
        guard panel != nil, !model.expanded else { return }
        animate(to: collapsedFrame)
    }

    private var expandedFrame: NSRect {
        guard let screen else { return .zero }
        let size = NSSize(width: 360, height: 140)
        return NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { show() } else { hide() }
    }

    private func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: collapsedFrame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: IslandView(model: model))
            self.panel = panel
        }
        model.onHoverChanged = { [weak self] hovering in
            self?.hoverChanged(hovering)
        }
        model.notchGap = notchWidth ?? 0
        panel?.setFrame(collapsedFrame, display: true)
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        model.expanded = false
    }

    private func hoverChanged(_ hovering: Bool) {
        collapseWork?.cancel()
        if hovering {
            guard !model.expanded else { return }
            model.expanded = true
            animate(to: expandedFrame)
        } else {
            // Grace period so moving between elements doesn't collapse it.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.model.expanded = false
                self.animate(to: self.collapsedFrame)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func animate(to frame: NSRect) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
}

// MARK: - Views

private struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        Group {
            if model.expanded {
                expanded
            } else {
                collapsed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(bottomLeading: model.expanded ? 20 : 12,
                               bottomTrailing: model.expanded ? 20 : 12)))
        .onHover { model.onHoverChanged?($0) }
        .animation(.easeOut(duration: 0.18), value: model.expanded)
    }

    private var collapsed: some View {
        HStack(spacing: 0) {
            Text("\(model.workspace)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: model.notchGap > 0 ? model.leftWingWidth : nil)
            if model.notchGap > 0 {
                // Hollow center: the physical notch lives here.
                Spacer().frame(width: model.notchGap)
            } else {
                Spacer().frame(width: 10)
            }
            HStack(spacing: 5) {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.nowPlaying?.isPlaying == true ? .green : .gray)
                if let nowPlaying = model.nowPlaying {
                    Text(nowPlaying.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: model.notchGap > 0 ? model.rightWingWidth : nil)
        }
    }

    private var glyph: String {
        guard let nowPlaying = model.nowPlaying else { return "music.note" }
        return nowPlaying.isPlaying ? "waveform" : "pause.fill"
    }

    private var expanded: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Workspace \(model.workspace)", systemImage: "square.grid.3x3.middle.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if let nowPlaying = model.nowPlaying {
                    Text(nowPlaying.player.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
            if let nowPlaying = model.nowPlaying {
                VStack(spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(nowPlaying.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
                HStack(spacing: 28) {
                    controlButton("backward.fill") { model.onPrevious?() }
                    controlButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill") {
                        model.onPlayPause?()
                    }
                    controlButton("forward.fill") { model.onNext?() }
                }
            } else {
                Spacer()
                Text("Nothing playing")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
