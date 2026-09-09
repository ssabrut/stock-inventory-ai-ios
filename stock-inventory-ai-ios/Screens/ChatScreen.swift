//
//  ChatScreen.swift
//  stock-inventory-ai-ios
//

import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

struct ChatScreen: View {
    let llm: LLMService

    @State private var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "Halo! Ada yang bisa saya bantu soal stok hari ini?")
    ]
    @State private var draft: String = ""
    @State private var pendingConfirmation: (call: ToolCall, summary: String, originalPrompt: String, loopState: LLMService.AgentLoopState)?
    /// Set when a tool call is missing a price it can't fall back on (see
    /// `LLMService.AgentResponse.needsPrice`). The next message the user
    /// sends is read as the price reply instead of a fresh prompt — the
    /// model has no memory of this pending call, so ChatScreen holds it.
    /// `originalPrompt` is the message that produced the call (e.g. "tambah
    /// 5kg beras"), kept alongside so the eventual confirm step can phrase
    /// its final answer against that instead of the bare price reply.
    /// `loopState` carries the in-progress agentic loop's transcript and
    /// round count so resuming after the price/confirm step continues the
    /// same loop instead of restarting it.
    @State private var pendingPriceRequest: (call: ToolCall, originalPrompt: String, loopState: LLMService.AgentLoopState)?

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
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                HStack(spacing: 12) {
                    TextField("Tulis pertanyaan...", text: $draft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                        .disabled(llm.state == .generating)
                        .onSubmit(send)

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.isEmpty || llm.state == .generating)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            DataReferencePanel()
                .frame(width: 200)
                .padding(.top, 24)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            "Konfirmasi",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            presenting: pendingConfirmation
        ) { pending in
            Button("Batal", role: .cancel) {
                messages.append(ChatMessage(isUser: false, text: "Oke, dibatalkan."))
                pendingConfirmation = nil
            }
            Button("Konfirmasi") {
                confirm(pending)
            }
        } message: { pending in
            Text(pending.summary)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch llm.state {
        case .idle, .loading, .ready:
            EmptyView()
        case .generating:
            HStack(spacing: 6) {
                ProgressView()
                Text("Mengetik…")
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
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(isUser: true, text: text))
        draft = ""

        if let pending = pendingPriceRequest {
            pendingPriceRequest = nil
            guard let response = llm.resolvePriceReply(text, call: pending.call, state: pending.loopState) else {
                messages.append(ChatMessage(isUser: false, text: "Maaf, saya tidak menangkap harganya. Coba sebutkan angka totalnya, misal \"20000\"."))
                pendingPriceRequest = pending
                return
            }
            handle(response, originalPrompt: pending.originalPrompt)
            return
        }

        Task {
            do {
                handle(try await llm.agenticReply(to: text), originalPrompt: text)
            } catch {
                messages.append(ChatMessage(isUser: false, text: "Maaf, terjadi kesalahan: \(error.localizedDescription)"))
            }
        }
    }

    private func handle(_ response: LLMService.AgentResponse, originalPrompt: String) {
        switch response {
        case .answer(let reply):
            messages.append(ChatMessage(isUser: false, text: reply))
        case .needsConfirmation(let call, let summary, let loopState):
            pendingConfirmation = (call: call, summary: summary, originalPrompt: originalPrompt, loopState: loopState)
        case .needsPrice(let call, let loopState):
            pendingPriceRequest = (call: call, originalPrompt: originalPrompt, loopState: loopState)
            messages.append(ChatMessage(isUser: false, text: "Berapa harga totalnya?"))
        }
    }

    private func confirm(_ pending: (call: ToolCall, summary: String, originalPrompt: String, loopState: LLMService.AgentLoopState)) {
        pendingConfirmation = nil

        Task {
            do {
                let response = try await llm.resolveConfirmedToolCall(pending.call, state: pending.loopState)
                handle(response, originalPrompt: pending.originalPrompt)
            } catch {
                messages.append(ChatMessage(isUser: false, text: "Maaf, terjadi kesalahan: \(error.localizedDescription)"))
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
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

private struct DataReferencePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)
                }
            }

            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 140)
                .overlay(
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 90, height: 8)
                    }
                    .padding(12),
                    alignment: .top
                )

            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    ChatScreen(llm: LLMService())
}
