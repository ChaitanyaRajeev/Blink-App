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
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.05)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
            } else {
                LoginView(authViewModel: authViewModel)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.05)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: apiService.isAuthenticated)
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab: Tab = .home
    
    enum Tab {
        case home
        case clips
        case settings
    }
    
    var body: some View {
        ZStack {
            Color(hex: "0D0D0D")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Content
                ZStack {
                    switch selectedTab {
                    case .home:
                        DashboardContentView(authViewModel: authViewModel)
                    case .clips:
                        ClipsView()
                    case .settings:
                        FullSettingsView(authViewModel: authViewModel)
                    }
                }
                
                // Bottom Tab Bar
                CustomTabBar(selectedTab: $selectedTab)
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    
    var body: some View {
        HStack(spacing: 0) {
            TabBarItem(
                icon: "house.fill",
                title: "Home",
                isSelected: selectedTab == .home
            ) {
                selectedTab = .home
            }
            
            TabBarItem(
                icon: "film.stack",
                title: "Clips",
                isSelected: selectedTab == .clips
            ) {
                selectedTab = .clips
            }
            
            TabBarItem(
                icon: "gearshape.fill",
                title: "Settings",
                isSelected: selectedTab == .settings
            ) {
                selectedTab = .settings
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(hex: "1A1A1A"))
        )
        .padding(.horizontal, 30)
        .padding(.bottom, 20)
    }
}

struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? Color(hex: "00E5CC") : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Dashboard Content (without tab bar)

struct DashboardContentView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var camerasViewModel = CamerasViewModel()
    @State private var selectedCamera: CameraDisplay?
    @State private var selectedRoom: String = "All"
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.top, 10)
            
            if camerasViewModel.isLoading && camerasViewModel.cameras.isEmpty {
                Spacer()
                loadingView
                Spacer()
            } else if let error = camerasViewModel.errorMessage {
                Spacer()
                errorView(message: error)
                Spacer()
            } else if camerasViewModel.cameras.isEmpty {
                Spacer()
                emptyView
                Spacer()
            } else {
                // Room filter chips
                roomFilterView
                    .padding(.top, 20)
                
                // Section header
                HStack {
                    Text("Real time")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)
                
                // Camera grid
                cameraGrid
            }
            
            Spacer(minLength: 0)
        }
        .fullScreenCover(item: $selectedCamera) { camera in
            CameraDetailView(camera: camera, camerasViewModel: camerasViewModel)
        }
        .task {
            await camerasViewModel.loadCameras()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hello, \(camerasViewModel.session?.username.components(separatedBy: "@").first ?? "User")")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button {
                Task {
                    await camerasViewModel.loadCameras()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .disabled(camerasViewModel.isLoading)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Room Filter View
    
    private var roomFilterView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(getRoomNames(), id: \.self) { room in
                    RoomChip(
                        name: room,
                        icon: iconForRoom(room),
                        isSelected: selectedRoom == room
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedRoom = room
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func getRoomNames() -> [String] {
        var rooms = ["All"]
        rooms.append(contentsOf: camerasViewModel.cameras.map { $0.name })
        return rooms
    }
    
    private func iconForRoom(_ room: String) -> String {
        let lowercased = room.lowercased()
        if lowercased.contains("living") { return "sofa.fill" }
        if lowercased.contains("bed") { return "bed.double.fill" }
        if lowercased.contains("bath") { return "shower.fill" }
        if lowercased.contains("kitchen") { return "refrigerator.fill" }
        if lowercased.contains("garage") { return "car.fill" }
        if lowercased.contains("front") || lowercased.contains("door") { return "door.left.hand.closed" }
        if lowercased.contains("back") { return "tree.fill" }
        if lowercased.contains("office") { return "desktopcomputer" }
        return "video.fill"
    }
    
    // MARK: - Camera Grid
    
    private var cameraGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredCameras) { camera in
                    CameraGridCard(
                        camera: camera,
                        thumbnailData: camerasViewModel.thumbnails[camera.id]
                    )
                    .onTapGesture {
                        selectedCamera = camera
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .refreshable {
            await camerasViewModel.loadCameras()
        }
    }
    
    private var filteredCameras: [CameraDisplay] {
        if selectedRoom == "All" {
            return camerasViewModel.cameras
        }
        return camerasViewModel.cameras.filter { $0.name == selectedRoom }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "00E5CC"))
            
            Text("Loading cameras...")
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
            
            Text("Something went wrong")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    await camerasViewModel.loadCameras()
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
            Image(systemName: "video.slash.fill")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No Cameras Found")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("Make sure your Blink cameras are set up and online")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Full Settings View (standalone)

struct FullSettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var driveService = GoogleDriveService.shared
    @State private var isConnectingDrive = false
    @State private var driveError: String?
    @State private var showDisconnectAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Account section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("BLINK ACCOUNT")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(Color(hex: "00E5CC"))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(BlinkAPIService.shared.session?.username ?? "Unknown")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Account ID: \(BlinkAPIService.shared.session?.accountId ?? 0)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Google Drive section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CLOUD STORAGE")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        
                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                // Google Drive icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(hex: "4285F4"), Color(hex: "34A853")],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: "externaldrive.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Google Drive")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    if driveService.isAuthenticated {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 8, height: 8)
                                            Text("Connected")
                                                .font(.system(size: 13))
                                                .foregroundColor(.green)
                                        }
                                    } else {
                                        Text("Not connected")
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                                
                                Spacer()
                                
                                if driveService.isAuthenticated {
                                    Button {
                                        showDisconnectAlert = true
                                    } label: {
                                        Text("Disconnect")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color(hex: "FF6B6B"))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(hex: "FF6B6B").opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                } else {
                                    Button {
                                        Task {
                                            await connectGoogleDrive()
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if isConnectingDrive {
                                                ProgressView()
                                                    .scaleEffect(0.7)
                                                    .tint(.white)
                                            }
                                            Text(isConnectingDrive ? "Connecting..." : "Connect")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(hex: "4285F4"))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .disabled(isConnectingDrive)
                                }
                            }
                            .padding(16)
                            
                            if driveService.isAuthenticated {
                                Divider().background(Color.white.opacity(0.1))
                                
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(Color(hex: "00E5CC"))
                                    Text("Clips will be saved to")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    Text("Blink Clips")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        if let error = driveError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "FF6B6B"))
                                .padding(.horizontal, 4)
                        }
                        
                        if driveService.isAuthenticated {
                            Text("Videos you save from Clips will be uploaded to your Google Drive in the 'Blink Clips' folder.")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 4)
                        }
                    }
                    
                    // Session info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SESSION")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        
                        VStack(spacing: 0) {
                            settingsInfoRow(title: "Region", value: BlinkAPIService.shared.session?.region ?? "Unknown")
                            Divider().background(Color.white.opacity(0.1))
                            settingsInfoRow(title: "Host", value: BlinkAPIService.shared.session?.host ?? "Unknown")
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // About section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ABOUT")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        
                        VStack(spacing: 0) {
                            settingsInfoRow(title: "App Version", value: "1.0.0")
                            Divider().background(Color.white.opacity(0.1))
                            settingsInfoRow(title: "Build", value: "2026.01")
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    Spacer(minLength: 40)
                    
                    // Logout button
                    Button {
                        authViewModel.logout()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out of Blink")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "FF6B6B"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "FF6B6B").opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .alert("Disconnect Google Drive?", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                driveService.signOut()
            }
        } message: {
            Text("You'll need to sign in again to save clips to Google Drive.")
        }
    }
    
    private func connectGoogleDrive() async {
        isConnectingDrive = true
        driveError = nil
        
        do {
            try await driveService.signIn()
        } catch GoogleDriveError.cancelled {
            // User cancelled, no error needed
        } catch {
            driveError = error.localizedDescription
        }
        
        isConnectingDrive = false
    }
    
    private func settingsInfoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    ContentView()
}
