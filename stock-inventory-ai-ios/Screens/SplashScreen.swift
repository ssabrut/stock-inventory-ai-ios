//
//  SplashScreen.swift
//  stock-inventory-ai-ios
//
//  Created by Michael Eko on 28/09/26.
//

import SwiftUI

struct SplashScreen: View {
    let loadState: ChatModel.LoadState
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Stock Inventory AI")
                .font(.title.bold())
            
            if case .failed(let message) = loadState {
                Text("Gagal menyiapkan AI: \(message)")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Lanjutkan tanpa AI", action: onContinue)
                    .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                Text("Menyiapkan AI untuk pertama kali…\nHanya sekali, mohon tunggu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        // Keep the screen awake so the phone doesn't lock mid-preparation.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
