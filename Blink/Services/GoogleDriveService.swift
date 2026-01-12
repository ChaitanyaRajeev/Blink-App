//
//  GoogleDriveService.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/12/26.
//

import Foundation
import AuthenticationServices
import SwiftUI
import CryptoKit
import Combine

// MARK: - Google Drive Service

@MainActor
class GoogleDriveService: NSObject, ObservableObject {
    static let shared = GoogleDriveService()
    
    // OAuth Configuration
    // NOTE: Create an iOS OAuth Client ID in Google Cloud Console:
    // 1. Go to console.cloud.google.com > APIs & Services > Credentials
    // 2. Create OAuth Client ID > iOS
    // 3. Bundle ID: com.chaitanya.Blink (or your actual bundle ID)
    // 4. Copy the Client ID here (no client secret needed for iOS)
    
    private let clientId = "766591197676-at1ucjmk5l5vojen1h0p1l9jifojei3e.apps.googleusercontent.com"
    // Reversed client ID for URL scheme
    private var reversedClientId: String {
        let parts = clientId.components(separatedBy: ".")
        return parts.reversed().joined(separator: ".")
    }
    private var redirectUri: String {
        return "\(reversedClientId):/oauth2callback"
    }
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let driveUploadURL = "https://www.googleapis.com/upload/drive/v3/files"
    private let driveScope = "https://www.googleapis.com/auth/drive.file"
    
    @Published var isAuthenticated = false
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var userName: String?
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    
    private let keychainService = "com.blink.googledrive"
    
    private var authSession: ASWebAuthenticationSession?
    private var presentationContextProvider: AuthPresentationContextProvider?
    
    override init() {
        super.init()
        loadTokens()
    }
    
    // MARK: - Authentication
    
    func signIn() async throws {
        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Build auth URL
        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: driveScope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authorizationURL = components.url else {
            throw GoogleDriveError.invalidURL
        }
        
        print("🔐 Starting Google OAuth flow...")
        
        // Use ASWebAuthenticationSession with reversed client ID as callback
        let callbackScheme = self.reversedClientId
        let authCode = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GoogleDriveError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleDriveError.noAuthCode)
                    return
                }
                
                continuation.resume(returning: code)
            }
            
            self.presentationContextProvider = AuthPresentationContextProvider()
            session.presentationContextProvider = self.presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            
            self.authSession = session
            session.start()
        }
        
        print("🔐 Got auth code, exchanging for tokens...")
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: authCode, codeVerifier: codeVerifier)
        
        print("🔐 Google Drive authentication successful!")
    }
    
    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // For iOS apps with PKCE, no client_secret is needed
        let params = [
            "client_id": clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.invalidResponse
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔐 Token response: \(responseString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GoogleDriveError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        self.isAuthenticated = true
        
        saveTokens()
    }
    
    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        userName = nil
        clearTokens()
    }
    
    // MARK: - Token Management
    
    private func saveTokens() {
        if let accessToken = accessToken {
            KeychainHelper.save(key: "\(keychainService).access", value: accessToken)
        }
        if let refreshToken = refreshToken {
            KeychainHelper.save(key: "\(keychainService).refresh", value: refreshToken)
        }
        if let expiry = tokenExpiry {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: "\(keychainService).expiry")
        }
    }
    
    private func loadTokens() {
        accessToken = KeychainHelper.load(key: "\(keychainService).access")
        refreshToken = KeychainHelper.load(key: "\(keychainService).refresh")
        
        let expiryTimestamp = UserDefaults.standard.double(forKey: "\(keychainService).expiry")
        if expiryTimestamp > 0 {
            tokenExpiry = Date(timeIntervalSince1970: expiryTimestamp)
        }
        
        isAuthenticated = accessToken != nil
    }
    
    private func clearTokens() {
        KeychainHelper.delete(key: "\(keychainService).access")
        KeychainHelper.delete(key: "\(keychainService).refresh")
        UserDefaults.standard.removeObject(forKey: "\(keychainService).expiry")
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw GoogleDriveError.noRefreshToken
        }
        
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            signOut()
            throw GoogleDriveError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        
        self.accessToken = tokenResponse.accessToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        
        saveTokens()
    }
    
    private func getValidAccessToken() async throws -> String {
        if let expiry = tokenExpiry, Date() > expiry.addingTimeInterval(-60) {
            try await refreshAccessToken()
        }
        
        guard let token = accessToken else {
            throw GoogleDriveError.notAuthenticated
        }
        
        return token
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Upload to Google Drive
    
    func uploadVideo(data: Data, fileName: String, folderName: String = "Blink Clips") async throws -> String {
        isUploading = true
        uploadProgress = 0
        
        defer {
            isUploading = false
            uploadProgress = 0
        }
        
        let token = try await getValidAccessToken()
        
        // First, find or create the Blink Clips folder
        let folderId = try await findOrCreateFolder(name: folderName, token: token)
        
        print("📤 Uploading to folder: \(folderId)")
        
        // Create file metadata
        let metadata: [String: Any] = [
            "name": fileName,
            "parents": [folderId]
        ]
        
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        
        // Create multipart upload
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        // Metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n".data(using: .utf8)!)
        
        // File part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        var request = URLRequest(url: URL(string: "\(driveUploadURL)?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        print("📤 Uploading \(data.count) bytes...")
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDriveError.invalidResponse
        }
        
        if let responseString = String(data: responseData, encoding: .utf8) {
            print("📤 Upload response (\(httpResponse.statusCode)): \(responseString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GoogleDriveError.uploadFailed(httpResponse.statusCode)
        }
        
        let fileResponse = try JSONDecoder().decode(GoogleDriveFile.self, from: responseData)
        
        print("📤 Upload complete! File ID: \(fileResponse.id)")
        
        return fileResponse.id
    }
    
    private func findOrCreateFolder(name: String, token: String) async throws -> String {
        // Search for existing folder
        let query = "name='\(name)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        var searchRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)")!)
        searchRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (searchData, _) = try await URLSession.shared.data(for: searchRequest)
        let searchResult = try JSONDecoder().decode(GoogleDriveFileList.self, from: searchData)
        
        if let existingFolder = searchResult.files.first {
            return existingFolder.id
        }
        
        // Create new folder
        let folderMetadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        
        var createRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: folderMetadata)
        
        let (createData, _) = try await URLSession.shared.data(for: createRequest)
        let folder = try JSONDecoder().decode(GoogleDriveFile.self, from: createData)
        
        print("📁 Created folder: \(folder.id)")
        
        return folder.id
    }
}

// MARK: - Presentation Context Provider

class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Models

struct GoogleTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

struct GoogleDriveFile: Codable {
    let id: String
    let name: String?
    let mimeType: String?
}

struct GoogleDriveFileList: Codable {
    let files: [GoogleDriveFile]
}

// MARK: - Errors

enum GoogleDriveError: LocalizedError {
    case invalidURL
    case cancelled
    case noAuthCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case notAuthenticated
    case invalidResponse
    case uploadFailed(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authentication URL"
        case .cancelled:
            return "Sign-in was cancelled"
        case .noAuthCode:
            return "No authorization code received"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .noRefreshToken:
            return "No refresh token available"
        case .notAuthenticated:
            return "Not signed in to Google Drive"
        case .invalidResponse:
            return "Invalid response from server"
        case .uploadFailed(let code):
            return "Upload failed with status \(code)"
        }
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

