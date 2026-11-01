import Foundation
import SwiftUI

@MainActor
class ProxyClient: ObservableObject {
    @Published var accounts: [NormalizedAccount] = []
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var statusMessage: String = "Connecting..."
    @Published var isRebalancing: Bool = false
    
    // Summary metrics
    @Published var readyCount: Int = 0
    @Published var cooldownCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var soonestCooldownSeconds: Int? = nil
    
    // Pinned accounts for Menu Bar Glance (Multiple accounts supported)
    @Published var pinnedAccountIds: Set<String> = []
    
    @Published var proxyURL: String = "http://127.0.0.1:8317"
    @Published var secretKey: String = "123456"
    @Published var pollInterval: Double = 5.0
    
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    
    var glanceAccounts: [NormalizedAccount] {
        if !pinnedAccountIds.isEmpty {
            return accounts.filter { pinnedAccountIds.contains($0.id) }
        }
        if let first = accounts.first {
            return [first]
        }
        return []
    }
    
    var glanceGroups: [ProviderGlanceGroup] {
        let active = glanceAccounts
        var groups: [ProviderGlanceGroup] = []
        for acc in active {
            if let idx = groups.firstIndex(where: { $0.provider.lowercased() == acc.provider.lowercased() }) {
                var existing = groups[idx].accounts
                existing.append(acc)
                groups[idx] = ProviderGlanceGroup(provider: groups[idx].provider, accounts: existing)
            } else {
                groups.append(ProviderGlanceGroup(provider: acc.provider, accounts: [acc]))
            }
        }
        return groups
    }
    
    func togglePinAccount(id: String) {
        if pinnedAccountIds.contains(id) {
            pinnedAccountIds.remove(id)
        } else {
            pinnedAccountIds.insert(id)
        }
        UserDefaults.standard.set(Array(pinnedAccountIds), forKey: "pinned_glance_account_ids")
    }
    
    func clearAllPins() {
        pinnedAccountIds.removeAll()
        UserDefaults.standard.removeObject(forKey: "pinned_glance_account_ids")
    }
    
    init() {
        if let savedPins = UserDefaults.standard.stringArray(forKey: "pinned_glance_account_ids") {
            self.pinnedAccountIds = Set(savedPins)
        } else if let legacyPin = UserDefaults.standard.string(forKey: "pinned_glance_account_id") {
            self.pinnedAccountIds = [legacyPin]
        }
        
        // 1. Proxy URL
        if let savedURL = UserDefaults.standard.string(forKey: "proxy_url"), !savedURL.isEmpty {
            self.proxyURL = savedURL
        } else if let envURL = ProcessInfo.processInfo.environment["CLIPROXY_URL"], !envURL.isEmpty {
            self.proxyURL = envURL
        }
        
        // 2. Secret Key (Keychain priority)
        if let savedKey = KeychainHelper.load(key: "management_secret_key"), !savedKey.isEmpty {
            self.secretKey = savedKey
        } else if let savedKeyUD = UserDefaults.standard.string(forKey: "management_secret_key"), !savedKeyUD.isEmpty {
            self.secretKey = savedKeyUD
        } else if let envKey = ProcessInfo.processInfo.environment["CLIPROXY_KEY"], !envKey.isEmpty {
            self.secretKey = envKey
        }
        
        // 3. Polling Interval
        let savedInterval = UserDefaults.standard.double(forKey: "poll_interval")
        if savedInterval >= 1.0 && savedInterval <= 30.0 {
            self.pollInterval = savedInterval
        } else {
            self.pollInterval = 5.0
        }
        
        startTimers()
        Task {
            await fetchAuthFiles()
        }
    }
    
    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
    }
    
    func startTimers() {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
        
        // Dynamic Network polling timer
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchAuthFiles()
            }
        }
        
        // Local second tick for smooth countdowns
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.decrementCountdowns()
            }
        }
    }
    
    func updateSettings(url: String, key: String, interval: Double) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInterval = max(1.0, min(30.0, interval))
        
        self.proxyURL = cleanURL
        self.secretKey = cleanKey
        self.pollInterval = cleanInterval
        
        UserDefaults.standard.set(cleanURL, forKey: "proxy_url")
        UserDefaults.standard.set(cleanInterval, forKey: "poll_interval")
        UserDefaults.standard.set(cleanKey, forKey: "management_secret_key")
        KeychainHelper.save(key: "management_secret_key", value: cleanKey)
        
        startTimers()
        Task {
            await fetchAuthFiles()
        }
    }
    
    func testConnection(url: String, key: String) async -> (success: Bool, message: String) {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetURL = URL(string: "\(cleanURL)/v0/management/auth-files") else {
            return (false, "Invalid URL format")
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 4.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    if let decoded = try? JSONDecoder().decode(AuthFilesResponse.self, from: data) {
                        let count = decoded.files?.count ?? 0
                        return (true, "Connected successfully (\(count) accounts found)")
                    }
                    return (true, "Connected successfully")
                } else if http.statusCode == 401 || http.statusCode == 403 {
                    return (false, "Unauthorized: Secret Key is invalid")
                } else {
                    return (false, "Server returned HTTP \(http.statusCode)")
                }
            }
            return (false, "Unexpected response from server")
        } catch {
            return (false, "Connection error: \(error.localizedDescription)")
        }
    }
    
    func decrementCountdowns() {
        var minCooldown: Int? = nil
        accounts = accounts.map { acc in
            var updatedCooldown = acc.cooldownRemainingSeconds
            if updatedCooldown > 0 {
                updatedCooldown -= 1
            }
            
            var updatedPrimaryReset = acc.primaryResetSeconds
            if let pr = updatedPrimaryReset, pr > 0 {
                updatedPrimaryReset = pr - 1
            }
            
            var updatedSecReset = acc.secondaryResetSeconds
            if let sr = updatedSecReset, sr > 0 {
                updatedSecReset = sr - 1
            }
            
            if updatedCooldown > 0 {
                if let currentMin = minCooldown {
                    minCooldown = min(currentMin, updatedCooldown)
                } else {
                    minCooldown = updatedCooldown
                }
            }
            
            let newStatus: AccountStatus = acc.isDisabled ? .disabled : (updatedCooldown > 0 ? .cooldown : .ready)
            
            return NormalizedAccount(
                id: acc.id,
                provider: acc.provider,
                email: acc.email,
                filePath: acc.filePath,
                priority: acc.priority,
                isDisabled: acc.isDisabled,
                status: newStatus,
                cooldownRemainingSeconds: updatedCooldown,
                coolingModels: acc.coolingModels,
                primaryUsedPercent: acc.primaryUsedPercent,
                primaryResetSeconds: updatedPrimaryReset,
                primaryStatusText: acc.primaryStatusText,
                secondaryUsedPercent: acc.secondaryUsedPercent,
                secondaryResetSeconds: updatedSecReset,
                planType: acc.planType,
                planDetails: acc.planDetails,
                rawObservedAt: acc.rawObservedAt
            )
        }
        self.soonestCooldownSeconds = minCooldown
    }
    
    func fetchAuthFiles() async {
        guard let url = URL(string: "\(proxyURL)/v0/management/auth-files") else {
            statusMessage = "Invalid URL"
            isConnected = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                let decoder = JSONDecoder()
                let result = try decoder.decode(AuthFilesResponse.self, from: data)
                let rawFiles = result.files ?? []
                
                parseAndSetAccounts(rawFiles)
                self.isConnected = true
                self.lastUpdated = Date()
                self.statusMessage = "Connected to CLIProxy (Port 8317)"
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.isConnected = false
                self.statusMessage = "HTTP Error: \(code)"
            }
        } catch {
            self.isConnected = false
            self.statusMessage = "Cannot connect to 127.0.0.1:8317"
        }
    }
    
    private func parseAndSetAccounts(_ rawFiles: [RawAuthFile]) {
        let nowEpoch = Int(Date().timeIntervalSince1970)
        var parsed: [NormalizedAccount] = []
        var ready = 0
        var cooling = 0
        var minCooldown: Int? = nil
        
        for f in rawFiles {
            let prov = f.provider ?? "unknown"
            let email = f.email ?? f.account ?? f.name ?? f.id ?? "Account"
            let id = f.id ?? email
            let path = f.path ?? ""
            let prio = f.priority ?? 0
            let disabled = f.disabled ?? false
            
            // Extract cooldowns
            var maxRemaining = 0
            var coolingModels: [String] = []
            if let cds = f.cooldowns {
                for c in cds {
                    let rem = c.remainingSeconds ?? 0
                    if rem > maxRemaining {
                        maxRemaining = rem
                    }
                    if let model = c.modelKey, !coolingModels.contains(model) {
                        coolingModels.append(model)
                    }
                }
            }
            
            // Extract quota signals
            var primaryPercent: Double? = nil
            var primaryResetSec: Int? = nil
            var primaryStatus: String? = nil
            var secondaryPercent: Double? = nil
            var secondaryResetSec: Int? = nil
            var planType: String? = nil
            var planDetails: String? = nil
            
            if let signals = f.quota?.signals {
                // Claude - calculate REMAINING % (100% - used%) to match official Web UI
                if let p5hUtilStr = signals["Anthropic-Ratelimit-Unified-5h-Utilization"],
                   let p5hVal = Double(p5hUtilStr) {
                    let used = min(max(p5hVal * 100.0, 0.0), 100.0)
                    primaryPercent = max(100.0 - used, 0.0)
                }
                if let p7dUtilStr = signals["Anthropic-Ratelimit-Unified-7d-Utilization"],
                   let p7dVal = Double(p7dUtilStr) {
                    let used = min(max(p7dVal * 100.0, 0.0), 100.0)
                    secondaryPercent = max(100.0 - used, 0.0)
                }
                if let p7dResetStr = signals["Anthropic-Ratelimit-Unified-7d-Reset"],
                   let p7dResetEpoch = Int(p7dResetStr) {
                    secondaryResetSec = max(p7dResetEpoch - nowEpoch, 0)
                }
                primaryStatus = signals["Anthropic-Ratelimit-Unified-5h-Status"]
                
                // Set primary reset countdown: if in cooldown, use the exact remaining seconds!
                if maxRemaining > 0 {
                    primaryResetSec = maxRemaining
                } else if let p5hResetStr = signals["Anthropic-Ratelimit-Unified-5h-Reset"],
                          let p5hResetEpoch = Int(p5hResetStr) {
                    primaryResetSec = max(p5hResetEpoch - nowEpoch, 0)
                } else if let retryAfterStr = signals["Retry-After"], let retrySec = Int(retryAfterStr) {
                    primaryResetSec = retrySec
                }
                
                // Codex - calculate REMAINING % (100% - used%)
                if let pUsed = signals["X-Codex-Primary-Used-Percent"], let val = Double(pUsed) {
                    primaryPercent = max(100.0 - val, 0.0)
                }
                if maxRemaining > 0 {
                    primaryResetSec = maxRemaining
                } else if let pResetSec = signals["X-Codex-Primary-Reset-After-Seconds"], let val = Int(pResetSec) {
                    primaryResetSec = val
                }
                
                if let sUsed = signals["X-Codex-Secondary-Used-Percent"], let val = Double(sUsed) {
                    secondaryPercent = max(100.0 - val, 0.0)
                }
                if let sResetSec = signals["X-Codex-Secondary-Reset-After-Seconds"], let val = Int(sResetSec) {
                    secondaryResetSec = val
                }
                if let plan = signals["X-Codex-Plan-Type"] {
                    planType = plan.capitalized
                }
            }
            
            // Extract local metadata for providers without usage signals
            let normProv = resolveProviderLogoName(prov)
            if primaryPercent == nil && !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if normProv == "antigravity" {
                        let proj = json["project_id"] as? String ?? "aicode-consumers"
                        var modelCount = 0
                        if let hints = json["antigravity_capability_hints"] as? [String: Any],
                           let models = hints["model_ids"] as? [String] {
                            modelCount = models.count
                        }
                        planDetails = "Project: \(proj) • \(modelCount > 0 ? "\(modelCount) models" : "Active")"
                    } else if normProv == "meta" {
                        let tier = json["subs_tier_name"] as? String ?? "Everyday Usage"
                        let active = json["is_subs_active"] as? Bool ?? true
                        planDetails = "Tier: \(tier)\(active ? " • Active" : "")"
                    } else if normProv == "vertex" {
                        let proj = json["project_id"] as? String ?? "GCP"
                        planDetails = "Project: \(proj) • Service Account"
                    } else if normProv == "devin" {
                        let org = json["org_name"] as? String ?? json["org"] as? String
                        planDetails = org != nil ? "Org: \(org!)" : "Cognition Devin"
                    } else if normProv == "kimi" {
                        planDetails = "Moonshot Kimi AI"
                    } else if normProv == "xai" {
                        planDetails = "xAI Grok"
                    } else if normProv == "qwen" {
                        planDetails = "Alibaba Qwen Code"
                    } else if normProv == "gemini" {
                        let proj = json["project_id"] as? String
                        planDetails = proj != nil ? "Project: \(proj!)" : "Google Gemini"
                    }
                }
            }
            if primaryPercent == nil && planDetails == nil {
                planDetails = "\(prov.capitalized) Account"
            }
            
            let status: AccountStatus
            if disabled {
                status = .disabled
            } else if maxRemaining > 0 {
                status = .cooldown
                cooling += 1
                if let currentMin = minCooldown {
                    minCooldown = min(currentMin, maxRemaining)
                } else {
                    minCooldown = maxRemaining
                }
            } else {
                status = .ready
                ready += 1
            }
            
            let acc = NormalizedAccount(
                id: id,
                provider: prov,
                email: email,
                filePath: path,
                priority: prio,
                isDisabled: disabled,
                status: status,
                cooldownRemainingSeconds: maxRemaining,
                coolingModels: coolingModels,
                primaryUsedPercent: primaryPercent,
                primaryResetSeconds: primaryResetSec,
                primaryStatusText: primaryStatus,
                secondaryUsedPercent: secondaryPercent,
                secondaryResetSeconds: secondaryResetSec,
                planType: planType,
                planDetails: planDetails,
                rawObservedAt: f.quota?.observedAt
            )
            parsed.append(acc)
        }
        
        let savedOrder = UserDefaults.standard.stringArray(forKey: "user_account_order") ?? []
        parsed.sort { a, b in
            if !savedOrder.isEmpty {
                let idxA = savedOrder.firstIndex(of: a.id) ?? Int.max
                let idxB = savedOrder.firstIndex(of: b.id) ?? Int.max
                if idxA != idxB {
                    return idxA < idxB
                }
            }
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            if a.provider != b.provider {
                return a.provider < b.provider
            }
            return a.id < b.id
        }
        
        self.accounts = parsed
        self.readyCount = ready
        self.cooldownCount = cooling
        self.totalCount = parsed.count
        self.soonestCooldownSeconds = minCooldown
    }
    
    func runRebalance() {
        guard !isRebalancing else { return }
        isRebalancing = true
        
        let targetURL = self.proxyURL
        let targetKey = self.secretKey
        
        DispatchQueue.global(qos: .userInitiated).async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let rebalancerPath = home.appendingPathComponent(".cli-proxy-api/soonest_reset_rebalancer.py").path
            
            guard FileManager.default.fileExists(atPath: rebalancerPath) else {
                print("Rebalancer script not found at: \(rebalancerPath)")
                DispatchQueue.main.async {
                    self.isRebalancing = false
                }
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", rebalancerPath]
            
            var env = ProcessInfo.processInfo.environment
            env["CLIPROXY_URL"] = targetURL
            env["CLIPROXY_KEY"] = targetKey
            process.environment = env
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("Failed to run rebalancer: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isRebalancing = false
                UserDefaults.standard.removeObject(forKey: "user_account_order")
                Task {
                    await self.fetchAuthFiles()
                }
            }
        }
    }
    
    func reorderAccount(fromId: String, toId: String) {
        guard fromId != toId,
              let fromIndex = accounts.firstIndex(where: { $0.id == fromId }),
              let toIndex = accounts.firstIndex(where: { $0.id == toId }) else { return }
        
        if fromIndex < toIndex {
            accounts.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex + 1)
        } else {
            accounts.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
        
        // Save user's custom sequence
        let newOrder = accounts.map { $0.id }
        UserDefaults.standard.set(newOrder, forKey: "user_account_order")
        
        // Assign global descending priorities (50, 49, 48...)
        let basePriority = max(50, accounts.count + 10)
        var updates: [(name: String, path: String, priority: Int)] = []
        
        for (idx, acc) in accounts.enumerated() {
            let newPriority = max(basePriority - idx, 1)
            if acc.priority != newPriority {
                updates.append((name: acc.id, path: acc.filePath, priority: newPriority))
                
                let updated = NormalizedAccount(
                    id: acc.id,
                    provider: acc.provider,
                    email: acc.email,
                    filePath: acc.filePath,
                    priority: newPriority,
                    isDisabled: acc.isDisabled,
                    status: acc.status,
                    cooldownRemainingSeconds: acc.cooldownRemainingSeconds,
                    coolingModels: acc.coolingModels,
                    primaryUsedPercent: acc.primaryUsedPercent,
                    primaryResetSeconds: acc.primaryResetSeconds,
                    primaryStatusText: acc.primaryStatusText,
                    secondaryUsedPercent: acc.secondaryUsedPercent,
                    secondaryResetSeconds: acc.secondaryResetSeconds,
                    planType: acc.planType,
                    planDetails: acc.planDetails,
                    rawObservedAt: acc.rawObservedAt
                )
                accounts[idx] = updated
            }
        }
        
        // API-First remote HTTP update, with local disk fallback!
        Task {
            await self.persistPrioritiesRemoteAndLocal(updates: updates)
        }
    }
    
    private func persistPrioritiesRemoteAndLocal(updates: [(name: String, path: String, priority: Int)]) async {
        for u in updates {
            // 1. API-First HTTP PATCH to proxy (works anywhere, even remote VPS/Docker)
            await patchPriorityOverHTTP(name: u.name, priority: u.priority)
            
            // 2. Local fallback if file exists on this machine
            if !u.path.isEmpty && FileManager.default.fileExists(atPath: u.path) {
                persistPriorityLocal(filePath: u.path, priority: u.priority)
            }
        }
        
        // 3. Trigger proxy refresh to sync state immediately across all clients
        await triggerAuthRefreshOverHTTP()
    }
    
    private func patchPriorityOverHTTP(name: String, priority: Int) async {
        guard let url = URL(string: "\(self.proxyURL)/v0/management/auth-files/fields") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(self.secretKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3.0
        
        let payload: [String: Any] = ["name": name, "priority": priority]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = body
        
        _ = try? await URLSession.shared.data(for: req)
    }
    
    private func triggerAuthRefreshOverHTTP() async {
        guard let url = URL(string: "\(self.proxyURL)/v0/management/auth-files/refresh") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(self.secretKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3.0
        
        let payload: [String: Any] = ["all": true]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = body
        
        _ = try? await URLSession.shared.data(for: req)
    }
    
    private func persistPriorityLocal(filePath: String, priority: Int) {
        guard !filePath.isEmpty, FileManager.default.fileExists(atPath: filePath) else { return }
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        
        json["priority"] = priority
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: url, options: .atomic)
        }
    }
}
