//
//  StockSessionOverlay.swift
//  stock-inventory-ai-ios
//

import SwiftUI

/// Floating bottom-right mic FAB + expandable session card, mounted once
/// over the whole app (see ContentView). Mirrors two entry points into the
/// same shared session (SiriSessionState):
///   - Siri: AddStockIntent runs out-of-process and marks the session active
///     in SiriSessionState; this view observes that via Darwin notifications
///     and pops the card open + starts listening automatically.
///   - Manual: tapping the FAB starts an in-app SFSpeechRecognizer session
///     (VoiceStockService) and writes into the same shared state, so both
///     paths render through one card and one confirm/StockStore.add call.
///
/// Each spoken segment is routed through a small state machine (SessionPhase)
/// instead of being appended straight to the session: a parsed item is held
/// pending until the user confirms it's correct, then asked whether to add
/// another before finally reaching the review-and-save summary — mirroring
/// Siri's own "is that right? anything else?" conversational shape.
struct StockSessionOverlay: View {
    let llm: LLMService

    /// Where the current voice session is in its per-item confirm loop.
    private enum SessionPhase: Equatable {
        /// Listening for a new item to be spoken (or a done-signal).
        case listeningForItem
        /// An item was parsed; next segment is classified as confirm/reject.
        case confirmingItem(PendingStockItemDTO)
        /// The item was rejected; next segment replaces it entirely.
        case awaitingCorrection
        /// The item was confirmed; next segment is classified as continue/stop.
        case askingContinue
        /// No more items; review list is ready for the final save.
        case finalSummary
    }

    @State private var voice = VoiceStockService()
    @State private var items: [PendingStockItemDTO] = []
    @State private var isSessionActive = false
    @State private var isCardExpanded = false
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var phase: SessionPhase = .listeningForItem
    /// Guards against re-triggering auto-listen on every refresh while a
    /// Siri-sourced session stays active (each item append re-fires the
    /// Darwin notification), so the mic only auto-starts once per session.
    @State private var hasAutoStartedForSession = false

    private var isCardShown: Bool {
        isCardExpanded && (isSessionActive || !items.isEmpty)
    }

    var body: some View {
        ZStack {
            if isCardShown {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation { isCardExpanded = false }
                    }
            }

            VStack(alignment: .trailing, spacing: 12) {
                if isCardShown {
                    sessionCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                fab
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
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
            phase = .listeningForItem
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

            phasePrompt

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        HStack {
                            Text("• \(item.quantity) \(item.unit) \(item.itemName)")
                                .font(.subheadline)
                            Spacer()
                            if phase == .finalSummary {
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
                }
            }

            if phase == .finalSummary {
                Button(action: confirmAndSave) {
                    Text(items.isEmpty ? "Tidak Ada Item" : "Tambahkan \(items.count) Item ke Stok")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty)
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

    @ViewBuilder
    private var phasePrompt: some View {
        switch phase {
        case .listeningForItem:
            if items.isEmpty {
                Text("Belum ada item. Ucapkan item stok, misal \"50 gram ayam\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sebutkan item berikutnya, atau ucapkan selesai.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .confirmingItem(let entry):
            Text("\(entry.quantity) \(entry.unit) \(entry.itemName) — apa sudah benar?")
                .font(.subheadline)
        case .awaitingCorrection:
            Text("Ucapkan item yang benar.")
                .font(.subheadline)
        case .askingContinue:
            Text("Mau tambah item lagi?")
                .font(.subheadline)
        case .finalSummary:
            Text(items.isEmpty ? "Tidak ada item untuk disimpan." : "Ringkasan item:")
                .font(.subheadline)
        }
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
    /// Routes the segment through the per-item confirm state machine (see
    /// SessionPhase) instead of appending it straight to the session.
    private func handleSegment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch phase {
        case .listeningForItem:
            handleItemUtterance(trimmed, checkForDoneSignal: true)
        case .confirmingItem(let entry):
            handleConfirmReply(trimmed, entry: entry)
        case .awaitingCorrection:
            handleItemUtterance(trimmed, checkForDoneSignal: false)
        case .askingContinue:
            handleContinueReply(trimmed)
        case .finalSummary:
            break
        }
    }

    /// Parses a segment as a new (or corrected) item and moves to
    /// .confirmingItem so the next segment is read as a yes/no reply.
    /// `checkForDoneSignal` is only true from .listeningForItem (not from
    /// .awaitingCorrection, where any segment is necessarily a correction,
    /// not a done-signal) — captured by the caller rather than re-read from
    /// `phase` here, since that may have already moved on by the time this
    /// Task's first `await` returns.
    private func handleItemUtterance(_ text: String, checkForDoneSignal: Bool) {
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                if checkForDoneSignal, try await llm.isDoneIntent(text) {
                    finishListeningToSummary()
                    return
                }
                let entry = try await llm.parseStockPhrase(text)
                let dto = PendingStockItemDTO(itemName: entry.itemName, quantity: entry.quantity, unit: entry.unit)
                phase = .confirmingItem(dto)
            } catch {
                errorMessage = "Tidak bisa memahami: \"\(text)\""
            }
        }
    }

    /// Classifies the reply to "is that right?" — on yes, commits the item to
    /// the shared session and moves to .askingContinue; on no, discards the
    /// pending item and moves to .awaitingCorrection so the next segment
    /// replaces it entirely.
    private func handleConfirmReply(_ text: String, entry: PendingStockItemDTO) {
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let isCorrect = try await llm.classifyYesNo(reply: text, question: "Is this item correct: \(entry.quantity) \(entry.unit) \(entry.itemName)?")
                if isCorrect {
                    SiriSessionState.append(entry, source: SiriSessionState.source)
                    refreshFromSharedState()
                    phase = .askingContinue
                } else {
                    phase = .awaitingCorrection
                }
            } catch {
                errorMessage = "Tidak bisa memahami jawabannya, coba lagi."
            }
        }
    }

    /// Classifies the reply to "want to add another item?" — on yes, resumes
    /// listening for another item; on no, moves to the final review summary.
    private func handleContinueReply(_ text: String) {
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                let wantsMore = try await llm.classifyYesNo(reply: text, question: "Do you want to add another item?")
                if wantsMore {
                    phase = .listeningForItem
                } else {
                    finishListeningToSummary()
                }
            } catch {
                errorMessage = "Tidak bisa memahami jawabannya, coba lagi."
            }
        }
    }

    private func finishListeningToSummary() {
        voice.stopListening()
        phase = .finalSummary
    }

    private func removeItem(_ item: PendingStockItemDTO) {
        SiriSessionState.remove(id: item.id)
        refreshFromSharedState()
    }

    private func confirmAndSave() {
        StockStore.add(items.map { (itemName: $0.itemName, quantity: $0.quantity, unit: $0.unit) })
        SiriSessionState.end()
        phase = .listeningForItem
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
        phase = .listeningForItem
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
