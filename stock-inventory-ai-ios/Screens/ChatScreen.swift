//
//  ChatScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI
import SwiftData

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
    /// The `PlanLog` behind this reply, when collection is on — enables 👍/👎.
    var logID: PersistentIdentifier? = nil
    var verdict: PlanVerdict = .unrated
    /// Tappable answers for a "maksudnya yang mana?" question; cleared once answered.
    var options: [String] = []
}

private struct DataReferencePanel: View {
    let toolCalls: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data dipakai", systemImage: "shippingbox")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if toolCalls.isEmpty {
                Text("Belum ada data yang dicek.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(toolCalls, id: \.self) { call in
                    Text(call)
                        .font(.caption.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }
}


struct ChatScreen: View {
    private var chatModel = ChatModel.shared
    @Environment(\.modelContext) private var modelContext
    @State private var pendingAction: PendingStockAction?
    @State private var pendingClarification: Clarification?
    /// Names the user disambiguated during the current request ("gula" →
    /// "gula halus"), so follow-up answers don't trigger the same question.
    @State private var picks: [String: String] = [:]
    @State private var previousUserMessage: String?
    @State private var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "Halo! Ada yang bisa saya bantu hari ini?")
    ]
    @State private var draft: String = ""
    @State private var datasetExport: PlanDataset.Export?
    @State private var feedbackLog: PlanLog?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Tanya AI")
                        .font(.title2.bold())
                    Spacer()
                    statusView
                    if PlanLog.isCollectionEnabled {
                        Button {
                            exportDataset()
                        } label: {
                            Label("Ekspor data latih", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                ChatBubble(
                                    message: message,
                                    onRate: { verdict in rate(message.id, verdict) },
                                    onPick: { choice in
                                        if let clarification = pendingClarification {
                                            pick(choice, for: clarification)
                                        }
                                    }
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    // Writes proposed by the agent only happen after an explicit tap.
                    if let action = pendingAction {
                        HStack(spacing: 12) {
                            Text(action.summary)
                                .font(.subheadline)
                            Spacer()
                            Button("Batal") {
                                pendingAction = nil
                                messages.append(ChatMessage(isUser: false, text: "Dibatalkan."))
                            }
                            Button("Simpan") { confirm(action) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.1)))
                    }

                    HStack(spacing: 12) {
                        TextField("Tulis pertanyaan...", text: $draft)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                            .onSubmit(send)

                        Button(action: send) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 26))
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.isEmpty)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 8)
                .background(.background)
            }

            DataReferencePanel(toolCalls: chatModel.lastTrace)
                .frame(width: 200)
                .padding(.top, 24)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            // Normally already loaded/loading from app launch; no-op then.
            await chatModel.loadIfNeeded()
        }
        .sheet(item: $datasetExport) { export in
            VStack(spacing: 16) {
                Text("Data latih planner")
                    .font(.headline)
                Text("""
                \(export.trainCount) contoh siap latih · \(export.preferenceCount) pasangan koreksi
                \(export.reviewCount) 👎 belum dikoreksi · \(export.skippedCount) dilewati (skema lama)
                """)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(items: export.urls) {
                    Label("Bagikan file JSONL", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .presentationDetents([.medium])
        }
        .sheet(item: $feedbackLog) { log in
            PlanFeedbackSheet(log: log)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch chatModel.loadState {
            case .idle, .ready:
                if chatModel.isGenerating {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Mengetik…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .preparing:
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Menyiapkan AI…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Text("Error: \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
    }

    private func send() {
        let text = draft
        guard !text.isEmpty, chatModel.loadState == .ready, !chatModel.isGenerating else { return }
        draft = ""

        // A typed answer to "maksudnya yang mana?" ("2", "yang halus")
        // resumes that request in code instead of starting a new one.
        if let clarification = pendingClarification, let choice = clarification.match(text) {
            pick(choice, for: clarification, typed: text)
            return
        }
        endClarification()
        messages.append(ChatMessage(isUser: true, text: text))
        pendingAction = nil

        let replyIndex = messages.count
        messages.append(ChatMessage(isUser: false, text: ""))
        let previous = previousUserMessage
        if previous == nil { picks = [:] }  // new request — earlier picks don't apply
        let currentPicks = picks
        // Everything the user wrote for this request. Kept across follow-up
        // questions ("berapa harganya?" → "20rb" → "kemarin") so no answer is
        // lost; capped so an abandoned request doesn't grow forever.
        let userText = ([previous, text].compactMap { $0 }.joined(separator: "\n"))
            .split(separator: "\n").suffix(3).joined(separator: "\n")
        previousUserMessage = userText

        Task {
            var logID: PersistentIdentifier?
            do {
                let outcome: AgentOutcome
                do {
                    let plan = try await chatModel.plan(StockPlan.self, instructions: StockPlan.instructions, text: text, previous: previous)
                    logID = PlanLog.record(plan, message: text, previous: previous, in: modelContext)
                    outcome = try StockAgent(context: modelContext).execute(plan, userText: userText, picks: currentPicks)
                } catch {
                    // Planning failed — degrade to plain keyword retrieval so the
                    // user still gets an answer grounded in real stock data.
                    print("[ChatScreen] Planner failed, falling back to retrieval:", error)
                    outcome = .facts(StockKnowledge.relevantFacts(for: text, in: modelContext) ?? "")
                }
                try await present(outcome, at: replyIndex, question: text)
            } catch {
                messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, terjadi kesalahan: \(error.localizedDescription)")
            }
            // Attached last: streaming replaces the message on every partial.
            messages[replyIndex].logID = logID
        }
    }

    /// Resumes a clarified request with the item the user picked. Runs the
    /// stored plan through the agent again — no model call to re-plan.
    private func pick(_ choice: String, for clarification: Clarification, typed: String? = nil) {
        guard !chatModel.isGenerating else { return }
        messages.append(ChatMessage(isUser: true, text: typed ?? choice))
        endClarification()
        pendingAction = nil
        let newPicks = clarification.picks(choosing: choice)
        picks = newPicks
        // Keep the request open: if the agent now asks for a missing price or
        // date, the answer is planned together with the original message.
        previousUserMessage = clarification.userText

        let replyIndex = messages.count
        messages.append(ChatMessage(isUser: false, text: ""))
        Task {
            do {
                let outcome = try StockAgent(context: modelContext)
                    .execute(clarification.plan, userText: clarification.userText, picks: newPicks)
                try await present(outcome, at: replyIndex, question: "\(clarification.userText) (\(choice))")
            } catch {
                messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, terjadi kesalahan: \(error.localizedDescription)")
            }
        }
    }

    /// Shows an agent outcome in the reply bubble at `replyIndex`.
    private func present(_ outcome: AgentOutcome, at replyIndex: Int, question: String) async throws {
        switch outcome {
        case .reply(let reply):
            messages[replyIndex] = ChatMessage(isUser: false, text: reply)
        case .confirm(let action):
            messages[replyIndex] = ChatMessage(isUser: false, text: "Konfirmasi: \(action.summary)?")
            pendingAction = action
            previousUserMessage = nil
        case .clarify(let clarification):
            messages[replyIndex] = ChatMessage(isUser: false, text: clarification.question, options: clarification.options)
            pendingClarification = clarification
            // The clarification carries the request; anything typed that
            // isn't one of the options starts fresh.
            previousUserMessage = nil
        case .facts(let facts):
            for try await partial in chatModel.streamAnswer(question: question, facts: facts) {
                messages[replyIndex] = ChatMessage(isUser: false, text: partial)
            }
            previousUserMessage = nil
        }
        if messages[replyIndex].text.isEmpty {
            messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, AI tidak memberikan jawaban. Coba lagi.")
        }
    }

    private func endClarification() {
        pendingClarification = nil
        for index in messages.indices where !messages[index].options.isEmpty {
            messages[index].options = []
        }
    }

    private func confirm(_ action: PendingStockAction) {
        pendingAction = nil
        messages.append(ChatMessage(isUser: false, text: StockAgent(context: modelContext).commit(action)))
    }

    /// 👍/👎 rates the *plan* (did the AI understand the request?) — check the
    /// side panel's `plan:` line when the answer looks off. 👎 also opens the
    /// correction sheet, which turns the mistake into training data.
    private func rate(_ messageID: UUID, _ verdict: PlanVerdict) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let logID = messages[index].logID,
              let log = modelContext.model(for: logID) as? PlanLog
        else { return }
        log.verdict = verdict
        try? modelContext.save()
        messages[index].verdict = verdict
        if verdict == .bad { feedbackLog = log }
    }

    private func exportDataset() {
        do {
            datasetExport = try PlanDataset.export(from: modelContext)
        } catch {
            messages.append(ChatMessage(isUser: false, text: "Gagal ekspor data latih: \(error.localizedDescription)"))
        }
    }

}

private struct ChatBubble: View {
    let message: ChatMessage
    let onRate: (PlanVerdict) -> Void
    let onPick: (String) -> Void

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if !message.isUser && message.text.isEmpty {
                        TypingIndicator()
                    } else {
                        Text(message.text)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(message.isUser ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
                )

                if !message.options.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.options, id: \.self) { option in
                                Button(option) { onPick(option) }
                                    .buttonStyle(.bordered)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                if message.logID != nil {
                    HStack(spacing: 12) {
                        rateButton(.good, systemImage: "hand.thumbsup")
                        rateButton(.bad, systemImage: "hand.thumbsdown")
                    }
                    .padding(.leading, 8)
                }
            }
            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    private func rateButton(_ verdict: PlanVerdict, systemImage: String) -> some View {
        Button {
            onRate(verdict)
        } label: {
            Image(systemName: message.verdict == verdict ? "\(systemImage).fill" : systemImage)
                .font(.caption)
                .foregroundStyle(message.verdict == verdict ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(verdict == .good ? "Rencana benar" : "Rencana salah")
    }
}

/// Three dots bouncing in a wave, shown while the AI reply is still empty.
private struct TypingIndicator: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = sin(time * 6 - Double(index) * 0.9)
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .offset(y: -3 * phase)
                        .opacity(0.5 + 0.5 * max(phase, 0))
                }
            }
            .frame(height: 18)
        }
        .accessibilityLabel("AI sedang mengetik")
    }
}

#Preview {
    ChatScreen()
}
