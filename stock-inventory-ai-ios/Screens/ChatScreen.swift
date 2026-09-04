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
    let qnaService: QnaServicing = QnaService()

    @State private var messages: [ChatMessage] = [
        ChatMessage(isUser: false, text: "Halo! Ada yang bisa saya bantu soal stok hari ini?")
    ]
    @State private var draft: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tanya AI")
                    .font(.title2.bold())

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            if isSending {
                                HStack {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Mengetik...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onChange(of: messages.count) {
                        if let lastId = messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
                    TextField("Tulis pertanyaan...", text: $draft)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                        .disabled(isSending)
                        .onSubmit(sendMessage)

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
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
    }

    private func sendMessage() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }

        messages.append(ChatMessage(isUser: true, text: question))
        draft = ""
        errorMessage = nil
        isSending = true

        Task {
            do {
                let answer = try await qnaService.ask(question: question)
                messages.append(ChatMessage(isUser: false, text: answer))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
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
    ChatScreen()
}
