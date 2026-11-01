import SwiftUI
import AppKit

// MARK: - Main Popover View (Apple macOS HIG + Agent Design)

struct MainView: View {
    @ObservedObject var client: ProxyClient
    @State private var selectedProvider: String = "ALL"
    
    var providers: [String] {
        let set = Set(client.accounts.map { $0.provider.uppercased() })
        return ["ALL"] + Array(set).sorted()
    }
    
    var filteredAccounts: [NormalizedAccount] {
        if selectedProvider == "ALL" {
            return client.accounts
        }
        return client.accounts.filter { $0.provider.uppercased() == selectedProvider }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HeaderView(client: client)
            
            Divider()
                .overlay(Color(NSColor.separatorColor).opacity(0.4))
            
            // Native Segmented Control for Providers
            if providers.count > 2 {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(providers, id: \.self) { p in
                        Text(providerTabTitle(p)).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                Divider()
                    .overlay(Color(NSColor.separatorColor).opacity(0.3))
            }
            
            // Content List
            if client.accounts.isEmpty {
                EmptyStateView(client: client)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredAccounts) { acc in
                            AccountCardView(account: acc)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            
            Divider()
                .overlay(Color(NSColor.separatorColor).opacity(0.4))
            
            // Footer Bar
            FooterView(client: client)
        }
        .frame(width: 360, height: 490)
        .background(.ultraThinMaterial)
    }
    
    private func providerTabTitle(_ p: String) -> String {
        if p == "ALL" { return "All (\(client.accounts.count))" }
        let c = client.accounts.filter { $0.provider.uppercased() == p }.count
        return "\(p.capitalized) (\(c))"
    }
}

// MARK: - Header Bar (Clean, Typography-First)

struct HeaderView: View {
    @ObservedObject var client: ProxyClient
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Status Dot
            Circle()
                .fill(client.isConnected ? Color(NSColor.systemGreen) : Color(NSColor.systemRed))
                .frame(width: 6, height: 6)
            
            // Title & Metrics
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("CLIProxy")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("8317")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(NSColor.separatorColor).opacity(0.25))
                        .cornerRadius(3)
                }
                
                HStack(spacing: 4) {
                    Text("\(client.readyCount) ready")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(NSColor.systemGreen))
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    
                    Text("\(client.cooldownCount) cooling")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(client.cooldownCount > 0 ? Color(NSColor.systemOrange) : .secondary)
                    
                    if let soonest = client.soonestCooldownSeconds, soonest > 0 {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("next \(formatSeconds(soonest))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(NSColor.systemTeal))
                    }
                }
            }
            
            Spacer()
            
            // Actions (Clean Apple-Style Buttons)
            HStack(spacing: 5) {
                Button(action: { client.runRebalance() }) {
                    Text(client.isRebalancing ? "Rebalancing…" : "Rebalance")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(client.isRebalancing)
                .help("Run Soonest-Reset Priority Rebalancer")
                
                Menu {
                    Button("Refresh Quota") {
                        Task { await client.fetchAuthFiles() }
                    }
                    Button("Open Config Directory") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: NSString(string: "~/.cli-proxy-api").expandingTildeInPath)
                    }
                    Divider()
                    Button("Quit CLIProxyBar") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Text("•••")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Account Card View (Zero-Shadow, Layering, Apple HIG)

struct AccountCardView: View {
    let account: NormalizedAccount
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Header (Email + Provider Tag + Priority + Status Dot)
            HStack(alignment: .center, spacing: 6) {
                // Status Indicator Dot
                Circle()
                    .fill(statusColor(account.status))
                    .frame(width: 5, height: 5)
                
                // Account Email
                Text(account.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(account.isDisabled ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                // Provider Tag
                Text(account.provider.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(NSColor.separatorColor).opacity(0.2))
                    .cornerRadius(3)
                
                // Priority Tag
                Text("P\(account.priority)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // Status Text / Countdown
                StatusText(status: account.status, remainingSeconds: account.cooldownRemainingSeconds)
            }
            
            // Row 2: 5-Hour Limit Row
            if let primary = account.primaryUsedPercent {
                MetricRow(
                    label: "5h Limit",
                    percent: primary,
                    resetSeconds: account.primaryResetSeconds
                )
            }
            
            // Row 3: 7-Day Limit Row
            if let secondary = account.secondaryUsedPercent {
                MetricRow(
                    label: "7d Limit",
                    percent: secondary,
                    resetSeconds: account.secondaryResetSeconds
                )
            }
            
            // Row 4: Locked Models (if in cooldown)
            if !account.coolingModels.isEmpty {
                HStack(spacing: 4) {
                    Text("Locked:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(NSColor.systemOrange))
                    
                    Text(account.coolingModels.joined(separator: ", "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor).opacity(0.35), lineWidth: 0.5)
        )
    }
    
    private func statusColor(_ st: AccountStatus) -> Color {
        switch st {
        case .ready: return Color(NSColor.systemGreen)
        case .cooldown: return Color(NSColor.systemOrange)
        case .disabled: return Color(NSColor.disabledControlTextColor)
        case .error: return Color(NSColor.systemRed)
        }
    }
}

// MARK: - Metric Row & Progress Bar

struct MetricRow: View {
    let label: String
    let percent: Double
    let resetSeconds: Int?
    
    var tintColor: Color {
        if percent >= 95 { return Color(NSColor.systemRed) }
        if percent >= 75 { return Color(NSColor.systemOrange) }
        return Color(NSColor.systemGreen)
    }
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 3) {
                    Text("\(Int(percent))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(tintColor)
                    
                    if let sec = resetSeconds, sec > 0 {
                        Text("(\(formatSeconds(sec)))")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress Track (Thin, 2.5px, Apple Style)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(NSColor.separatorColor).opacity(0.25))
                        .frame(height: 2.5)
                    
                    Capsule()
                        .fill(tintColor)
                        .frame(width: max(0, min(geo.size.width * CGFloat(percent / 100.0), geo.size.width)), height: 2.5)
                }
            }
            .frame(height: 2.5)
        }
    }
}

// MARK: - Status Text (Typography-First, No Bloated Icons)

struct StatusText: View {
    let status: AccountStatus
    let remainingSeconds: Int
    
    var body: some View {
        if status == .cooldown && remainingSeconds > 0 {
            Text(formatSeconds(remainingSeconds))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(NSColor.systemOrange))
        } else {
            Text(status.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(status == .ready ? Color(NSColor.systemGreen) : .secondary)
        }
    }
}

// MARK: - Empty State View (Decisive, 1-Line, No Illustration)

struct EmptyStateView: View {
    @ObservedObject var client: ProxyClient
    
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No Active Accounts")
                .font(.system(size: 13, weight: .semibold))
            
            Text(client.statusMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            
            Button("Retry") {
                Task { await client.fetchAuthFiles() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer View (Subtle, Clean Metadata)

struct FooterView: View {
    @ObservedObject var client: ProxyClient
    
    var timeString: String {
        guard let d = client.lastUpdated else { return "--:--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
    
    var body: some View {
        HStack {
            Text("Updated \(timeString)")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(client.totalCount) accounts loaded")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
