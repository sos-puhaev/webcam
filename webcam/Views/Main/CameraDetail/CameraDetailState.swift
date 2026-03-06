import SwiftUI
import Combine

@MainActor
final class CameraDetailState: ObservableObject {
    // Playback UI
    @Published var isPlaying = true
    @Published var showVideoError = false
    @Published var videoErrorMessage = ""
    @Published var isLoading = true

    // DVR
    @Published var positionSeconds: Double = 0
    @Published var previewPositionSeconds: Double = 0
    @Published var isScrubbing = false

    // Cache markers for scrubber
    @Published var cachedMarkers: [TimelineScrubber.TimelineMarker] = []
    
    @Published var archiveSpeed: Double? = nil
    
    // ✅ база для “движения шкалы” от AVPlayer времени
    @Published var archiveBaseFromTs: Int? = nil           // ts, с которого открыт архив
    @Published var archiveBasePlayerSeconds: Double = 0    // playerTime на момент открытия
    @Published var archiveBasePositionSeconds: Double = 0   // позиция на шкале в момент открытия архива
    @Published var archiveBaseSpeed: Double = 1

    // Guards
    var debounceTask: Task<Void, Never>?
    var lastRequestedFromTs: Int?
    var lastOpenedPositionSeconds: Double?
}
