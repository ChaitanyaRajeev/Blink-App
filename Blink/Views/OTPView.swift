//
//  OTPView.swift
//  Blink
//
//  Created by Chaitanya Rajeev on 1/11/26.
//

import SwiftUI
import Combine

struct OTPView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @FocusState private var isCodeFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background
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
            
            // Animated orbs
            backgroundOrbs
            
            VStack(spacing: 40) {
                // Close button
                HStack {
                    Button {
                        authViewModel.cancelOTP()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Icon and Title
                VStack(spacing: 24) {
                    // Email icon with animation
                    ZStack {
                        // Pulsing ring
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "00D9FF").opacity(0.5), Color(hex: "7B2FFF").opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 120, height: 120)
                        
                        // Glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(hex: "7B2FFF").opacity(0.3), Color.clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        // Icon background
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "1E1E3F"), Color(hex: "2D2D5A")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    // Title
                    VStack(spacing: 12) {
                        Text("Verification")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Enter the 6-digit code sent to your email")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                }
                
                // OTP Input
                VStack(spacing: 24) {
                    // Code input field
                    HStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            OTPDigitBox(
                                digit: getDigit(at: index),
                                isFocused: authViewModel.otpCode.count == index
                            )
                        }
                    }
                    
                    // Hidden text field for input
                    TextField("", text: $authViewModel.otpCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isCodeFocused)
                        .opacity(0)
                        .frame(width: 1, height: 1)
                        .onChange(of: authViewModel.otpCode) { oldValue, newValue in
                            // Limit to 6 digits
                            if newValue.count > 6 {
                                authViewModel.otpCode = String(newValue.prefix(6))
                            }
                            // Remove non-digits
                            authViewModel.otpCode = newValue.filter { $0.isNumber }
                        }
                }
                .onTapGesture {
                    isCodeFocused = true
                }
                
                // Verify Button
                Button {
                    Task {
                        await authViewModel.verifyOTP()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                authViewModel.otpCode.count == 6 ?
                                LinearGradient(
                                    colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 56)
                            .shadow(
                                color: authViewModel.otpCode.count == 6 ? Color(hex: "00D9FF").opacity(0.4) : Color.clear,
                                radius: 20,
                                x: 0,
                                y: 10
                            )
                        
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                        } else {
                            HStack(spacing: 12) {
                                Text("Verify")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
                .disabled(authViewModel.otpCode.count != 6 || authViewModel.isLoading)
                .opacity(authViewModel.otpCode.count == 6 ? 1 : 0.5)
                
                Spacer()
                
                // Resend code hint
                VStack(spacing: 8) {
                    Text("Didn't receive the code?")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text("Check your spam folder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "00D9FF"))
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 30)
        }
        .onAppear {
            isCodeFocused = true
        }
        .alert("Error", isPresented: $authViewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authViewModel.errorMessage ?? "An error occurred")
        }
    }
    
    // MARK: - Background Orbs
    
    private var backgroundOrbs: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "7B2FFF").opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 100, y: -150)
                .blur(radius: 60)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "00D9FF").opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .offset(x: -100, y: 200)
                .blur(radius: 50)
        }
    }
    
    private func getDigit(at index: Int) -> String {
        guard index < authViewModel.otpCode.count else { return "" }
        let stringIndex = authViewModel.otpCode.index(authViewModel.otpCode.startIndex, offsetBy: index)
        return String(authViewModel.otpCode[stringIndex])
    }
}

// MARK: - OTP Digit Box

struct OTPDigitBox: View {
    let digit: String
    let isFocused: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .frame(width: 48, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isFocused ?
                            LinearGradient(
                                colors: [Color(hex: "00D9FF"), Color(hex: "7B2FFF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(digit.isEmpty ? 0.1 : 0.3), Color.white.opacity(digit.isEmpty ? 0.1 : 0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isFocused ? 2 : 1
                        )
                )
            
            if digit.isEmpty && isFocused {
                // Cursor animation
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: "00D9FF"))
                    .frame(width: 2, height: 24)
                    .opacity(1)
            } else {
                Text(digit)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview {
    OTPView(authViewModel: AuthViewModel())
}

