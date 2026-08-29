import AppKit

/// Now-playing state for the island, read from Music and Spotify via their
/// public scripting interfaces (macOS offers no public system-wide API; the
/// first poll of each app triggers one Automation permission prompt).
@MainActor
final class MediaController {

    struct NowPlaying: Equatable {
        var player: Player
        var title: String
        var artist: String
        var isPlaying: Bool
    }

    enum Player: String, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String {
            switch self {
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }
    }

    private(set) var nowPlaying: NowPlaying?
    var onUpdate: ((NowPlaying?) -> Void)?

    private var timer: Timer?
    private var polling = false

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        setNowPlaying(nil)
    }

    // MARK: - Polling

    private func runningPlayers() -> [Player] {
        Player.allCases.filter { player in
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: player.bundleID).isEmpty
        }
    }

    private func poll() {
        guard !polling else { return }
        let players = runningPlayers()
        guard !players.isEmpty else {
            setNowPlaying(nil)
            return
        }
        polling = true
        var results: [NowPlaying] = []
        var remaining = players.count

        for player in players {
            fetchState(of: player) { [weak self] state in
                if let state { results.append(state) }
                remaining -= 1
                if remaining == 0 {
                    guard let self else { return }
                    self.polling = false
                    // A playing player beats a paused one; ties keep current.
                    let best = results.first { $0.isPlaying }
                        ?? results.first { $0.player == self.nowPlaying?.player }
                        ?? results.first
                    self.setNowPlaying(best)
                }
            }
        }
    }

    private func setNowPlaying(_ state: NowPlaying?) {
        guard state != nowPlaying else { return }
        nowPlaying = state
        onUpdate?(state)
    }

    private func fetchState(of player: Player,
                            completion: @escaping @MainActor (NowPlaying?) -> Void) {
        let script = """
        tell application "\(player.rawValue)"
            if player state is playing or player state is paused then
                set sep to "\u{1}"
                return (player state as text) & sep & (name of current track) & sep & (artist of current track)
            end if
        end tell
        """
        runScript(script) { output in
            let parts = output.components(separatedBy: "\u{1}")
            guard parts.count == 3, !parts[1].isEmpty else {
                completion(nil)
                return
            }
            completion(NowPlaying(player: player, title: parts[1], artist: parts[2],
                                  isPlaying: parts[0] == "playing"))
        }
    }

    // MARK: - Transport

    func playPause() {
        guard let player = nowPlaying?.player else { return }
        command(player, "playpause")
    }

    func nextTrack() {
        guard let player = nowPlaying?.player else { return }
        command(player, "next track")
    }

    func previousTrack() {
        guard let player = nowPlaying?.player else { return }
        command(player, "previous track")
    }

    private func command(_ player: Player, _ verb: String) {
        runScript("tell application \"\(player.rawValue)\" to \(verb)") { [weak self] _ in
            self?.poll()
        }
    }

    /// Runs AppleScript out-of-process so slow scripting apps never block
    /// the main thread.
    private func runScript(_ script: String,
                           completion: @escaping @MainActor (String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(output) }
            }
        }
        do {
            try process.run()
        } catch {
            completion("")
        }
    }
}
