//
//  BlinkModels.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import Foundation

// MARK: - Session/Token Storage

struct BlinkSession: Codable {
    var accountId: Int
    var clientId: Int
    var authToken: String
    var refreshToken: String?
    var region: String
    var tier: String?
    var username: String
    var host: String
    var hardwareId: String?
    var expiresIn: Int?
    var tokenExpiry: Date?
    
    var isExpired: Bool {
        guard let expiry = tokenExpiry else { return false }
        return Date() > expiry
    }
    
    var baseURL: String {
        return "https://\(host)"
    }
    
    // Initializer for OAuth v2 flow
    init(accountId: Int, clientId: Int, authToken: String, refreshToken: String? = nil, region: String, tier: String?, username: String, host: String, hardwareId: String? = nil, expiresIn: Int? = nil) {
        self.accountId = accountId
        self.clientId = clientId
        self.authToken = authToken
        self.refreshToken = refreshToken
        self.region = region
        self.tier = tier
        self.username = username
        self.host = host
        self.hardwareId = hardwareId
        self.expiresIn = expiresIn
        
        if let expiresIn = expiresIn {
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
    }
}

// MARK: - Homescreen API Response (very flexible to handle various fields)

struct BlinkHomescreen: Codable {
    let networks: [BlinkNetwork]?
    let syncModules: [BlinkSyncModule]?
    let cameras: [BlinkCamera]?
    let owls: [BlinkOwlCamera]?
    let doorbells: [BlinkDoorbell]?
    let account: BlinkAccountInfo?
    
    enum CodingKeys: String, CodingKey {
        case networks
        case syncModules = "sync_modules"
        case cameras
        case owls
        case doorbells
        case account
    }
    
    // Custom decoder to handle missing fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        networks = try? container.decodeIfPresent([BlinkNetwork].self, forKey: .networks)
        syncModules = try? container.decodeIfPresent([BlinkSyncModule].self, forKey: .syncModules)
        cameras = try? container.decodeIfPresent([BlinkCamera].self, forKey: .cameras)
        owls = try? container.decodeIfPresent([BlinkOwlCamera].self, forKey: .owls)
        doorbells = try? container.decodeIfPresent([BlinkDoorbell].self, forKey: .doorbells)
        account = try? container.decodeIfPresent(BlinkAccountInfo.self, forKey: .account)
    }
    
    // Manual initializer for creating empty homescreen
    init(networks: [BlinkNetwork]?, syncModules: [BlinkSyncModule]?, cameras: [BlinkCamera]?, owls: [BlinkOwlCamera]?) {
        self.networks = networks
        self.syncModules = syncModules
        self.cameras = cameras
        self.owls = owls
        self.doorbells = nil
        self.account = nil
    }
}

struct BlinkAccountInfo: Codable {
    let id: Int?
    let emailVerified: Bool?
    let emailVerificationRequired: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case emailVerified = "email_verified"
        case emailVerificationRequired = "email_verification_required"
    }
}

struct BlinkNetwork: Codable, Identifiable {
    let id: Int
    let name: String
    let armed: Bool?
    let createdAt: String?
    let updatedAt: String?
    let lv_save: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, armed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lv_save
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        armed = try? container.decodeIfPresent(Bool.self, forKey: .armed)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        lv_save = try? container.decodeIfPresent(Int.self, forKey: .lv_save)
    }
}

struct BlinkSyncModule: Codable, Identifiable {
    let id: Int
    let networkId: Int?
    let name: String?
    let status: String?
    let serial: String?
    let fwVersion: String?
    let wifiStrength: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case networkId = "network_id"
        case name, status, serial
        case fwVersion = "fw_version"
        case wifiStrength = "wifi_strength"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        networkId = try? container.decodeIfPresent(Int.self, forKey: .networkId)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        serial = try? container.decodeIfPresent(String.self, forKey: .serial)
        fwVersion = try? container.decodeIfPresent(String.self, forKey: .fwVersion)
        wifiStrength = try? container.decodeIfPresent(Int.self, forKey: .wifiStrength)
    }
}

struct BlinkCamera: Codable, Identifiable {
    let id: Int
    let name: String
    let networkId: Int
    let status: String?
    let enabled: Bool?
    let thumbnail: String?
    let batteryState: String?
    let type: String?
    let serial: String?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case networkId = "network_id"
        case status, enabled, thumbnail
        case batteryState = "battery_state"
        case type, serial
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        networkId = try container.decode(Int.self, forKey: .networkId)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
        thumbnail = try? container.decodeIfPresent(String.self, forKey: .thumbnail)
        batteryState = try? container.decodeIfPresent(String.self, forKey: .batteryState)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        serial = try? container.decodeIfPresent(String.self, forKey: .serial)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct BlinkOwlCamera: Codable, Identifiable {
    let id: Int
    let name: String
    let networkId: Int
    let enabled: Bool?
    let thumbnail: String?
    let status: String?
    let serial: String?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case networkId = "network_id"
        case enabled, thumbnail, status, serial
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        networkId = try container.decode(Int.self, forKey: .networkId)
        enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
        thumbnail = try? container.decodeIfPresent(String.self, forKey: .thumbnail)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        serial = try? container.decodeIfPresent(String.self, forKey: .serial)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct BlinkDoorbell: Codable, Identifiable {
    let id: Int
    let name: String
    let networkId: Int
    let enabled: Bool?
    let thumbnail: String?
    let status: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case networkId = "network_id"
        case enabled, thumbnail, status
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        networkId = try container.decode(Int.self, forKey: .networkId)
        enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
        thumbnail = try? container.decodeIfPresent(String.self, forKey: .thumbnail)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
    }
}

// MARK: - Display Models

struct CameraDisplay: Identifiable {
    let id: Int
    let name: String
    let networkId: Int
    let type: CameraType
    var thumbnailURL: String?
    var status: String
    var batteryState: String?
    var isEnabled: Bool
    var lastUpdated: Date?
    
    enum CameraType: String {
        case mini = "owl"
        case indoor = "catalina"
        case outdoor = "white"
        case doorbell = "doorbell"
        case unknown = "unknown"
        
        var icon: String {
            switch self {
            case .mini: return "video.fill"
            case .indoor: return "web.camera.fill"
            case .outdoor: return "camera.fill"
            case .doorbell: return "bell.fill"
            case .unknown: return "questionmark.video.fill"
            }
        }
        
        var displayName: String {
            switch self {
            case .mini: return "Blink Mini"
            case .indoor: return "Blink Indoor"
            case .outdoor: return "Blink Outdoor"
            case .doorbell: return "Blink Doorbell"
            case .unknown: return "Blink Camera"
            }
        }
    }
    
    static func from(camera: BlinkCamera, baseURL: String) -> CameraDisplay {
        var thumbnailURL: String? = nil
        if let thumb = camera.thumbnail {
            if thumb.hasPrefix("http") {
                thumbnailURL = thumb
            } else {
                thumbnailURL = "\(baseURL)\(thumb)"
            }
        }
        
        return CameraDisplay(
            id: camera.id,
            name: camera.name,
            networkId: camera.networkId,
            type: CameraType(rawValue: camera.type ?? "") ?? .unknown,
            thumbnailURL: thumbnailURL,
            status: camera.status ?? "unknown",
            batteryState: camera.batteryState,
            isEnabled: camera.enabled ?? false
        )
    }
    
    static func from(owl: BlinkOwlCamera, baseURL: String) -> CameraDisplay {
        var thumbnailURL: String? = nil
        if let thumb = owl.thumbnail {
            if thumb.hasPrefix("http") {
                thumbnailURL = thumb
            } else {
                thumbnailURL = "\(baseURL)\(thumb)"
            }
        }
        
        return CameraDisplay(
            id: owl.id,
            name: owl.name,
            networkId: owl.networkId,
            type: .mini,
            thumbnailURL: thumbnailURL,
            status: owl.status ?? "unknown",
            batteryState: nil,
            isEnabled: owl.enabled ?? false
        )
    }
    
    static func from(doorbell: BlinkDoorbell, baseURL: String) -> CameraDisplay {
        var thumbnailURL: String? = nil
        if let thumb = doorbell.thumbnail {
            if thumb.hasPrefix("http") {
                thumbnailURL = thumb
            } else {
                thumbnailURL = "\(baseURL)\(thumb)"
            }
        }
        
        return CameraDisplay(
            id: doorbell.id,
            name: doorbell.name,
            networkId: doorbell.networkId,
            type: .doorbell,
            thumbnailURL: thumbnailURL,
            status: doorbell.status ?? "unknown",
            batteryState: nil,
            isEnabled: doorbell.enabled ?? false
        )
    }
}

// MARK: - API Response Models

struct BlinkCommandResponse: Codable {
    let id: Int?
    let message: String?
}

// MARK: - Video/Media Models

struct BlinkMediaResponse: Codable {
    let limit: Int?
    let purgeId: Int?
    let refreshCount: Int?
    let media: [BlinkVideoClip]?
    
    enum CodingKeys: String, CodingKey {
        case limit
        case purgeId = "purge_id"
        case refreshCount = "refresh_count"
        case media
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try? container.decodeIfPresent(Int.self, forKey: .limit)
        purgeId = try? container.decodeIfPresent(Int.self, forKey: .purgeId)
        refreshCount = try? container.decodeIfPresent(Int.self, forKey: .refreshCount)
        media = try? container.decodeIfPresent([BlinkVideoClip].self, forKey: .media)
    }
}

struct BlinkVideoClip: Codable, Identifiable {
    let id: Int
    let createdAt: String?
    let updatedAt: String?
    let deleted: Bool?
    let device: String?
    let deviceId: Int?
    let deviceName: String?
    let networkId: Int?
    let networkName: String?
    let type: String?
    let source: String?
    let watched: Bool?
    let partial: Bool?
    let thumbnail: String?
    let media: String?
    let additionalDevices: [String]?
    let timeZone: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deleted, device
        case deviceId = "device_id"
        case deviceName = "device_name"
        case networkId = "network_id"
        case networkName = "network_name"
        case type, source, watched, partial, thumbnail, media
        case additionalDevices = "additional_devices"
        case timeZone = "time_zone"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        deleted = try? container.decodeIfPresent(Bool.self, forKey: .deleted)
        device = try? container.decodeIfPresent(String.self, forKey: .device)
        deviceId = try? container.decodeIfPresent(Int.self, forKey: .deviceId)
        deviceName = try? container.decodeIfPresent(String.self, forKey: .deviceName)
        networkId = try? container.decodeIfPresent(Int.self, forKey: .networkId)
        networkName = try? container.decodeIfPresent(String.self, forKey: .networkName)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        watched = try? container.decodeIfPresent(Bool.self, forKey: .watched)
        partial = try? container.decodeIfPresent(Bool.self, forKey: .partial)
        thumbnail = try? container.decodeIfPresent(String.self, forKey: .thumbnail)
        media = try? container.decodeIfPresent(String.self, forKey: .media)
        additionalDevices = try? container.decodeIfPresent([String].self, forKey: .additionalDevices)
        timeZone = try? container.decodeIfPresent(String.self, forKey: .timeZone)
    }
    
    var formattedDate: String {
        guard let dateString = createdAt else { return "Unknown" }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy • h:mm a"
            return formatter.string(from: date)
        }
        
        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy • h:mm a"
            return formatter.string(from: date)
        }
        
        return dateString
    }
    
    var triggerType: String {
        switch source?.lowercased() {
        case "pir": return "Motion Detected"
        case "button": return "Button Press"
        case "snapshot": return "Snapshot"
        default: return source?.capitalized ?? "Recording"
        }
    }
}
