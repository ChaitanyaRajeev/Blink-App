//
//  BlinkAPIService.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import Foundation
import Combine
import CryptoKit

enum BlinkAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case authRequired
    case twoFactorRequired
    case unauthorized
    case serverError(Int, String?)
    case decodingError(Error)
    case oauthFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from server"
        case .authRequired: return "Authentication required"
        case .twoFactorRequired: return "Two-factor authentication required"
        case .unauthorized: return "Invalid credentials"
        case .serverError(let code, let message): return "Server error (\(code)): \(message ?? "Unknown")"
        case .decodingError(let error): return "Failed to parse response: \(error.localizedDescription)"
        case .oauthFailed(let reason): return "OAuth failed: \(reason)"
        }
    }
}

@MainActor
final class BlinkAPIService: ObservableObject {
    
    static let shared = BlinkAPIService()
    
    @Published var session: BlinkSession?
    @Published var isAuthenticated = false
    @Published var requires2FA = false
    
    // OAuth 2.0 Constants (matching blinkpy)
    private let oauthBaseURL = "https://api.oauth.blink.com"
    private let blinkURL = "immedia-semi.com"
    private let defaultURL = "rest-prod.immedia-semi.com"
    
    private let oauthClientId = "ios"
    private let oauthScope = "client"
    private let oauthRedirectURI = "immedia-blink://applinks.blink.com/signin/callback"
    
    // User agents (matching blinkpy)
    private let oauthUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1"
    private let oauthTokenUserAgent = "Blink/2511191620 CFNetwork/3860.200.71 Darwin/25.1.0"
    
    // Device ID
    private var hardwareId: String
    
    // OAuth state for 2FA flow
    private var oauthCodeVerifier: String?
    private var oauthCSRFToken: String?
    private var pendingEmail: String?
    private var pendingPassword: String?
    
    // Shared URL session with cookie support
    private var urlSession: URLSession
    
    private init() {
        // Generate hardware ID (UUID)
        if let savedHardwareId = UserDefaults.standard.string(forKey: "BlinkHardwareId") {
            self.hardwareId = savedHardwareId
        } else {
            self.hardwareId = UUID().uuidString.uppercased()
            UserDefaults.standard.set(self.hardwareId, forKey: "BlinkHardwareId")
        }
        
        // Create URL session with cookie storage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        self.urlSession = URLSession(configuration: config)
        
        // Try to load existing session
        if let savedSession = try? KeychainService.shared.loadSession() {
            self.session = savedSession
            self.isAuthenticated = true
        }
    }
    
    private var baseURL: String {
        if let session = session {
            return session.baseURL
        }
        return "https://\(defaultURL)"
    }
    
    // MARK: - PKCE Helper Functions
    
    private func generatePKCEPair() -> (verifier: String, challenge: String) {
        // Generate random 32 bytes for code verifier
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        
        // Base64 URL encode the verifier
        let verifier = Data(randomBytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // SHA256 hash of verifier, then base64 URL encode for challenge
        let verifierData = Data(verifier.utf8)
        let hash = SHA256.hash(data: verifierData)
        let challenge = Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return (verifier, challenge)
    }
    
    // MARK: - OAuth 2.0 + PKCE Authentication Flow
    
    func login(email: String, password: String) async throws {
        // Clear any stale OAuth cookies before starting fresh login
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: oauthBaseURL)!) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        
        // Store credentials for potential 2FA
        pendingEmail = email
        pendingPassword = password
        
        // Step 1: Generate PKCE pair
        let pkce = generatePKCEPair()
        oauthCodeVerifier = pkce.verifier
        
        print("🔐 Starting OAuth login flow...")
        
        // Step 2: Authorization request
        let authSuccess = try await oauthAuthorizeRequest(codeChallenge: pkce.challenge)
        if !authSuccess {
            throw BlinkAPIError.oauthFailed("Authorization request failed")
        }
        print("✅ Authorization request successful")
        
        // Step 3: Get signin page and CSRF token
        guard let csrfToken = try await oauthGetSigninPage() else {
            throw BlinkAPIError.oauthFailed("Failed to get CSRF token")
        }
        oauthCSRFToken = csrfToken
        print("✅ Got CSRF token")
        
        // Step 4: Submit credentials
        let signinResult = try await oauthSignin(email: email, password: password, csrfToken: csrfToken)
        print("📝 Signin result: \(signinResult)")
        
        if signinResult == "2FA_REQUIRED" {
            requires2FA = true
            throw BlinkAPIError.twoFactorRequired
        } else if signinResult != "SUCCESS" {
            throw BlinkAPIError.unauthorized
        }
        
        // Step 5: Get authorization code
        guard let code = try await oauthGetAuthorizationCode() else {
            throw BlinkAPIError.oauthFailed("Failed to get authorization code")
        }
        print("✅ Got authorization code")
        
        // Step 6: Exchange code for token
        guard let tokenData = try await oauthExchangeCodeForToken(code: code, codeVerifier: pkce.verifier) else {
            throw BlinkAPIError.oauthFailed("Failed to exchange code for token")
        }
        print("✅ Got access token")
        
        // Process token and get tier info
        try await processTokenData(tokenData, email: email)
    }
    
    func verify2FA(pin: String) async throws {
        guard let csrfToken = oauthCSRFToken,
              let codeVerifier = oauthCodeVerifier,
              let email = pendingEmail else {
            throw BlinkAPIError.authRequired
        }
        
        print("🔐 Verifying 2FA...")
        
        // Verify 2FA code
        let verified = try await oauthVerify2FA(csrfToken: csrfToken, twofaCode: pin)
        if !verified {
            throw BlinkAPIError.unauthorized
        }
        print("✅ 2FA verified")
        
        // Get authorization code
        guard let code = try await oauthGetAuthorizationCode() else {
            throw BlinkAPIError.oauthFailed("Failed to get authorization code after 2FA")
        }
        print("✅ Got authorization code")
        
        // Exchange code for token
        guard let tokenData = try await oauthExchangeCodeForToken(code: code, codeVerifier: codeVerifier) else {
            throw BlinkAPIError.oauthFailed("Failed to exchange code for token after 2FA")
        }
        print("✅ Got access token")
        
        // Process token and get tier info
        try await processTokenData(tokenData, email: email)
        
        requires2FA = false
        clearOAuthState()
    }
    
    // MARK: - OAuth API Calls
    
    private func oauthAuthorizeRequest(codeChallenge: String) async throws -> Bool {
        var components = URLComponents(string: "\(oauthBaseURL)/oauth/v2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "app_brand", value: "blink"),
            URLQueryItem(name: "app_version", value: "50.1"),
            URLQueryItem(name: "client_id", value: oauthClientId),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "device_brand", value: "Apple"),
            URLQueryItem(name: "device_model", value: "iPhone16,1"),
            URLQueryItem(name: "device_os_version", value: "26.1"),
            URLQueryItem(name: "hardware_id", value: hardwareId),
            URLQueryItem(name: "redirect_uri", value: oauthRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: oauthScope)
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(oauthUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        print("📱 Authorize response: \(httpResponse.statusCode)")
        return httpResponse.statusCode == 200
    }
    
    private func oauthGetSigninPage() async throws -> String? {
        let url = URL(string: "\(oauthBaseURL)/oauth/v2/signin")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(oauthUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // Extract CSRF token from oauth-args script tag
        // Looking for: <script id="oauth-args" type="application/json">{"csrf-token":"..."}</script>
        if let range = html.range(of: #"<script id="oauth-args" type="application/json">"#),
           let endRange = html.range(of: "</script>", range: range.upperBound..<html.endIndex) {
            let jsonString = String(html[range.upperBound..<endRange.lowerBound])
            
            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let csrfToken = json["csrf-token"] as? String {
                return csrfToken
            }
        }
        
        return nil
    }
    
    // Properly encode form data (handles special chars like @, +, &, etc.)
    private func formURLEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
    
    private func oauthSignin(email: String, password: String, csrfToken: String) async throws -> String {
        let url = URL(string: "\(oauthBaseURL)/oauth/v2/signin")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(oauthUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://api.oauth.blink.com", forHTTPHeaderField: "Origin")
        request.setValue("\(oauthBaseURL)/oauth/v2/signin", forHTTPHeaderField: "Referer")
        
        // Use proper form URL encoding for all values
        let bodyString = "username=\(formURLEncode(email))&password=\(formURLEncode(password))&csrf-token=\(formURLEncode(csrfToken))"
        request.httpBody = bodyString.data(using: .utf8)
        
        // Don't follow redirects automatically - we need to check status
        let delegate = NoRedirectDelegate()
        let noRedirectSession = URLSession(configuration: urlSession.configuration, delegate: delegate, delegateQueue: nil)
        
        let (data, response) = try await noRedirectSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return "FAILED"
        }
        
        print("📱 Signin response: \(httpResponse.statusCode)")
        
        // Debug: print response body on failure
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            if let responseBody = String(data: data, encoding: .utf8) {
                print("📱 Signin error body: \(responseBody)")
            }
        }
        
        if httpResponse.statusCode == 412 {
            return "2FA_REQUIRED"
        } else if [301, 302, 303, 307, 308].contains(httpResponse.statusCode) {
            return "SUCCESS"
        }
        
        return "FAILED"
    }
    
    private func oauthVerify2FA(csrfToken: String, twofaCode: String) async throws -> Bool {
        let url = URL(string: "\(oauthBaseURL)/oauth/v2/2fa/verify")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(oauthUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://api.oauth.blink.com", forHTTPHeaderField: "Origin")
        request.setValue("\(oauthBaseURL)/oauth/v2/signin", forHTTPHeaderField: "Referer")
        
        // Use proper form URL encoding
        let bodyString = "2fa_code=\(formURLEncode(twofaCode))&csrf-token=\(formURLEncode(csrfToken))&remember_me=false"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        print("📱 2FA verify response: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 201 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status == "auth-completed"
            }
        }
        
        // Debug on failure
        if let responseBody = String(data: data, encoding: .utf8) {
            print("📱 2FA error body: \(responseBody)")
        }
        
        return false
    }
    
    private func oauthGetAuthorizationCode() async throws -> String? {
        let url = URL(string: "\(oauthBaseURL)/oauth/v2/authorize")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(oauthUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("\(oauthBaseURL)/oauth/v2/signin", forHTTPHeaderField: "Referer")
        
        // Don't follow redirects - we need to extract code from Location header
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: urlSession.configuration, delegate: delegate, delegateQueue: nil)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        
        print("📱 Get auth code response: \(httpResponse.statusCode)")
        
        if [301, 302, 303, 307, 308].contains(httpResponse.statusCode),
           let location = httpResponse.value(forHTTPHeaderField: "Location") {
            
            // Extract code from URL: ...?code=XXX&state=YYY
            if let components = URLComponents(string: location),
               let codeItem = components.queryItems?.first(where: { $0.name == "code" }) {
                return codeItem.value
            }
        }
        
        return nil
    }
    
    private func oauthExchangeCodeForToken(code: String, codeVerifier: String) async throws -> [String: Any]? {
        let url = URL(string: "\(oauthBaseURL)/oauth/token")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(oauthTokenUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        let bodyParams = [
            "app_brand": "blink",
            "client_id": oauthClientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "hardware_id": hardwareId,
            "redirect_uri": oauthRedirectURI,
            "scope": oauthScope
        ]
        
        // Use proper form URL encoding
        let bodyString = bodyParams.map { "\($0.key)=\(formURLEncode($0.value))" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        
        print("📱 Token exchange response: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 200 {
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        
        // Debug on failure
        if let responseBody = String(data: data, encoding: .utf8) {
            print("📱 Token exchange error: \(responseBody)")
        }
        
        return nil
    }
    
    private func processTokenData(_ tokenData: [String: Any], email: String) async throws {
        guard let accessToken = tokenData["access_token"] as? String,
              let refreshToken = tokenData["refresh_token"] as? String else {
            throw BlinkAPIError.oauthFailed("Invalid token response")
        }
        
        let expiresIn = tokenData["expires_in"] as? Int ?? 3600
        
        // Get tier info to get region and account ID
        let tierInfo = try await getTierInfo(accessToken: accessToken)
        
        guard let tier = tierInfo["tier"] as? String,
              let accountId = tierInfo["account_id"] as? Int else {
            throw BlinkAPIError.oauthFailed("Failed to get tier info")
        }
        
        let host = "rest-\(tier).\(blinkURL)"
        
        let newSession = BlinkSession(
            accountId: accountId,
            clientId: 0,  // Not used in OAuth v2
            authToken: accessToken,
            refreshToken: refreshToken,
            region: tier,
            tier: tier,
            username: email,
            host: host,
            hardwareId: hardwareId,
            expiresIn: expiresIn
        )
        
        // Save to keychain
        try KeychainService.shared.saveSession(newSession)
        
        session = newSession
        isAuthenticated = true
        
        print("✅ Login complete! Account ID: \(accountId), Region: \(tier)")
    }
    
    private func getTierInfo(accessToken: String) async throws -> [String: Any] {
        let url = URL(string: "https://\(defaultURL)/api/v1/users/tier_info")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("27.0ANDROID_28373244", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BlinkAPIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, "Failed to get tier info")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BlinkAPIError.invalidResponse
        }
        
        return json
    }
    
    private func clearOAuthState() {
        oauthCodeVerifier = nil
        oauthCSRFToken = nil
        pendingEmail = nil
        pendingPassword = nil
    }
    
    func logout() {
        try? KeychainService.shared.deleteSession()
        session = nil
        isAuthenticated = false
        requires2FA = false
        clearOAuthState()
    }
    
    // MARK: - Camera APIs
    
    private func authorizedHeader() -> [String: String] {
        guard let session = session else { return [:] }
        return [
            "Authorization": "Bearer \(session.authToken)",
            "Content-Type": "application/json"
        ]
    }
    
    func getHomescreen() async throws -> BlinkHomescreen {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        let url = URL(string: "\(session.baseURL)/api/v3/accounts/\(session.accountId)/homescreen")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlinkAPIError.invalidResponse
        }
        
        // Debug - print full response
        if let responseString = String(data: data, encoding: .utf8) {
            print("📱 Homescreen Response (\(httpResponse.statusCode)):")
            print(responseString)
        }
        
        switch httpResponse.statusCode {
        case 200:
            do {
                // Our models handle snake_case via custom CodingKeys
                return try JSONDecoder().decode(BlinkHomescreen.self, from: data)
            } catch {
                print("📱 Decode error: \(error)")
                // Return empty homescreen on decode failure
                return BlinkHomescreen(networks: [], syncModules: [], cameras: [], owls: [])
            }
        case 401:
            logout()
            throw BlinkAPIError.unauthorized
        default:
            throw BlinkAPIError.serverError(httpResponse.statusCode, nil)
        }
    }
    
    func getThumbnail(url thumbnailPath: String) async throws -> Data {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        let fullURL: URL
        if thumbnailPath.hasPrefix("http") {
            fullURL = URL(string: thumbnailPath)!
        } else {
            fullURL = URL(string: "\(session.baseURL)\(thumbnailPath)")!
        }
        
        var request = URLRequest(url: fullURL)
        request.httpMethod = "GET"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BlinkAPIError.invalidResponse
        }
        
        return data
    }
    
    func requestSnapshot(networkId: Int, cameraId: Int) async throws {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        let url = URL(string: "\(session.baseURL)/network/\(networkId)/camera/\(cameraId)/thumbnail")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlinkAPIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw BlinkAPIError.serverError(httpResponse.statusCode, nil)
        }
    }
    
    func requestRecording(networkId: Int, cameraId: Int) async throws {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        let url = URL(string: "\(session.baseURL)/network/\(networkId)/camera/\(cameraId)/clip")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlinkAPIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw BlinkAPIError.serverError(httpResponse.statusCode, nil)
        }
    }
    
    // For Blink Mini cameras (owls)
    func requestOwlSnapshot(networkId: Int, cameraId: Int) async throws {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        let url = URL(string: "\(session.baseURL)/api/v1/accounts/\(session.accountId)/networks/\(networkId)/owls/\(cameraId)/thumbnail")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlinkAPIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw BlinkAPIError.serverError(httpResponse.statusCode, nil)
        }
    }
    
    // MARK: - Video/Clips APIs
    
    func getVideos(since: Date? = nil, page: Int = 0) async throws -> BlinkMediaResponse {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        // Default to 7 days ago if no date specified
        let sinceDate = since ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let timestamp = ISO8601DateFormatter().string(from: sinceDate)
        
        let url = URL(string: "\(session.baseURL)/api/v1/accounts/\(session.accountId)/media/changed?since=\(timestamp)&page=\(page)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlinkAPIError.invalidResponse
        }
        
        // Debug
        if let responseString = String(data: data, encoding: .utf8) {
            print("📹 Videos Response (\(httpResponse.statusCode)): \(responseString.prefix(1000))...")
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(BlinkMediaResponse.self, from: data)
        case 401:
            logout()
            throw BlinkAPIError.unauthorized
        default:
            throw BlinkAPIError.serverError(httpResponse.statusCode, nil)
        }
    }
    
    func getVideoData(url videoPath: String) async throws -> Data {
        guard let session = session else {
            throw BlinkAPIError.authRequired
        }
        
        let fullURL: URL
        if videoPath.hasPrefix("http") {
            fullURL = URL(string: videoPath)!
        } else {
            fullURL = URL(string: "\(session.baseURL)\(videoPath)")!
        }
        
        var request = URLRequest(url: fullURL)
        request.httpMethod = "GET"
        for (key, value) in authorizedHeader() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BlinkAPIError.invalidResponse
        }
        
        return data
    }
}

// Helper class to prevent automatic redirect following
private class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Return nil to prevent redirect
        completionHandler(nil)
    }
}
