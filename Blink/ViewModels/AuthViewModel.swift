//
//  AuthViewModel.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    
    @Published var email = ""
    @Published var password = ""
    @Published var otpCode = ""
    
    @Published var isLoading = false
    @Published var showOTPView = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    private let apiService = BlinkAPIService.shared
    
    var isAuthenticated: Bool {
        apiService.isAuthenticated
    }
    
    func login() async {
        guard !email.isEmpty, !password.isEmpty else {
            showErrorMessage("Please enter email and password")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await apiService.login(email: email, password: password)
            // Login successful without 2FA
            clearFields()
        } catch BlinkAPIError.twoFactorRequired {
            // 2FA required - show OTP view
            showOTPView = true
        } catch BlinkAPIError.unauthorized {
            showErrorMessage("Invalid email or password")
        } catch {
            showErrorMessage(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    func verifyOTP() async {
        guard !otpCode.isEmpty else {
            showErrorMessage("Please enter the verification code")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await apiService.verify2FA(pin: otpCode)
            // 2FA successful
            showOTPView = false
            clearFields()
        } catch BlinkAPIError.unauthorized {
            showErrorMessage("Invalid verification code")
        } catch {
            showErrorMessage(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    func logout() {
        apiService.logout()
        clearFields()
        showOTPView = false
    }
    
    func cancelOTP() {
        showOTPView = false
        otpCode = ""
        apiService.logout()
    }
    
    private func clearFields() {
        email = ""
        password = ""
        otpCode = ""
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}

