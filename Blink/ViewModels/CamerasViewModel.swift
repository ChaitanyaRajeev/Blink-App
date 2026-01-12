//
//  CamerasViewModel.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class CamerasViewModel: ObservableObject {
    
    @Published var cameras: [CameraDisplay] = []
    @Published var networks: [BlinkNetwork] = []
    @Published var syncModules: [BlinkSyncModule] = []
    @Published var isLoading = false
    @Published var isArming = false
    @Published var errorMessage: String?
    @Published var thumbnails: [Int: Data] = [:]
    
    private let apiService = BlinkAPIService.shared
    
    var isArmed: Bool {
        // Return true if any network is armed
        networks.first?.armed ?? false
    }
    
    var session: BlinkSession? {
        apiService.session
    }
    
    func loadCameras() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let homescreen = try await apiService.getHomescreen()
            
            var allCameras: [CameraDisplay] = []
            let baseURL = session?.baseURL ?? ""
            
            // Add regular cameras
            if let cameras = homescreen.cameras {
                print("📹 Found \(cameras.count) regular cameras")
                allCameras.append(contentsOf: cameras.map { CameraDisplay.from(camera: $0, baseURL: baseURL) })
            }
            
            // Add Blink Mini (owl) cameras
            if let owls = homescreen.owls {
                print("📹 Found \(owls.count) Blink Mini cameras")
                allCameras.append(contentsOf: owls.map { CameraDisplay.from(owl: $0, baseURL: baseURL) })
            }
            
            // Add doorbells
            if let doorbells = homescreen.doorbells {
                print("📹 Found \(doorbells.count) doorbells")
                allCameras.append(contentsOf: doorbells.map { CameraDisplay.from(doorbell: $0, baseURL: baseURL) })
            }
            
            print("📹 Total cameras: \(allCameras.count)")
            self.cameras = allCameras
            self.networks = homescreen.networks ?? []
            self.syncModules = homescreen.syncModules ?? []
            
            print("📡 Sync modules: \(syncModules.count)")
            print("🔒 Armed: \(isArmed)")
            
            // Load thumbnails
            await loadAllThumbnails()
            
        } catch BlinkAPIError.unauthorized {
            errorMessage = "Session expired. Please login again."
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadAllThumbnails() async {
        for camera in cameras {
            if let thumbnailURL = camera.thumbnailURL {
                await loadThumbnail(for: camera.id, url: thumbnailURL)
            }
        }
    }
    
    func loadThumbnail(for cameraId: Int, url: String) async {
        do {
            let data = try await apiService.getThumbnail(url: url)
            thumbnails[cameraId] = data
        } catch {
            print("Failed to load thumbnail for camera \(cameraId): \(error)")
        }
    }
    
    func refreshSnapshot(for camera: CameraDisplay) async {
        do {
            if camera.type == .mini {
                try await apiService.requestOwlSnapshot(networkId: camera.networkId, cameraId: camera.id)
            } else {
                try await apiService.requestSnapshot(networkId: camera.networkId, cameraId: camera.id)
            }
            
            // Wait for snapshot to be processed
            try await Task.sleep(nanoseconds: 3_000_000_000)
            
            // Reload cameras to get new thumbnail URL
            await loadCameras()
        } catch {
            print("Failed to refresh snapshot: \(error)")
        }
    }
    
    func requestRecording(for camera: CameraDisplay) async {
        do {
            try await apiService.requestRecording(networkId: camera.networkId, cameraId: camera.id)
        } catch {
            print("Failed to request recording: \(error)")
        }
    }
    
    func toggleArm() async {
        guard let network = networks.first else { return }
        
        isArming = true
        
        do {
            if isArmed {
                try await apiService.disarmNetwork(networkId: network.id)
            } else {
                try await apiService.armNetwork(networkId: network.id)
            }
            
            // Refresh to get updated status
            await loadCameras()
        } catch {
            errorMessage = "Failed to \(isArmed ? "disarm" : "arm"): \(error.localizedDescription)"
        }
        
        isArming = false
    }
}

