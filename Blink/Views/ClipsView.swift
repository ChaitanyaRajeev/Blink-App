//
//  ClipsView.swift
//  Blink
//

import SwiftUI
import AVKit
import Combine

struct ClipsView: View {
    @StateObject private var viewModel = ClipsViewModel()
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var selectedClip: BlinkVideoClip?
    @State private var selectedTimeFilter: String = "All"
    @State private var selectedCameraFilter: String = "All"
    @State private var uploadingClipId: Int?
    @State private var showUploadSuccess = false
    @State private var showUploadError: String?
    @State private var showConnectDriveAlert = false
    
    // Video player state
    @State private var player: AVPlayer?
    @State private var isLoadingVideo = false
    @State private var localVideoURL: URL?
    
    private let timeFilters = ["All", "Today", "This Week"]
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                Text("Clips")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 16)
                
                // Filter dropdowns - fixed position
                HStack(spacing: 12) {
                    // Time dropdown
                    Menu {
                        ForEach(timeFilters, id: \.self) { filter in
                            Button {
                                selectedTimeFilter = filter
                            } label: {
                                HStack {
                                    Text(filter)
                                    if selectedTimeFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedTimeFilter)
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "1A1A1A"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: "F5F5F5"))
                        .clipShape(Capsule())
                    }
                    
                    // Camera dropdown
                    Menu {
                        ForEach(getCameraNames(), id: \.self) { camera in
                            Button {
                                selectedCameraFilter = camera
                            } label: {
                                HStack {
                                    Text(camera)
                                    if selectedCameraFilter == camera {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11))
                            Text(selectedCameraFilter)
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "1A1A1A"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(hex: "F5F5F5"))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Upload to drive button (if video selected and drive connected)
                    if let clip = selectedClip, driveService.isAuthenticated {
                        Button {
                            uploadClipToDrive(clip)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "007AFF"))
                                .frame(width: 36, height: 36)
                                .background(Color(hex: "F5F5F5"))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Video player area (only when clip selected)
                if selectedClip != nil {
                    videoPlayerArea
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                
                // Clips List
                if viewModel.isLoading && viewModel.clips.isEmpty {
                    Spacer()
                    loadingState
                    Spacer()
                } else if filteredClips.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    clipsListSection
                }
            }
            
            // Upload overlay
            if uploadingClipId != nil {
                uploadingOverlay
            }
            
            // Success toast
            if showUploadSuccess {
                VStack {
                    Spacer()
                    successToast
                        .padding(.bottom, 120)
                }
            }
        }
        .alert("Connect Google Drive", isPresented: $showConnectDriveAlert) {
            Button("OK") { }
        } message: {
            Text("Connect your Google Drive in Settings to save clips.")
        }
        .alert("Upload Failed", isPresented: .init(
            get: { showUploadError != nil },
            set: { if !$0 { showUploadError = nil } }
        )) {
            Button("OK") { showUploadError = nil }
        } message: {
            Text(showUploadError ?? "")
        }
        .task {
            await viewModel.loadClips()
        }
        .onDisappear {
            stopVideo()
        }
    }
    
    // MARK: - Video Player Area
    
    private var videoPlayerArea: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Loading state
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "F5F5F5"))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        ProgressView()
                            .tint(Color(hex: "999999"))
                    )
            }
        }
    }
    
    // MARK: - Clips List Section
    
    private var clipsListSection: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(filteredClips) { clip in
                    ClipRow(
                        clip: clip,
                        thumbnailData: viewModel.thumbnails[clip.id],
                        isSelected: selectedClip?.id == clip.id,
                        onTap: { selectClip(clip) },
                        onUpload: { uploadClipToDrive(clip) },
                        isDriveConnected: driveService.isAuthenticated
                    )
                    .task {
                        await viewModel.loadThumbnail(for: clip)
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            await viewModel.loadClips()
        }
    }
    
    // MARK: - Helpers
    
    private func getCameraNames() -> [String] {
        var names = Set<String>()
        for clip in viewModel.clips {
            if let name = clip.deviceName {
                names.insert(name)
            }
        }
        var result = ["All"]
        result.append(contentsOf: names.sorted())
        return result
    }
    
    private var filteredClips: [BlinkVideoClip] {
        var clips = viewModel.clips
        
        switch selectedTimeFilter {
        case "Today": clips = clips.filter { isToday($0.createdAt) }
        case "This Week": clips = clips.filter { isThisWeek($0.createdAt) }
        default: break
        }
        
        if selectedCameraFilter != "All" {
            clips = clips.filter { $0.deviceName == selectedCameraFilter }
        }
        
        return clips
    }
    
    private func isToday(_ dateString: String?) -> Bool {
        guard let dateString = dateString else { return false }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            return Calendar.current.isDateInToday(date)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return Calendar.current.isDateInToday(date)
        }
        return false
    }
    
    private func isThisWeek(_ dateString: String?) -> Bool {
        guard let dateString = dateString else { return false }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        }
        return false
    }
    
    // MARK: - Video Control
    
    private func selectClip(_ clip: BlinkVideoClip) {
        // If same clip, toggle play/pause
        if selectedClip?.id == clip.id {
            if player?.rate == 0 {
                player?.play()
            } else {
                player?.pause()
            }
            return
        }
        
        stopVideo()
        selectedClip = clip
        loadVideo(for: clip)
    }
    
    private func loadVideo(for clip: BlinkVideoClip) {
        guard let mediaPath = clip.media else { return }
        isLoadingVideo = true
        
        Task {
            do {
                let data = try await BlinkAPIService.shared.getVideoData(url: mediaPath)
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("clip_\(clip.id).mp4")
                try data.write(to: fileURL)
                
                await MainActor.run {
                    localVideoURL = fileURL
                    let playerItem = AVPlayerItem(url: fileURL)
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                    self.isLoadingVideo = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingVideo = false
                }
            }
        }
    }
    
    private func stopVideo() {
        player?.pause()
        player = nil
        if let url = localVideoURL {
            try? FileManager.default.removeItem(at: url)
            localVideoURL = nil
        }
    }
    
    // MARK: - Upload
    
    private func uploadClipToDrive(_ clip: BlinkVideoClip) {
        guard driveService.isAuthenticated else {
            showConnectDriveAlert = true
            return
        }
        
        uploadingClipId = clip.id
        
        Task {
            do {
                guard let mediaPath = clip.media else { throw NSError(domain: "", code: 0) }
                let videoData = try await BlinkAPIService.shared.getVideoData(url: mediaPath)
                let fileName = "\(clip.deviceName ?? "Blink")_\(clip.id).mp4"
                _ = try await driveService.uploadVideo(data: videoData, fileName: fileName)
                
                await MainActor.run {
                    uploadingClipId = nil
                    withAnimation { showUploadSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showUploadSuccess = false }
                    }
                }
            } catch {
                await MainActor.run {
                    uploadingClipId = nil
                    showUploadError = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - States
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(hex: "999999"))
            Text("Loading clips...")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "999999"))
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "CCCCCC"))
            Text("No clips")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "999999"))
        }
    }
    
    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Uploading...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color(hex: "333333"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var successToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Saved to Drive")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(hex: "333333"))
        .clipShape(Capsule())
    }
}

// MARK: - Clip Row

struct ClipRow: View {
    let clip: BlinkVideoClip
    let thumbnailData: Data?
    let isSelected: Bool
    let onTap: () -> Void
    let onUpload: () -> Void
    let isDriveConnected: Bool
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    if let data = thumbnailData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 42)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(hex: "F0F0F0"))
                            .frame(width: 56, height: 42)
                            .overlay(
                                Image(systemName: "video.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "CCCCCC"))
                            )
                    }
                    
                    // Playing indicator
                    if isSelected {
                        Color.black.opacity(0.3)
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.deviceName ?? "Camera")
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? Color(hex: "007AFF") : Color(hex: "1A1A1A"))
                    
                    Text(clip.formattedDate)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "999999"))
                }
                
                Spacer()
                
                // Menu
                Menu {
                    Button { onTap() } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    if isDriveConnected {
                        Button { onUpload() } label: {
                            Label("Save to Drive", systemImage: "externaldrive")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "CCCCCC"))
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(isSelected ? Color(hex: "F8F8F8") : Color.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Clips ViewModel

@MainActor
class ClipsViewModel: ObservableObject {
    @Published var clips: [BlinkVideoClip] = []
    @Published var thumbnails: [Int: Data] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = BlinkAPIService.shared
    
    func loadClips() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await apiService.getVideos()
            clips = response.media ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadThumbnail(for clip: BlinkVideoClip) async {
        guard thumbnails[clip.id] == nil,
              let thumbnailPath = clip.thumbnail else { return }
        
        do {
            let data = try await apiService.getThumbnail(url: thumbnailPath)
            thumbnails[clip.id] = data
        } catch {
            print("Thumbnail error: \(error)")
        }
    }
}
