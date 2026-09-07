//
//  LLMService.swift
//  stock-inventory-ai-ios
//

import Foundation
import Hub
import MLXLLM
@preconcurrency import MLXLMCommon

@Observable
final class LLMService {
    enum LoadPhase: Equatable {
        case checkingCache
        case downloading(fraction: Double, speedMBps: Double?)
        case loadingWeights
    }

    enum State: Equatable {
        case idle
        case loading(LoadPhase)
        case ready
        case generating
        case failed(String)
    }

    private(set) var state: State = .idle

    private var modelContainer: ModelContainer?
    private let modelId = "mlx-community/Qwen2.5-1.5B-Instruct-4bit"

    /// Persists downloaded model weights to Documents instead of Caches, so the
    /// ~1GB download survives Xcode debug reinstalls (which can purge Caches).
    /// HF token is baked in from Secrets.xcconfig (gitignored) at build time via
    /// INFOPLIST_KEY_HFToken, never a scheme env var, so it can't leak into git.
    static let downloadBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        .appending(path: "huggingface")

    private let hub = HubApi(
        downloadBase: downloadBase,
        hfToken: {
            let token = Bundle.main.infoDictionary?["HFToken"] as? String
            return (token?.isEmpty == false && token != "$(HF_TOKEN)") ? token : nil
        }()
    )

    func loadIfNeeded() async {
        guard modelContainer == nil else { return }
        state = .loading(.checkingCache)
        do {
            let factory = LLMModelFactory.shared
            let configuration = ModelConfiguration(id: modelId)
            var didSeeRealProgress = false

            modelContainer = try await factory.loadContainer(hub: hub, configuration: configuration) { [weak self] progress in
                let fraction = progress.fractionCompleted
                let speed = progress.userInfo[.throughputKey] as? Double
                Task { @MainActor in
                    guard let self else { return }
                    // A cache hit resolves near-instantly with no meaningful fraction
                    // reported; only treat this as an active download once we see
                    // real forward progress on it.
                    if fraction > 0 { didSeeRealProgress = true }
                    if didSeeRealProgress {
                        if fraction < 1 {
                            self.state = .loading(.downloading(fraction: fraction, speedMBps: speed.map { $0 / 1_000_000 }))
                        } else {
                            self.state = .loading(.loadingWeights)
                        }
                    }
                }
            }
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reply(to prompt: String, stockContext: String? = nil) async throws -> String {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        var systemPrompt = "Kamu adalah asisten AI untuk aplikasi manajemen stok inventori. Jawab singkat, jelas, dan dalam Bahasa Indonesia."
        if let stockContext {
            systemPrompt += "\n\nData stok saat ini:\n\(stockContext)"
        }

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(prompt)
        ]

        let result = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.6),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        return result
    }

    struct ParsedStockEntry: Decodable {
        let itemName: String
        let quantity: Int
        let unit: String
    }

    /// Classifies whether a spoken segment signals the end of an add-stock
    /// session (e.g. "selesai", "okay done", "udah segitu aja", "that's all")
    /// rather than another item to add. Used by StockSessionOverlay's
    /// continuous-listening flow so the done-signal isn't limited to a fixed
    /// word list — free-form phrasing works the way Siri's own "no more
    /// items" gate would.
    func isDoneIntent(_ text: String) async throws -> Bool {
        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        Kamu mendeteksi apakah ucapan pengguna berarti dia SUDAH SELESAI menambahkan stok \
        (misal: "selesai", "cukup", "udah segitu aja", "that's all", "okay done"), BUKAN \
        menyebutkan barang baru. Balas HANYA dengan "yes" jika itu sinyal selesai, atau "no" \
        jika itu masih menyebutkan item stok (misal "50 gram ayam").
        """

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(text)
        ]

        let raw = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        return raw.lowercased().contains("yes")
    }

    /// Extracts item name/quantity/unit from a free-text stock phrase, e.g.
    /// "50gr of chicken" -> {itemName: "chicken", quantity: 50, unit: "gr"}.
    /// Used by AddStockIntent so Siri can take one free-text parameter
    /// instead of relying on its own quantity/unit slot-filling, which
    /// tends to default to "1 pcs" on fused phrases like "50gr".
    ///
    /// Quantity/unit come from StockPhraseParser (deterministic, dictionary
    /// based) rather than the LLM — the LLM was unreliable at extracting
    /// units, e.g. it would drop an explicit "gram" and default to "pcs"
    /// despite being told not to. The LLM here only cleans up the
    /// leftover text into an item name, a task it's better suited for.
    func parseStockPhrase(_ text: String) async throws -> ParsedStockEntry {
        let parsed = StockPhraseParser.parse(text)

        await loadIfNeeded()
        guard let modelContainer else {
            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        Bersihkan teks ini menjadi nama barang gudang yang rapi. \
        Balas HANYA dengan nama barangnya, tanpa tanda kutip, tanpa penjelasan lain.
        """

        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(parsed.remainingText)
        ]

        let raw = try await modelContainer.perform { context in
            let input = try await context.processor.prepare(input: .init(chat: chat))
            var output = ""
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.0),
                context: context
            )
            for try await item in stream {
                if case .chunk(let text) = item {
                    output += text
                }
            }
            return output
        }

        let itemName = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        guard !itemName.isEmpty else {
            throw NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse item name"])
        }

        return ParsedStockEntry(itemName: itemName, quantity: parsed.quantity, unit: parsed.unit)
    }

    struct CachedModel: Identifiable {
        let id: String
        let url: URL
        let sizeBytes: Int64
        let isActive: Bool
    }

    /// Lists every downloaded model repo under Documents/huggingface/models,
    /// e.g. after switching modelId this surfaces the previous model's now-
    /// orphaned weights so the user can reclaim the disk space manually.
    func cachedModels() -> [CachedModel] {
        let modelsRoot = LLMService.downloadBase.appending(component: "models")
        let fm = FileManager.default

        guard let orgDirs = try? fm.contentsOfDirectory(at: modelsRoot, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [CachedModel] = []
        for orgDir in orgDirs {
            guard let repoDirs = try? fm.contentsOfDirectory(at: orgDir, includingPropertiesForKeys: nil) else { continue }
            for repoDir in repoDirs {
                let id = "\(orgDir.lastPathComponent)/\(repoDir.lastPathComponent)"
                results.append(
                    CachedModel(
                        id: id,
                        url: repoDir,
                        sizeBytes: Self.directorySize(repoDir),
                        isActive: id == modelId
                    )
                )
            }
        }
        return results.sorted { $0.id < $1.id }
    }

    /// Deletes one cached model's weights from disk. Throws if it's the
    /// currently loaded model — that would corrupt the live ModelContainer
    /// mid-session; the caller should have the user switch away first, or
    /// this app relaunch after.
    func deleteCachedModel(_ model: CachedModel) throws {
        guard !model.isActive || modelContainer == nil else {
            throw NSError(
                domain: "LLMService", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Tidak bisa menghapus model yang sedang aktif digunakan."]
            )
        }
        try FileManager.default.removeItem(at: model.url)
    }

    func deleteAllCachedModels() throws {
        for model in cachedModels() {
            try deleteCachedModel(model)
        }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
