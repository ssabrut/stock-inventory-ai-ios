//
//  StockSessionOverlay.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Floating bottom-right mic FAB + expandable session card, mounted once
/// over the whole app (see ContentView). Mirrors two entry points into the
/// same shared session (SiriSessionState):
///   - Siri: AddStockIntent runs out-of-process and writes each parsed item
///     to SiriSessionState as it goes; this view observes that via Darwin
///     notifications and pops the card open automatically.
///   - Manual: tapping the FAB starts an in-app SFSpeechRecognizer session
///     (VoiceStockService) and writes into the same shared state, so both
///     paths render through one card and one confirm/StockStore.add call.
struct StockSessionOverlay: View {
    let llm: LLMService

    @State private var voice = VoiceStockService()
    @State private var items: [PendingStockItemDTO] = []
    @State private var isSessionActive = false
    @State private var isCardExpanded = false
    @State private var isParsing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if isCardExpanded && (isSessionActive || !items.isEmpty) {
                sessionCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            fab
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(duration: 0.3), value: isCardExpanded)
        .animation(.spring(duration: 0.3), value: items)
        .task {
            _ = await voice.requestAuthorization()
            refreshFromSharedState()
            SiriSessionState.observe {
                refreshFromSharedState()
            }
        }
    }

    // MARK: - FAB

    private var fab: some View {
        Button(action: handleFABTap) {
            ZStack {
                Circle()
                    .fill(voice.state == .listening ? Color.red : Color.accentColor)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                    .scaleEffect(1 + voice.audioLevel * 0.15)
                    .animation(.easeOut(duration: 0.1), value: voice.audioLevel)

                if isSessionActive && SiriSessionState.source == .siri && voice.state != .listening {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: voice.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                if !items.isEmpty {
                    badge
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(voice.state == .denied)
    }

    private var badge: some View {
        Text("\(items.count)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(Color.red))
            .offset(x: 20, y: -20)
    }

    private func handleFABTap() {
        errorMessage = nil
        if voice.state == .listening {
            let text = voice.transcript
            voice.stopListening()
            parseAndAppend(text)
            return
        }

        withAnimation { isCardExpanded = true }

        if !isSessionActive {
            SiriSessionState.begin(source: .manual)
            isSessionActive = true
        }

        do {
            try voice.startListening()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session card

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(SiriSessionState.source == .siri ? "Sesi Siri" : "Sesi Suara")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation { isCardExpanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if voice.state == .listening {
                listeningIndicator
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isParsing {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Memproses…").font(.caption).foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                Text("Belum ada item. Ucapkan item stok, misal \"50 gram ayam\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        HStack {
                            Text("• \(item.quantity) \(item.unit) \(item.itemName)")
                                .font(.subheadline)
                            Spacer()
                            Button {
                                removeItem(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: confirmAndSave) {
                    Text("Tambahkan \(items.count) Item ke Stok")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
    }

    private var listeningIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(for: i))
            }
            Spacer()
            Text(voice.transcript.isEmpty ? "Mendengarkan…" : voice.transcript)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.1), value: voice.audioLevel)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let center = 4.5
        let distance = abs(Double(index) - center) / center
        let falloff = 1 - distance * 0.6
        return 3 + CGFloat(voice.audioLevel) * 18 * falloff
    }

    // MARK: - Actions

    private func parseAndAppend(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let entry = try await llm.parseStockPhrase(trimmed)
                let dto = PendingStockItemDTO(itemName: entry.itemName, quantity: entry.quantity, unit: entry.unit)
                SiriSessionState.append(dto, source: .manual)
                refreshFromSharedState()
            } catch {
                errorMessage = "Tidak bisa memahami: \"\(trimmed)\""
            }
        }
    }

    private func removeItem(_ item: PendingStockItemDTO) {
        SiriSessionState.remove(id: item.id)
        refreshFromSharedState()
    }

    private func confirmAndSave() {
        StockStore.add(items.map { (itemName: $0.itemName, quantity: $0.quantity, unit: $0.unit) })
        SiriSessionState.end()
        refreshFromSharedState()
        withAnimation { isCardExpanded = false }
    }

    private func refreshFromSharedState() {
        items = SiriSessionState.items
        isSessionActive = SiriSessionState.isActive
        if isSessionActive && SiriSessionState.source == .siri {
            withAnimation { isCardExpanded = true }
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        StockSessionOverlay(llm: LLMService())
    }
}
