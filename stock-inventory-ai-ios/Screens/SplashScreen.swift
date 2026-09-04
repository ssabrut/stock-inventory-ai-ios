//
//  SplashScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct SplashScreen: View {
    let state: LLMService.State
    let onContinueAnyway: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Stock AI")
                .font(.title.bold())

            statusView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            VStack(spacing: 8) {
                ProgressView()
                Text("Mempersiapkan…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loading(let phase):
            loadingPhaseView(phase)
        case .ready, .generating:
            EmptyView()
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Gagal memuat model")
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Lanjutkan tanpa AI", action: onContinueAnyway)
                    .font(.caption.bold())
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func loadingPhaseView(_ phase: LLMService.LoadPhase) -> some View {
        switch phase {
        case .checkingCache:
            VStack(spacing: 8) {
                ProgressView()
                Text("Memeriksa model di cache…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloading(let fraction, let speedMBps):
            VStack(spacing: 6) {
                ProgressView(value: fraction)
                    .frame(width: 200)
                Text("Mengunduh model dari Hugging Face — \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let speedMBps {
                    Text(String(format: "%.1f MB/s", speedMBps))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        case .loadingWeights:
            VStack(spacing: 8) {
                ProgressView()
                Text("Memuat model ke memori…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SplashScreen(state: .loading(.downloading(fraction: 0.4, speedMBps: 3.2)), onContinueAnyway: {})
}
