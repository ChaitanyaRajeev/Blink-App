//
//  ContentView.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @ObservedObject private var apiService = BlinkAPIService.shared
    
    var body: some View {
        ZStack {
            if apiService.isAuthenticated {
                MainTabView(authViewModel: authViewModel)
                    .transition(.opacity)
            } else {
                LoginView(authViewModel: authViewModel)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: apiService.isAuthenticated)
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            TabView(selection: $selectedTab) {
                HomeView(authViewModel: authViewModel)
                    .tag(0)
                
                ClipsView()
                    .tag(1)
                
                SettingsView(authViewModel: authViewModel)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Custom Tab Bar
            HStack(spacing: 0) {
                TabButton(icon: "house", label: "Home", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                
                TabButton(icon: "play.rectangle.on.rectangle", label: "Clips", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                
                TabButton(icon: "gearshape", label: "Settings", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .background(
                Color.white
                    .shadow(color: .black.opacity(0.08), radius: 20, y: -5)
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 22, weight: .medium))
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? Color(hex: "1A1A1A") : Color(hex: "1A1A1A").opacity(0.35))
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var camerasViewModel = CamerasViewModel()
    @State private var selectedCamera: CameraDisplay?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Welcome Chai!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color(hex: "1A1A1A"))
                    .padding(.top, 60)
                
                // Cameras
                if camerasViewModel.isLoading && camerasViewModel.cameras.isEmpty {
                    loadingState
                } else if camerasViewModel.cameras.isEmpty {
                    emptyState
                } else {
                    camerasGrid
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .background(Color.white)
        .refreshable {
            await camerasViewModel.loadCameras()
        }
        .fullScreenCover(item: $selectedCamera) { camera in
            LiveViewScreen(camera: camera, camerasViewModel: camerasViewModel)
        }
        .task {
            await camerasViewModel.loadCameras()
        }
    }
    
    private var camerasGrid: some View {
        VStack(spacing: 12) {
            ForEach(camerasViewModel.cameras) { camera in
                LargeCameraCard(
                    camera: camera,
                    thumbnailData: camerasViewModel.thumbnails[camera.id]
                )
                .onTapGesture {
                    selectedCamera = camera
                }
            }
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color(hex: "1A1A1A"))
            Text("Loading cameras...")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "999999"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "CCCCCC"))
            
            Text("No cameras found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: "999999"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Camera Card

struct LargeCameraCard: View {
    let camera: CameraDisplay
    let thumbnailData: Data?
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail
            if let data = thumbnailData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(hex: "F0F0F0"))
                    .frame(height: 160)
                    .overlay(
                        ProgressView()
                            .tint(Color(hex: "CCCCCC"))
                    )
            }
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Camera info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(camera.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(camera.isEnabled ? Color(hex: "4CD964") : Color(hex: "FF3B30"))
                            .frame(width: 6, height: 6)
                        Text(camera.isEnabled ? "Online" : "Offline")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Spacer()
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - Live View Screen (Simplified)

struct LiveViewScreen: View {
    let camera: CameraDisplay
    @ObservedObject var camerasViewModel: CamerasViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentImage: UIImage?
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Camera feed
            if let image = currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else if let data = camerasViewModel.thumbnails[camera.id],
                      let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Minimal overlay
        VStack {
                // Top bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(camera.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("Live")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Color.clear
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Refreshing indicator
                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                        Text("Refreshing...")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 50)
                }
            }
        }
        .task {
            await startLiveRefresh()
        }
    }
    
    private func startLiveRefresh() async {
        let apiService = BlinkAPIService.shared
        
        while !Task.isCancelled {
            isRefreshing = true
            
            do {
                // Request new snapshot based on camera type
                if camera.type == .mini {
                    try await apiService.requestOwlSnapshot(
                        networkId: camera.networkId,
                        cameraId: camera.id
                    )
                } else {
                    try await apiService.requestSnapshot(
                        networkId: camera.networkId,
                        cameraId: camera.id
                    )
                }
                
                try await Task.sleep(nanoseconds: 2_000_000_000)
                
                if let thumbnailURL = camera.thumbnailURL,
                   let data = try? await apiService.getThumbnail(url: thumbnailURL) {
                    await MainActor.run {
                        currentImage = UIImage(data: data)
                    }
                }
            } catch {
                print("Live refresh error: \(error)")
            }
            
            isRefreshing = false
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var isConnectingDrive = false
    @State private var showDisconnectAlert = false
    
    var body: some View {
        ZStack {
            Color(hex: "F5F5F5")
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(hex: "1A1A1A"))
                        .padding(.top, 60)
                    
                    // Account
                    SettingsSection(title: "Account") {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(String(BlinkAPIService.shared.session?.username.prefix(1).uppercased() ?? "U"))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(BlinkAPIService.shared.session?.username ?? "Unknown")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(hex: "1A1A1A"))
                                
                                Text("Blink Account")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "666666"))
                            }
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    }
                    
                    // Cloud Storage
                    SettingsSection(title: "Cloud Storage") {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Google Drive")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(hex: "1A1A1A"))
                                
                                if driveService.isAuthenticated {
                                    Text("Connected")
                                        .font(.system(size: 13))
                                        .foregroundColor(.green)
                                } else {
                                    Text("Not connected")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(hex: "666666"))
                                }
                            }
                            
                            Spacer()
                            
                            if driveService.isAuthenticated {
                                Button("Disconnect") {
                                    showDisconnectAlert = true
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                            } else {
                                Button {
                                    Task {
                                        isConnectingDrive = true
                                        try? await driveService.signIn()
                                        isConnectingDrive = false
                                    }
                                } label: {
                                    if isConnectingDrive {
                                        ProgressView()
                                            .tint(Color(hex: "4285F4"))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Connect")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .foregroundColor(Color(hex: "4285F4"))
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    }
                    
                    // About
                    SettingsSection(title: "About") {
                        VStack(spacing: 0) {
                            SettingsRow(label: "Version", value: "1.0.0")
                            Divider().padding(.horizontal, 16)
                            SettingsRow(label: "Region", value: BlinkAPIService.shared.session?.region ?? "-")
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Sign Out
                    Button {
                        authViewModel.logout()
                    } label: {
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .alert("Disconnect Google Drive?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                driveService.signOut()
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "999999"))
                .tracking(1)
            
            content
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "666666"))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(hex: "1A1A1A"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    ContentView()
}
