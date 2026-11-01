import SwiftUI

// MARK: - Main Popover View

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
                .opacity(0.3)
            
            // Filter Pills
            if providers.count > 2 {
                FilterBarView(providers: providers, selected: $selectedProvider, accounts: client.accounts)
                
                Divider()
                    .opacity(0.2)
            }
            
            // Account List
            if client.accounts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(client.statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Button("Retry Connection") {
                        Task { await client.fetchAuthFiles() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredAccounts) { acc in
                            AccountCardView(account: acc)
                        }
                    }
                    .padding(10)
                }
            }
            
            Divider()
                .opacity(0.3)
            
            // Footer
            FooterView(client: client)
        }
        .frame(width: 380, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var client: ProxyClient
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Status Indicator
            Circle()
                .fill(client.isConnected ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("CLIProxy Monitor")
                    .font(.system(size: 13, weight: .semibold))
                
                HStack(spacing: 6) {
                    Text("\(client.readyCount) Ready")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                    
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    
                    Text("\(client.cooldownCount) Cooling")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(client.cooldownCount > 0 ? .orange : .secondary)
                    
                    if let soonest = client.soonestCooldownSeconds, soonest > 0 {
                        Text("•")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("Next: \(formatSeconds(soonest))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 6) {
                // Rebalance Button
                Button(action: { client.runRebalance() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text(client.isRebalancing ? "..." : "Rebalance")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(client.isRebalancing)
                .help("Run Soonest-Reset Rebalancer")
                
                // Refresh Button
                Button(action: {
                    Task { await client.fetchAuthFiles() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Refresh Quota")
                
                // Quit Button
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Quit CLIProxy Bar")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Filter Bar

struct FilterBarView: View {
    let providers: [String]
    @Binding var selected: String
    let accounts: [NormalizedAccount]
    
    func countFor(prov: String) -> Int {
        if prov == "ALL" { return accounts.count }
        return accounts.filter { $0.provider.uppercased() == prov }.count
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(providers, id: \.self) { p in
                Button(action: { selected = p }) {
                    Text("\(p) (\(countFor(prov: p)))")
                        .font(.system(size: 10, weight: selected == p ? .semibold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(selected == p ? Color.accentColor.opacity(0.2) : Color.clear)
                        .foregroundColor(selected == p ? .accentColor : .secondary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

// MARK: - Account Card

struct AccountCardView: View {
    let account: NormalizedAccount
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Provider badge + Email + Priority + Status badge
            HStack(alignment: .center, spacing: 6) {
                // Provider label
                Text(account.provider.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(3)
                
                // Email
                Text(account.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                // Priority pill
                Text("P\(account.priority)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
                
                // Status Badge
                StatusBadge(status: account.status, remainingSeconds: account.cooldownRemainingSeconds)
            }
            
            // Row 2: 5-Hour / Primary limit
            if let primary = account.primaryUsedPercent {
                QuotaRow(
                    label: "5h Limit",
                    percent: primary,
                    resetSeconds: account.primaryResetSeconds
                )
            }
            
            // Row 3: 7-Day / Secondary limit
            if let secondary = account.secondaryUsedPercent {
                QuotaRow(
                    label: "7d Limit",
                    percent: secondary,
                    resetSeconds: account.secondaryResetSeconds
                )
            }
            
            // Cooldown Models row (if any)
            if !account.coolingModels.isEmpty {
                HStack(spacing: 4) {
                    Text("Cooldown:")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                    
                    Text(account.coolingModels.joined(separator: ", "))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 1)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Quota Row with Progress Bar

struct QuotaRow: View {
    let label: String
    let percent: Double
    let resetSeconds: Int?
    
    var barColor: Color {
        if percent >= 95 { return .red }
        if percent >= 75 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("\(Int(percent))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(barColor)
                    
                    if let sec = resetSeconds, sec > 0 {
                        Text("(resets \(formatSeconds(sec)))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress Bar Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 3)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: max(0, min(geo.size.width * CGFloat(percent / 100.0), geo.size.width)), height: 3)
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: AccountStatus
    let remainingSeconds: Int
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            
            if status == .cooldown && remainingSeconds > 0 {
                Text(formatSeconds(remainingSeconds))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            } else {
                Text(status.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(status.color)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12))
        .cornerRadius(4)
    }
}

// MARK: - Footer View

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
            Text("Updated: \(timeString)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Open Config") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: NSString(string: "~/.cli-proxy-api").expandingTildeInPath)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
}
