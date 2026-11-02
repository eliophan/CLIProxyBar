import Foundation
import SwiftUI
import AppKit
import Security

// MARK: - Secure Keychain Storage

enum KeychainHelper {
    private static let serviceName = "com.cliproxy.bar"
    
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

// MARK: - Raw JSON API Structures

struct AuthFilesResponse: Codable {
    let files: [RawAuthFile]?
}

struct RawAuthFile: Codable {
    let account: String?
    let accountType: String?
    let authIndex: String?
    let cooldowns: [RawCooldown]?
    let createdAt: String?
    let disabled: Bool?
    let email: String?
    let failed: Int?
    let id: String?
    let label: String?
    let lastRefresh: String?
    let modtime: String?
    let name: String?
    let path: String?
    let priority: Int?
    let provider: String?
    let quota: RawQuota?
    let modelQuotas: [String: RawQuota]?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case account
        case accountType = "account_type"
        case authIndex = "auth_index"
        case cooldowns
        case createdAt = "created_at"
        case disabled
        case email
        case failed
        case id
        case label
        case lastRefresh = "last_refresh"
        case modtime
        case name
        case path
        case priority
        case provider
        case quota
        case modelQuotas = "model_quotas"
        case status
    }
}

struct RawCooldown: Codable {
    let scope: String?
    let modelKey: String?
    let reason: String?
    let retryAt: String?
    let remainingSeconds: Int?
    let backoffLevel: Int?
    let httpStatus: Int?

    enum CodingKeys: String, CodingKey {
        case scope
        case modelKey = "model_key"
        case reason
        case retryAt = "retry_at"
        case remainingSeconds = "remaining_seconds"
        case backoffLevel = "backoff_level"
        case httpStatus = "http_status"
    }
}

struct RawQuota: Codable {
    let observedAt: String?
    let signals: [String: String]?

    enum CodingKeys: String, CodingKey {
        case observedAt = "observed_at"
        case signals
    }
}

// MARK: - Normalized Domain Models for UI

enum AccountStatus: String {
    case ready = "Ready"
    case cooldown = "Cooldown"
    case disabled = "Disabled"
    case error = "Error"

    var color: Color {
        switch self {
        case .ready: return Color.green
        case .cooldown: return Color.orange
        case .disabled: return Color.gray
        case .error: return Color.red
        }
    }
}

struct NormalizedAccount: Identifiable {
    let id: String
    let provider: String
    let email: String
    let filePath: String
    let priority: Int
    let isDisabled: Bool
    let status: AccountStatus
    
    // Cooldown info
    let cooldownRemainingSeconds: Int
    let coolingModels: [String]
    
    // Primary limit (e.g. 5-hour rolling)
    let primaryUsedPercent: Double?
    let primaryResetSeconds: Int?
    let primaryStatusText: String?
    
    // Secondary limit (e.g. 7-day weekly)
    let secondaryUsedPercent: Double?
    let secondaryResetSeconds: Int?
    
    // Metadata
    let planType: String?
    let planDetails: String?
    let rawObservedAt: String?
    
    var displayName: String {
        if !email.isEmpty { return email }
        return id
    }
}

// MARK: - Time Format Helpers

func formatSeconds(_ totalSeconds: Int) -> String {
    if totalSeconds <= 0 { return "0s" }
    let days = totalSeconds / 86400
    let hours = (totalSeconds % 86400) / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    
    if days > 0 {
        return "\(days)d \(hours)h"
    }
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    if minutes > 0 {
        return "\(minutes)m \(seconds)s"
    }
    return "\(seconds)s"
}

// MARK: - Menu Bar Provider Group

struct ProviderGlanceGroup: Identifiable {
    let provider: String
    let accounts: [NormalizedAccount]
    var id: String { provider }
    
    var displayText: String {
        accounts.map { acc -> String in
            if acc.status == .cooldown && acc.cooldownRemainingSeconds > 0 {
                return formatSeconds(acc.cooldownRemainingSeconds)
            } else if let pct = acc.primaryUsedPercent {
                return "\(Int(pct))%"
            } else {
                return acc.status == .ready ? "Ready" : acc.status.rawValue
            }
        }.joined(separator: " • ")
    }
}

// MARK: - Universal Provider Brand Resolution & Logo Loader

func resolveProviderLogoName(_ raw: String) -> String {
    let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if lower.contains("claude") || lower.contains("anthropic") {
        return "claude"
    } else if lower.contains("codex") || lower.contains("openai") || lower.contains("chatgpt") {
        return "codex"
    } else if lower.contains("antigravity") {
        return "antigravity"
    } else if lower.contains("meta") || lower.contains("llama") {
        return "meta"
    } else if lower.contains("devin") || lower.contains("cognition") {
        return "devin"
    } else if lower.contains("kimi") || lower.contains("moonshot") {
        return "kimi"
    } else if lower.contains("vertex") {
        return "vertex"
    } else if lower.contains("gemini") || lower.contains("google") || lower.contains("aistudio") {
        return "gemini"
    } else if lower.contains("xai") || lower.contains("grok") {
        return "xai"
    } else if lower.contains("qwen") || lower.contains("qianwen") || lower.contains("alibaba") {
        return "qwen"
    }
    return lower
}

func loadProviderLogo(provider: String) -> NSImage? {
    let resolved = resolveProviderLogoName(provider)
    let raw = provider.lowercased()
    
    // 1. Standard App Bundle resources
    if let url = Bundle.main.url(forResource: resolved, withExtension: "svg"),
       let img = NSImage(contentsOf: url) {
        return img
    }
    if let url = Bundle.main.url(forResource: raw, withExtension: "svg"),
       let img = NSImage(contentsOf: url) {
        return img
    }
    
    // 2. Relative to main bundle URL (e.g. Contents/Resources)
    let bundleResources = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")
    if let img = NSImage(contentsOf: bundleResources.appendingPathComponent("\(resolved).svg")) {
        return img
    }
    if let img = NSImage(contentsOf: bundleResources.appendingPathComponent("\(raw).svg")) {
        return img
    }
    
    // 3. Relative to current working directory (e.g. during local development)
    let currentDirResources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    if let img = NSImage(contentsOf: currentDirResources.appendingPathComponent("\(resolved).svg")) {
        return img
    }
    if let img = NSImage(contentsOf: currentDirResources.appendingPathComponent("\(raw).svg")) {
        return img
    }
    
    return nil
}
