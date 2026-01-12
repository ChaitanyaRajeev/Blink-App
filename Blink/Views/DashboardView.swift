//
//  DashboardView.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import SwiftUI
import Combine

struct DashboardView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var camerasViewModel = CamerasViewModel()
    @State private var selectedCamera: CameraDisplay?
    @State private var showSettings = false
    @State private var selectedRoom: String = "All"
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(hex: "0D0D0D")
                    .ignoresSafeArea()
                
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
                    
                    // Bottom tab bar
                    bottomTabBar
                }
            }
            .fullScreenCover(item: $selectedCamera) { camera in
                CameraDetailView(camera: camera, camerasViewModel: camerasViewModel)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel, camerasViewModel: camerasViewModel)
            }
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
            
            // Refresh button
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
    
    // MARK: - Bottom Tab Bar
    
    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            TabBarButton(icon: "house.fill", isSelected: true)
            TabBarButton(icon: "gearshape.fill", isSelected: false) {
                showSettings = true
            }
            TabBarButton(icon: "person.fill", isSelected: false)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 40)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Color(hex: "1A1A1A"))
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
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

// MARK: - Room Chip

struct RoomChip: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                
                Text(name)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color(hex: "00E5CC") : Color(hex: "1E1E1E"))
            )
            .foregroundColor(isSelected ? Color(hex: "0D0D0D") : .white)
        }
    }
}

// MARK: - Tab Bar Button

struct TabBarButton: View {
    let icon: String
    let isSelected: Bool
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Camera Grid Card

struct CameraGridCard: View {
    let camera: CameraDisplay
    let thumbnailData: Data?
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            ZStack(alignment: .bottomLeading) {
                if let data = thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(height: 120)
                        .overlay(
                            Image(systemName: camera.type.icon)
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.2))
                        )
                }
                
                // Gradient overlay
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Camera name
                Text(camera.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .background(Color(hex: "1E1E1E"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var camerasViewModel: CamerasViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color(hex: "0D0D0D").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Account info
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACCOUNT")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(hex: "00E5CC"))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(camerasViewModel.session?.username ?? "Unknown")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Account ID: \(camerasViewModel.session?.accountId ?? 0)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SESSION")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        
                        VStack(spacing: 0) {
                            infoRow(title: "Region", value: camerasViewModel.session?.region ?? "Unknown")
                            Divider().background(Color.white.opacity(0.1))
                            infoRow(title: "Cameras", value: "\(camerasViewModel.cameras.count)")
                        }
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Logout button
                Button {
                    authViewModel.logout()
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "FF6B6B"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "FF6B6B").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func infoRow(title: String, value: String) -> some View {
        HStack {
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
    DashboardView(authViewModel: AuthViewModel())
}
