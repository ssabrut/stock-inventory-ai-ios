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
    @State private var previousUserMessage: String?
    @State private var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "Halo! Ada yang bisa saya bantu hari ini?")
    ]
    @State private var draft: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Tanya AI")
                        .font(.title2.bold())
                    Spacer()
                    statusView
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
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
        messages.append(ChatMessage(isUser: true, text: text))
        draft = ""
        pendingAction = nil

        let replyIndex = messages.count
        messages.append(ChatMessage(isUser: false, text: ""))
        let previous = previousUserMessage
        previousUserMessage = text

        Task {
            do {
                let outcome: AgentOutcome
                do {
                    let plan = try await chatModel.plan(StockPlan.self, instructions: StockPlan.instructions, text: text, previous: previous)
                    outcome = try StockAgent(context: modelContext).execute(plan)
                } catch {
                    // Planning failed — degrade to plain keyword retrieval so the
                    // user still gets an answer grounded in real stock data.
                    print("[ChatScreen] Planner failed, falling back to retrieval:", error)
                    outcome = .facts(StockKnowledge.relevantFacts(for: text, in: modelContext) ?? "")
                }

                switch outcome {
                case .reply(let reply):
                    messages[replyIndex] = ChatMessage(isUser: false, text: reply)
                case .confirm(let action):
                    messages[replyIndex] = ChatMessage(isUser: false, text: "Konfirmasi: \(action.summary)?")
                    pendingAction = action
                    previousUserMessage = nil
                case .facts(let facts):
                    for try await partial in chatModel.streamAnswer(question: text, facts: facts) {
                        messages[replyIndex] = ChatMessage(isUser: false, text: partial)
                    }
                    previousUserMessage = nil
                }
                if messages[replyIndex].text.isEmpty {
                    messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, AI tidak memberikan jawaban. Coba lagi.")
                }
            } catch {
                messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, terjadi kesalahan: \(error.localizedDescription)")
            }
        }
    }

    private func confirm(_ action: PendingStockAction) {
        pendingAction = nil
        messages.append(ChatMessage(isUser: false, text: StockAgent(context: modelContext).commit(action)))
    }

}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
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
            if !message.isUser { Spacer(minLength: 40) }
        }
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
