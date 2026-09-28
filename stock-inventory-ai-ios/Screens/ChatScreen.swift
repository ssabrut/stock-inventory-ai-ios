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
    @State private var chatModel = ChatModel(modelURL: Self.resolveModelURL())

    @State private var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "Halo! Ada yang bisa saya bantu hari ini?")
    ]
    @State private var draft: String = ""

    /// Temporary diagnostic — prints Bundle.main's top-level contents so we
    /// can see exactly what's actually bundled at runtime, instead of
    /// crashing blind on a force-unwrap. Remove once the resource is
    /// confirmed resolving correctly.
    private static func resolveModelURL() -> URL {
        let name = "qwen3_0_6b_mixed_4bit_8bit_static"
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            print("[ChatScreen] Found model at:", url.path)
            return url
        }

        fatalError("Model resource '\(name)' not found in bundle — see console output above.")
    }

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
                        .onSubmit(send)

                    Button(action: send) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.isEmpty)
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
        .task {
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
        guard !text.isEmpty, chatModel.loadState == .ready else { return }
        messages.append(ChatMessage(isUser: true, text: text))
        draft = ""
        
        let replyIndex = messages.count
        messages.append(ChatMessage(isUser: false, text: ""))
        
        Task {
            do {
                for try await partial in chatModel.streamResponse(to: text) {
                    messages[replyIndex] = ChatMessage(isUser: false, text: partial)
                }
                // An empty reply would leave the typing dots spinning forever.
                if messages[replyIndex].text.isEmpty {
                    messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, AI tidak memberikan jawaban. Coba lagi.")
                }
            } catch {
                messages[replyIndex] = ChatMessage(isUser: false, text: "Maaf, terjadi kesalahan: \(error.localizedDescription)")
            }
        }
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
    ChatScreen()
}
