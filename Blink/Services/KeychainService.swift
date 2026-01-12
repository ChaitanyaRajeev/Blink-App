//
//  KeychainService.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import Foundation
import Security

enum KeychainError: Error {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case encodingError
    case decodingError
}

final class KeychainService {
    
    static let shared = KeychainService()
    
    private let service = "com.blink.ios"
    private let sessionKey = "blink_session"
    
    private init() {}
    
    // MARK: - Session Management
    
    func saveSession(_ session: BlinkSession) throws {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(session) else {
            throw KeychainError.encodingError
        }
        
        // Delete existing item if present
        try? deleteSession()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    func loadSession() throws -> BlinkSession {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw KeychainError.itemNotFound
        }
        
        guard let data = result as? Data else {
            throw KeychainError.decodingError
        }
        
        let decoder = JSONDecoder()
        guard let session = try? decoder.decode(BlinkSession.self, from: data) else {
            throw KeychainError.decodingError
        }
        
        return session
    }
    
    func deleteSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    func hasSession() -> Bool {
        do {
            _ = try loadSession()
            return true
        } catch {
            return false
        }
    }
}

