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
    
    var proxyURL: String = "http://127.0.0.1:8317"
    var secretKey: String = "123456"
    
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    
    init() {
        if let envURL = ProcessInfo.processInfo.environment["CLIPROXY_URL"], !envURL.isEmpty {
            self.proxyURL = envURL
        }
        if let envKey = ProcessInfo.processInfo.environment["CLIPROXY_KEY"], !envKey.isEmpty {
            self.secretKey = envKey
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
        
        // Network poll every 8 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
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
            
            if let signals = f.quota?.signals {
                // Claude
                if let p5hUtilStr = signals["Anthropic-Ratelimit-Unified-5h-Utilization"],
                   let p5hVal = Double(p5hUtilStr) {
                    primaryPercent = min(p5hVal * 100.0, 100.0)
                }
                if let p5hResetStr = signals["Anthropic-Ratelimit-Unified-5h-Reset"],
                   let p5hResetEpoch = Int(p5hResetStr) {
                    primaryResetSec = max(p5hResetEpoch - nowEpoch, 0)
                }
                if let retryAfterStr = signals["Retry-After"], let retrySec = Int(retryAfterStr) {
                    if primaryResetSec == nil || retrySec > 0 {
                        primaryResetSec = retrySec
                    }
                }
                if let p7dUtilStr = signals["Anthropic-Ratelimit-Unified-7d-Utilization"],
                   let p7dVal = Double(p7dUtilStr) {
                    secondaryPercent = min(p7dVal * 100.0, 100.0)
                }
                if let p7dResetStr = signals["Anthropic-Ratelimit-Unified-7d-Reset"],
                   let p7dResetEpoch = Int(p7dResetStr) {
                    secondaryResetSec = max(p7dResetEpoch - nowEpoch, 0)
                }
                primaryStatus = signals["Anthropic-Ratelimit-Unified-5h-Status"]
                
                // Codex
                if let pUsed = signals["X-Codex-Primary-Used-Percent"], let val = Double(pUsed) {
                    primaryPercent = val
                }
                if let pResetSec = signals["X-Codex-Primary-Reset-After-Seconds"], let val = Int(pResetSec) {
                    primaryResetSec = val
                }
                if let sUsed = signals["X-Codex-Secondary-Used-Percent"], let val = Double(sUsed) {
                    secondaryPercent = val
                }
                if let sResetSec = signals["X-Codex-Secondary-Reset-After-Seconds"], let val = Int(sResetSec) {
                    secondaryResetSec = val
                }
                if let plan = signals["X-Codex-Plan-Type"] {
                    planType = plan.capitalized
                }
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
                rawObservedAt: f.quota?.observedAt
            )
            parsed.append(acc)
        }
        
        // Sort accounts:
        // 1. Provider order: Claude, Codex, Antigravity, Others
        // 2. Status: Ready first, then Cooldown by remaining ascending
        // 3. Priority descending
        parsed.sort { a, b in
            if a.provider != b.provider {
                return a.provider < b.provider
            }
            if a.status != b.status {
                if a.status == .ready { return true }
                if b.status == .ready { return false }
                if a.status == .cooldown && b.status == .disabled { return true }
                if b.status == .cooldown && a.status == .disabled { return false }
            }
            if a.status == .cooldown && b.status == .cooldown {
                return a.cooldownRemainingSeconds < b.cooldownRemainingSeconds
            }
            return a.priority > b.priority
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
            let rebalancerPath = NSString(string: "~/.cli-proxy-api/soonest_reset_rebalancer.py").expandingTildeInPath
            
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
                Task {
                    await self.fetchAuthFiles()
                }
            }
        }
    }
}
