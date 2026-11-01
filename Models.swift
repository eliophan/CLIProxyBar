import Foundation
import SwiftUI

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
