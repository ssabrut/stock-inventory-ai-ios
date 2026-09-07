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
    /// Guards against re-triggering auto-listen on every refresh while a
    /// Siri-sourced session stays active (each item append re-fires the
    /// Darwin notification), so the mic only auto-starts once per session.
    @State private var hasAutoStartedForSession = false

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
            voice.onSegment = { segment in
                handleSegment(segment)
            }
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
            // Pauses the mic only — items stay pending in the card so the
            // user can still review/confirm. SiriSessionState.end() (which
            // clears items) is reserved for an explicit confirm/cancel.
            voice.stopListening()
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

                if voice.state == .listening {
                    Text("Item ditambahkan. Sebutkan item berikutnya, atau ucapkan selesai.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    /// Called once per pause-detected segment from VoiceStockService.onSegment.
    /// First checks whether the segment is a free-form done-signal ("selesai",
    /// "okay done", "udah segitu aja", ...) via the LLM rather than a fixed
    /// word list, mirroring Siri's own "any more items?" gate; otherwise
    /// treats it as another item to parse and add to the session.
    private func handleSegment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sessionSource: SiriSessionState.Source = SiriSessionState.source

        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                if try await llm.isDoneIntent(trimmed) {
                    voice.stopListening()
                    return
                }
                let entry = try await llm.parseStockPhrase(trimmed)
                let dto = PendingStockItemDTO(itemName: entry.itemName, quantity: entry.quantity, unit: entry.unit)
                SiriSessionState.append(dto, source: sessionSource)
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

        guard isSessionActive else {
            hasAutoStartedForSession = false
            return
        }

        guard SiriSessionState.source == .siri else { return }

        withAnimation { isCardExpanded = true }

        guard !hasAutoStartedForSession, voice.state != .listening else { return }
        hasAutoStartedForSession = true
        errorMessage = nil
        do {
            try voice.startListening()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground).ignoresSafeArea()
        StockSessionOverlay(llm: LLMService())
    }
}
