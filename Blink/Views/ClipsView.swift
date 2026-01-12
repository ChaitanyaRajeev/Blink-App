//
//  ClipsView.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/12/26.
//

import SwiftUI
import AVKit
import Combine

struct ClipsView: View {
    @StateObject private var viewModel = ClipsViewModel()
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var selectedClip: BlinkVideoClip?
    @State private var selectedFilter: ClipFilter = .all
    @State private var uploadingClipId: Int?
    @State private var showUploadSuccess = false
    @State private var showUploadError: String?
    @State private var showConnectDriveAlert = false
    
    enum ClipFilter: String, CaseIterable {
        case all = "All"
        case today = "Today"
        case week = "This Week"
        case motion = "Motion"
    }
    
    var body: some View {
        ZStack {
            Color(hex: "0D0D0D")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Filter chips
                filterChips
                    .padding(.top, 16)
                
                if viewModel.isLoading && viewModel.clips.isEmpty {
                    Spacer()
                    loadingView
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    errorView(message: error)
                    Spacer()
                } else if viewModel.clips.isEmpty {
                    Spacer()
                    emptyView
                    Spacer()
                } else {
                    // Clips list
                    clipsList
                }
            }
            
            // Upload progress overlay
            if let clipId = uploadingClipId {
                uploadingOverlay(clipId: clipId)
            }
            
            // Success toast
            if showUploadSuccess {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to Google Drive")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color(hex: "2A2A2A"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(item: $selectedClip) { clip in
            VideoPlayerView(clip: clip)
        }
        .alert("Connect Google Drive", isPresented: $showConnectDriveAlert) {
            Button("OK") { }
        } message: {
            Text("Please connect your Google Drive account in Settings to save clips.")
        }
        .alert("Upload Failed", isPresented: .init(
            get: { showUploadError != nil },
            set: { if !$0 { showUploadError = nil } }
        )) {
            Button("OK") { showUploadError = nil }
        } message: {
            Text(showUploadError ?? "Unknown error")
        }
        .task {
            await viewModel.loadClips()
        }
    }
    
    private func uploadClipToDrive(_ clip: BlinkVideoClip) {
        guard driveService.isAuthenticated else {
            showConnectDriveAlert = true
            return
        }
        
        uploadingClipId = clip.id
        
        Task {
            do {
                // Download video data
                guard let mediaPath = clip.media else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "No video URL"])
                }
                
                let videoData = try await BlinkAPIService.shared.getVideoData(url: mediaPath)
                
                // Upload to Drive
                let fileName = "\(clip.deviceName ?? "Blink")_\(clip.id)_\(formatDateForFileName()).mp4"
                _ = try await driveService.uploadVideo(data: videoData, fileName: fileName)
                
                await MainActor.run {
                    uploadingClipId = nil
                    withAnimation {
                        showUploadSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showUploadSuccess = false
                        }
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
    
    private func formatDateForFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
    
    private func uploadingOverlay(clipId: Int) -> some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color(hex: "00E5CC"))
                
                Text("Uploading to Google Drive...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                if let clip = viewModel.clips.first(where: { $0.id == clipId }) {
                    Text(clip.deviceName ?? "Video")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(40)
            .background(Color(hex: "1A1A1A"))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clips")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(viewModel.clips.count) recordings")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Button {
                Task {
                    await viewModel.loadClips()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // MARK: - Filter Chips
    
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ClipFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        name: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Clips List
    
    private var clipsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredClips) { clip in
                    ClipCard(
                        clip: clip,
                        viewModel: viewModel,
                        onUploadToDrive: {
                            uploadClipToDrive(clip)
                        }
                    )
                    .onTapGesture {
                        selectedClip = clip
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .refreshable {
            await viewModel.loadClips()
        }
    }
    
    private var filteredClips: [BlinkVideoClip] {
        switch selectedFilter {
        case .all:
            return viewModel.clips
        case .today:
            return viewModel.clips.filter { isToday($0.createdAt) }
        case .week:
            return viewModel.clips.filter { isThisWeek($0.createdAt) }
        case .motion:
            return viewModel.clips.filter { $0.source?.lowercased() == "pir" }
        }
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
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "00E5CC"))
            
            Text("Loading clips...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "FF6B6B"))
            
            Text("Couldn't load clips")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    await viewModel.loadClips()
                }
            } label: {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "0D0D0D"))
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color(hex: "00E5CC"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No Clips Found")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Recorded clips will appear here.\nMotion-triggered recordings are saved to Blink cloud.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color(hex: "00E5CC") : Color(hex: "1E1E1E"))
                )
                .foregroundColor(isSelected ? Color(hex: "0D0D0D") : .white)
        }
    }
}

// MARK: - Clip Card

struct ClipCard: View {
    let clip: BlinkVideoClip
    @ObservedObject var viewModel: ClipsViewModel
    let onUploadToDrive: () -> Void
    
    @StateObject private var driveService = GoogleDriveService.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail
            ZStack {
                if let thumbnailData = viewModel.thumbnails[clip.id],
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 80)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(width: 120, height: 80)
                        .overlay(
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }
                
                // Play icon overlay
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(clip.deviceName ?? "Unknown Camera")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: triggerIcon(for: clip.source))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "00E5CC"))
                    
                    Text(clip.triggerType)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Text(clip.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            // Three-dot menu
            Menu {
                Button {
                    onUploadToDrive()
                } label: {
                    Label("Save to Google Drive", systemImage: "externaldrive.fill")
                }
                .disabled(!driveService.isAuthenticated)
                
                if !driveService.isAuthenticated {
                    Text("Connect Google Drive in Settings")
                        .font(.caption)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(12)
        .background(Color(hex: "1A1A1A"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            await viewModel.loadThumbnail(for: clip)
        }
    }
    
    private func triggerIcon(for source: String?) -> String {
        switch source?.lowercased() {
        case "pir": return "figure.walk.motion"
        case "button": return "hand.tap.fill"
        case "snapshot": return "camera.fill"
        default: return "video.fill"
        }
    }
}

// MARK: - Video Player View

struct VideoPlayerView: View {
    let clip: BlinkVideoClip
    @Environment(\.dismiss) private var dismiss
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var error: String?
    @State private var downloadProgress: Double = 0
    @State private var localVideoURL: URL?
    @State private var videoData: Data?
    @State private var showDriveSheet = false
    @State private var uploadStatus: UploadStatus = .idle
    @State private var showSaveSuccess = false
    
    enum UploadStatus {
        case idle
        case uploading
        case success
        case error(String)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color(hex: "00E5CC"))
                    
                    Text("Downloading video...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    if downloadProgress > 0 {
                        ProgressView(value: downloadProgress)
                            .tint(Color(hex: "00E5CC"))
                            .frame(width: 200)
                    }
                }
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color(hex: "FF6B6B"))
                    
                    Text("Failed to load video")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    
                    Button {
                        Task {
                            await loadVideo()
                        }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "0D0D0D"))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color(hex: "00E5CC"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            
            // Header overlay
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(clip.deviceName ?? "Video")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(clip.formattedDate)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Save to Drive button
                    Button {
                        showDriveSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .disabled(videoData == nil)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
            }
            
            // Success toast
            if showSaveSuccess {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to Google Drive")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color(hex: "2A2A2A"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showDriveSheet) {
            GoogleDriveSheet(
                clip: clip,
                videoData: videoData,
                uploadStatus: $uploadStatus,
                onSuccess: {
                    showDriveSheet = false
                    withAnimation {
                        showSaveSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showSaveSuccess = false
                        }
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            await loadVideo()
        }
        .onDisappear {
            player?.pause()
            player = nil
            // Clean up temp file
            if let url = localVideoURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    private func loadVideo() async {
        isLoading = true
        error = nil
        
        guard let mediaPath = clip.media else {
            error = "No video URL available"
            isLoading = false
            return
        }
        
        print("📹 Loading video: \(mediaPath)")
        
        do {
            // Download video data using our authenticated API
            let data = try await BlinkAPIService.shared.getVideoData(url: mediaPath)
            
            print("📹 Downloaded \(data.count) bytes")
            
            // Store for potential Drive upload
            self.videoData = data
            
            // Save to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "blink_video_\(clip.id).mp4"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            try data.write(to: fileURL)
            localVideoURL = fileURL
            
            print("📹 Saved to: \(fileURL.path)")
            
            // Create player from local file
            await MainActor.run {
                let playerItem = AVPlayerItem(url: fileURL)
                self.player = AVPlayer(playerItem: playerItem)
                self.player?.play()
                self.isLoading = false
            }
            
        } catch {
            print("📹 Error loading video: \(error)")
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Google Drive Sheet

struct GoogleDriveSheet: View {
    let clip: BlinkVideoClip
    let videoData: Data?
    @Binding var uploadStatus: VideoPlayerView.UploadStatus
    let onSuccess: () -> Void
    
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var isSigningIn = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0D0D0D")
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Google Drive Icon
                    Image(systemName: "externaldrive.fill.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "4285F4"), Color(hex: "34A853"), Color(hex: "FBBC05"), Color(hex: "EA4335")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 20)
                    
                    Text("Save to Google Drive")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Clip info
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundColor(Color(hex: "00E5CC"))
                            Text(clip.deviceName ?? "Video Clip")
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(Color(hex: "00E5CC"))
                            Text(clip.formattedDate)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        
                        if let data = videoData {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(Color(hex: "00E5CC"))
                                Text(formatBytes(data.count))
                                    .foregroundColor(.white.opacity(0.7))
                                Spacer()
                            }
                        }
                    }
                    .font(.system(size: 14))
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "FF6B6B"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Action button
                    if driveService.isAuthenticated {
                        Button {
                            Task {
                                await uploadToDrive()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if isUploading {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                        .tint(Color(hex: "0D0D0D"))
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                }
                                Text(isUploading ? "Uploading..." : "Upload to Drive")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "0D0D0D"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "00E5CC"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isUploading || videoData == nil)
                        .padding(.horizontal, 20)
                        
                        Button {
                            driveService.signOut()
                        } label: {
                            Text("Sign out of Google")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.bottom, 20)
                    } else {
                        Button {
                            Task {
                                await signInToGoogle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if isSigningIn {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "person.badge.key.fill")
                                }
                                Text(isSigningIn ? "Signing in..." : "Sign in with Google")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: "4285F4"))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isSigningIn)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func signInToGoogle() async {
        isSigningIn = true
        errorMessage = nil
        
        do {
            try await driveService.signIn()
        } catch GoogleDriveError.cancelled {
            // User cancelled, no error needed
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSigningIn = false
    }
    
    private func uploadToDrive() async {
        guard let data = videoData else { return }
        
        isUploading = true
        errorMessage = nil
        
        do {
            let fileName = "\(clip.deviceName ?? "Blink")_\(clip.id)_\(formatDateForFileName()).mp4"
            _ = try await driveService.uploadVideo(data: data, fileName: fileName)
            
            await MainActor.run {
                onSuccess()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isUploading = false
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func formatDateForFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
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
            print("📹 Loaded \(clips.count) clips")
        } catch {
            errorMessage = error.localizedDescription
            print("📹 Error loading clips: \(error)")
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
            print("📹 Error loading thumbnail for clip \(clip.id): \(error)")
        }
    }
}

#Preview {
    ClipsView()
}

