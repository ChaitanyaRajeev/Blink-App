//
//  LoginView.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import SwiftUI
import Combine

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Stunning gradient background
                LinearGradient(
                    colors: [
                        Color(hex: "0D0D1A"),
                        Color(hex: "1A1A3E"),
                        Color(hex: "0D0D1A")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Animated orbs in background
                backgroundOrbs
                
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: geometry.size.height * 0.1)
                        
                        // Logo and Title
                        logoSection
                        
                        Spacer()
                            .frame(height: 50)
                        
                        // Login Form
                        loginForm
                        
                        Spacer()
                            .frame(height: 30)
                        
                        // Login Button
                        loginButton
                        
                        Spacer()
                            .frame(height: geometry.size.height * 0.15)
                    }
                    .padding(.horizontal, 30)
                }
            }
        }
        .alert("Error", isPresented: $authViewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authViewModel.errorMessage ?? "An error occurred")
        }
        .sheet(isPresented: $authViewModel.showOTPView) {
            OTPView(authViewModel: authViewModel)
        }
    }
    
    // MARK: - Background Orbs
    
    private var backgroundOrbs: some View {
        ZStack {
            // Cyan orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "00D9FF").opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: -100, y: -200)
                .blur(radius: 60)
            
            // Purple orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "7B2FFF").opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 250, height: 250)
                .offset(x: 120, y: 100)
                .blur(radius: 50)
            
            // Pink orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "FF2D92").opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .offset(x: -80, y: 300)
                .blur(radius: 40)
        }
    }
    
    // MARK: - Logo Section
    
    private var logoSection: some View {
        VStack(spacing: 20) {
            // Camera icon with glow
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "00D9FF").opacity(0.5), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                // Icon background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "1E1E3F"), Color(hex: "2D2D5A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                // Camera icon
                Image(systemName: "video.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Title
            VStack(spacing: 8) {
                Text("BLINK")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                Text("Home Security")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.5))
                    .tracking(4)
            }
        }
    }
    
    // MARK: - Login Form
    
    private var loginForm: some View {
        VStack(spacing: 20) {
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("EMAIL")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                    .tracking(2)
                
                HStack(spacing: 15) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(Color(hex: "00D9FF"))
                        .font(.system(size: 18))
                    
                    TextField("", text: $authViewModel.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .email)
                        .placeholder(when: authViewModel.email.isEmpty) {
                            Text("Enter your email")
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    focusedField == .email ?
                                    LinearGradient(colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")], startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 1
                                )
                        )
                )
            }
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("PASSWORD")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))
                    .tracking(2)
                
                HStack(spacing: 15) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(Color(hex: "7B2FFF"))
                        .font(.system(size: 18))
                    
                    SecureField("", text: $authViewModel.password)
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .password)
                        .placeholder(when: authViewModel.password.isEmpty) {
                            Text("Enter your password")
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    focusedField == .password ?
                                    LinearGradient(colors: [Color(hex: "7B2FFF"), Color(hex: "FF2D92")], startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 1
                                )
                        )
                )
            }
        }
    }
    
    // MARK: - Login Button
    
    private var loginButton: some View {
        Button {
            Task {
                await authViewModel.login()
            }
        } label: {
            ZStack {
                // Button background with gradient
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 56)
                    .shadow(color: Color(hex: "00D9FF").opacity(0.4), radius: 20, x: 0, y: 10)
                
                if authViewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    HStack(spacing: 12) {
                        Text("Sign In")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .disabled(authViewModel.isLoading)
        .opacity(authViewModel.isLoading ? 0.7 : 1)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Placeholder Modifier

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    LoginView(authViewModel: AuthViewModel())
}

