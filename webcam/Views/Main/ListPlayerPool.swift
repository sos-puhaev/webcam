import AVFoundation
import Foundation

@MainActor
final class ListPlayerPool {
    static let shared = ListPlayerPool(maxPlayers: 6)

    private let maxPlayers: Int

    private var free: [AVPlayer] = []
    private var inUse: [Int: AVPlayer] = [:]
    private var warm: [Int: AVPlayer] = [:]
    private var warmLRU: [Int] = []

    init(maxPlayers: Int) {
        self.maxPlayers = maxPlayers
    }

    func warmUp() {
        guard free.isEmpty, inUse.isEmpty, warm.isEmpty else { return }
        free = (0..<maxPlayers).map { _ in Self.makePlayer() }
    }

    func prefetch(cameraIds: [Int]) {
        for id in cameraIds {
            if inUse[id] != nil { continue }
            if warm[id] != nil {
                touchWarm(id)
                continue
            }

            let player = takePlayerForWarm()
            player.pause()
            player.isMuted = true
            warm[id] = player
            touchWarm(id)
        }

        trimWarmIfNeeded()
    }

    func acquire(for cameraId: Int) -> AVPlayer {
        if let p = inUse[cameraId] { return p }

        if let p = warm.removeValue(forKey: cameraId) {
            warmLRU.removeAll { $0 == cameraId }
            inUse[cameraId] = p
            return p
        }

        let p = takePlayerForUse()
        p.isMuted = true
        inUse[cameraId] = p
        return p
    }

    func release(cameraId: Int, keepWarm: Bool = true) {
        guard let p = inUse.removeValue(forKey: cameraId) else { return }
        p.pause()

        if keepWarm {
            warm[cameraId] = p
            touchWarm(cameraId)
            trimWarmIfNeeded()
        } else {
            p.replaceCurrentItem(with: nil)
            free.append(p)
        }
    }

    // MARK: - internals

    private static func makePlayer() -> AVPlayer {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        p.isMuted = true
        return p
    }

    private func takePlayerForWarm() -> AVPlayer {
        if let p = free.popLast() { return p }

        let total = free.count + inUse.count + warm.count
        if total < maxPlayers {
            return Self.makePlayer()
        }

        if let evictId = warmLRU.first,
           let evict = warm.removeValue(forKey: evictId) {
            warmLRU.removeFirst()
            evict.replaceCurrentItem(with: nil)
            return evict
        }

        return Self.makePlayer()
    }

    private func takePlayerForUse() -> AVPlayer {
        if let p = free.popLast() { return p }

        let total = free.count + inUse.count + warm.count
        if total < maxPlayers {
            return Self.makePlayer()
        }

        if let evictId = warmLRU.first,
           let evict = warm.removeValue(forKey: evictId) {
            warmLRU.removeFirst()
            evict.replaceCurrentItem(with: nil)
            return evict
        }

        return Self.makePlayer()
    }

    private func touchWarm(_ id: Int) {
        warmLRU.removeAll { $0 == id }
        warmLRU.append(id)
    }

    private func trimWarmIfNeeded() {
        let allowed = max(0, maxPlayers - inUse.count)
        while warm.count > allowed {
            guard let id = warmLRU.first,
                  let p = warm.removeValue(forKey: id) else { break }
            warmLRU.removeFirst()
            p.replaceCurrentItem(with: nil)
            free.append(p)
        }
    }
}
