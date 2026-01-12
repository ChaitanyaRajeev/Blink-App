//
//  CameraDetailView.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import SwiftUI
import Combine

struct CameraDetailView: View {
    let camera: CameraDisplay
    @ObservedObject var camerasViewModel: CamerasViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLiveStreaming = false
    @State private var liveImage: UIImage?
    @State private var streamTask: Task<Void, Never>?
    @State private var frameCount = 0
    @State private var isRecording = false
    @State private var showRecordingAlert = false
    @State private var recordingMessage = ""
    @State private var currentTime = Date()
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Background
            Color(hex: "0D0D0D")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Live View Card
                        liveViewCard
                        
                        // Playback Controls
                        playbackControls
                        
                        // Timestamp
                        Text(formattedTime)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        // D-Pad Controls (visual only for Blink)
                        dPadControls
                        
                        // Action Buttons
                        actionButtons
                        
                        // Camera Info
                        cameraInfoSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onDisappear {
            stopLiveStream()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .alert("Recording", isPresented: $showRecordingAlert) {
            Button("OK") { }
        } message: {
            Text(recordingMessage)
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss EEEE dd.MM.yyyy"
        return formatter.string(from: currentTime)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(camera.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text(camera.type.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(camera.isEnabled ? Color(hex: "00E5CC") : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(camera.isEnabled ? "Online" : "Offline")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Live View Card
    
    private var liveViewCard: some View {
        ZStack {
            // Video/Image content
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "1A1A2E"))
                .aspectRatio(16/9, contentMode: .fit)
            
            if let image = liveImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else if let data = camerasViewModel.thumbnails[camera.id], let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: camera.type.icon)
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.2))
                    
                    Text("Tap Live View to start")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            // Live badge & recording indicator
            VStack {
                HStack {
                    if isLiveStreaming {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text("LIVE")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            
                            if frameCount > 0 {
                                Text("• \(frameCount) frames")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    
                    if isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            
                            Text("Recording")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
                .padding(16)
                
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Playback Controls
    
    private var playbackControls: some View {
        HStack(spacing: 20) {
            // Refresh button
            ControlButton(
                icon: "arrow.clockwise",
                label: "Refresh",
                color: Color(hex: "00E5CC")
            ) {
                Task {
                    await refreshSnapshot()
                }
            }
            
            // Live/Stop button
            ControlButton(
                icon: isLiveStreaming ? "stop.fill" : "play.fill",
                label: isLiveStreaming ? "Stop" : "Live",
                color: isLiveStreaming ? Color.red : Color(hex: "00E5CC"),
                isLarge: true
            ) {
                if isLiveStreaming {
                    stopLiveStream()
                } else {
                    startLiveStream()
                }
            }
            
            // Record button
            ControlButton(
                icon: "record.circle",
                label: "Record",
                color: Color(hex: "FF4757")
            ) {
                Task {
                    await recordClip()
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - D-Pad Controls
    
    private var dPadControls: some View {
        ZStack {
            // Outer ring
            Circle()
                .fill(Color(hex: "00E5CC"))
                .frame(width: 180, height: 180)
            
            // Inner dark circle
            Circle()
                .fill(Color(hex: "0D0D0D"))
                .frame(width: 80, height: 80)
            
            // Direction buttons
            VStack(spacing: 60) {
                // Up
                Image(systemName: "chevron.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                // Down
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 60) {
                // Left
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                // Right
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Center lines
            VStack(spacing: 4) {
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 30, height: 3)
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 30, height: 3)
            }
            
            // Side labels
            HStack {
                VStack(spacing: 8) {
                    Text("ZM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "00E5CC"))
                    
                    VStack(spacing: 4) {
                        Text("+")
                        Text("−")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                }
                .offset(x: -100)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text("CN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "00E5CC"))
                    
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.left")
                        Image(systemName: "arrow.down.right")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                }
                .offset(x: 100)
            }
        }
        .frame(width: 260, height: 180)
        .opacity(0.6) // Dimmed since Blink doesn't support PTZ
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 30) {
            ActionCircleButton(icon: "speaker.slash.fill", isActive: false)
            ActionCircleButton(icon: "power", isActive: camera.isEnabled, color: Color(hex: "00E5CC"))
            ActionCircleButton(icon: "camera.fill", isActive: false) {
                Task {
                    await takeSnapshot()
                }
            }
        }
    }
    
    // MARK: - Camera Info Section
    
    private var cameraInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CAMERA INFO")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)
            
            VStack(spacing: 0) {
                InfoRow(icon: "number", title: "Camera ID", value: "\(camera.id)")
                Divider().background(Color.white.opacity(0.1))
                InfoRow(icon: "globe", title: "Network ID", value: "\(camera.networkId)")
                Divider().background(Color.white.opacity(0.1))
                InfoRow(icon: "camera", title: "Type", value: camera.type.displayName)
                Divider().background(Color.white.opacity(0.1))
                InfoRow(icon: "checkmark.circle", title: "Status", value: camera.status.capitalized)
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Live Stream Functions
    
    private func startLiveStream() {
        isLiveStreaming = true
        frameCount = 0
        
        streamTask = Task {
            while !Task.isCancelled && isLiveStreaming {
                do {
                    // Request new snapshot
                    if camera.type == .mini {
                        try await BlinkAPIService.shared.requestOwlSnapshot(
                            networkId: camera.networkId,
                            cameraId: camera.id
                        )
                    } else {
                        try await BlinkAPIService.shared.requestSnapshot(
                            networkId: camera.networkId,
                            cameraId: camera.id
                        )
                    }
                    
                    // Wait for camera to process
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    
                    // Fetch the new thumbnail
                    await camerasViewModel.loadCameras()
                    
                    // Update live image
                    if let data = camerasViewModel.thumbnails[camera.id],
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            liveImage = image
                            frameCount += 1
                        }
                    }
                    
                    // Small delay between frames
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                } catch {
                    print("Live stream error: \(error)")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }
    
    private func stopLiveStream() {
        isLiveStreaming = false
        streamTask?.cancel()
        streamTask = nil
    }
    
    private func refreshSnapshot() async {
        await camerasViewModel.refreshSnapshot(for: camera)
        if let data = camerasViewModel.thumbnails[camera.id],
           let image = UIImage(data: data) {
            liveImage = image
        }
    }
    
    private func takeSnapshot() async {
        do {
            if camera.type == .mini {
                try await BlinkAPIService.shared.requestOwlSnapshot(
                    networkId: camera.networkId,
                    cameraId: camera.id
                )
            } else {
                try await BlinkAPIService.shared.requestSnapshot(
                    networkId: camera.networkId,
                    cameraId: camera.id
                )
            }
            
            try await Task.sleep(nanoseconds: 3_000_000_000)
            await camerasViewModel.loadCameras()
            
            if let data = camerasViewModel.thumbnails[camera.id],
               let image = UIImage(data: data) {
                liveImage = image
            }
        } catch {
            print("Snapshot error: \(error)")
        }
    }
    
    private func recordClip() async {
        isRecording = true
        
        do {
            try await BlinkAPIService.shared.requestRecording(
                networkId: camera.networkId,
                cameraId: camera.id
            )
            
            recordingMessage = "Recording started! Check Blink cloud for the clip."
            showRecordingAlert = true
            
        } catch {
            recordingMessage = "Recording failed: \(error.localizedDescription)"
            showRecordingAlert = true
        }
        
        isRecording = false
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let label: String
    let color: Color
    var isLarge: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: isLarge ? 70 : 56, height: isLarge ? 70 : 56)
                    
                    Circle()
                        .stroke(color, lineWidth: 3)
                        .frame(width: isLarge ? 70 : 56, height: isLarge ? 70 : 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: isLarge ? 24 : 20, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Action Circle Button

struct ActionCircleButton: View {
    let icon: String
    let isActive: Bool
    var color: Color = .white
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button {
            action?()
        } label: {
            ZStack {
                Circle()
                    .fill(isActive ? color.opacity(0.2) : Color(hex: "2A2A2A"))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isActive ? color : .white.opacity(0.5))
            }
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "00E5CC"))
                .frame(width: 30)
            
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    CameraDetailView(
        camera: CameraDisplay(
            id: 1,
            name: "Living Room",
            networkId: 1,
            type: .mini,
            thumbnailURL: nil,
            status: "online",
            batteryState: nil,
            isEnabled: true
        ),
        camerasViewModel: CamerasViewModel()
    )
}
