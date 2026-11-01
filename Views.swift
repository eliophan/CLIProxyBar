import SwiftUI
import AppKit

// MARK: - Main Popover View (Apple Inset-Grouped Native Style)

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
                .overlay(Color(NSColor.separatorColor).opacity(0.3))
            
            // Filter Pills Bar (Native horizontal capsule pills)
            if providers.count > 2 {
                FilterPillsView(providers: providers, selected: $selectedProvider, accounts: client.accounts)
                
                Divider()
                    .overlay(Color(NSColor.separatorColor).opacity(0.2))
            }
            
            // Account List in Inset-Grouped Container
            if client.accounts.isEmpty {
                EmptyStateView(client: client)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredAccounts.enumerated()), id: \.element.id) { index, acc in
                            AccountRowView(account: acc)
                            
                            if index < filteredAccounts.count - 1 {
                                Divider()
                                    .padding(.leading, 24)
                                    .overlay(Color(NSColor.separatorColor).opacity(0.2))
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            
            Divider()
                .overlay(Color(NSColor.separatorColor).opacity(0.3))
            
            // Footer Bar
            FooterView(client: client)
        }
        .frame(width: 370, height: 480)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Header Bar (Clean, Rebalance inside ••• Menu)

struct HeaderView: View {
    @ObservedObject var client: ProxyClient
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Status Dot
            Circle()
                .fill(client.isConnected ? Color(NSColor.systemGreen) : Color(NSColor.systemRed))
                .frame(width: 7, height: 7)
            
            // Title & Status
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("CLIProxy")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("8317")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(NSColor.separatorColor).opacity(0.2))
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
            
            // Native Action Menu
            Menu {
                Button(action: { client.runRebalance() }) {
                    Label(client.isRebalancing ? "Rebalancing…" : "Rebalance Priorities (Soonest Reset)", systemImage: "bolt.fill")
                }
                .disabled(client.isRebalancing)
                
                Button(action: {
                    Task { await client.fetchAuthFiles() }
                }) {
                    Label("Refresh Quota", systemImage: "arrow.clockwise")
                }
                
                Divider()
                
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: NSString(string: "~/.cli-proxy-api").expandingTildeInPath)
                }) {
                    Label("Reveal Config in Finder", systemImage: "folder")
                }
                
                Divider()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("Quit CLIProxyBar", systemImage: "power")
                }
            } label: {
                Text("•••")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 20)
                    .background(Color(NSColor.separatorColor).opacity(0.15))
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Filter Pills (Horizontal Apple Capsule Style)

struct FilterPillsView: View {
    let providers: [String]
    @Binding var selected: String
    let accounts: [NormalizedAccount]
    
    func countFor(prov: String) -> Int {
        if prov == "ALL" { return accounts.count }
        return accounts.filter { $0.provider.uppercased() == prov }.count
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(providers, id: \.self) { p in
                    Button(action: { selected = p }) {
                        Text("\(p.capitalized) (\(countFor(prov: p)))")
                            .font(.system(size: 10, weight: selected == p ? .semibold : .regular))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(selected == p ? Color(NSColor.controlAccentColor).opacity(0.18) : Color.clear)
                            .foregroundColor(selected == p ? Color(NSColor.controlAccentColor) : .secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }
}

// MARK: - Masked Email View (Middle blurred, click to reveal full email)

struct MaskedEmailView: View {
    let email: String
    @State private var isRevealed: Bool = false
    
    private var parts: (prefix: String, middle: String, suffix: String) {
        let total = email.count
        guard total >= 6 else {
            return (email, "", "")
        }
        
        let prefixLen: Int
        let suffixLen: Int
        
        if total >= 20 {
            prefixLen = 3
            suffixLen = 7
        } else if total >= 14 {
            prefixLen = 2
            suffixLen = 6
        } else {
            prefixLen = 1
            suffixLen = 4
        }
        
        let pre = String(email.prefix(prefixLen))
        let suf = String(email.suffix(suffixLen))
        let mid = String(email.dropFirst(prefixLen).dropLast(suffixLen))
        
        return (pre, mid, suf)
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                isRevealed.toggle()
            }
        }) {
            HStack(spacing: 0) {
                if isRevealed {
                    Text(email)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    let p = parts
                    Text(p.prefix)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    if !p.middle.isEmpty {
                        Text(p.middle)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .blur(radius: 3.5)
                    }
                    
                    Text(p.suffix)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isRevealed ? "Click to blur email" : "Click to reveal full email")
    }
}

// MARK: - Account Row View (Clean Inset Row)

struct AccountRowView: View {
    let account: NormalizedAccount
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: Status Dot + Masked Email + Provider + Priority + Countdown
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(statusColor(account.status))
                    .frame(width: 5, height: 5)
                
                // Masked Email with Click to Reveal
                MaskedEmailView(email: account.displayName)
                
                Spacer()
                
                Text(account.provider.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color(NSColor.separatorColor).opacity(0.2))
                    .cornerRadius(2)
                
                Text("P\(account.priority)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                if account.status == .cooldown && account.cooldownRemainingSeconds > 0 {
                    Text(formatSeconds(account.cooldownRemainingSeconds))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(NSColor.systemOrange))
                } else {
                    Text(account.status.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(account.status == .ready ? Color(NSColor.systemGreen) : .secondary)
                }
            }
            
            // Line 2: 5-Hour Limit Bar (if available)
            if let primary = account.primaryUsedPercent {
                MiniProgressBar(
                    label: "5h",
                    percent: primary,
                    resetSeconds: account.primaryResetSeconds
                )
            }
            
            // Line 3: 7-Day Limit Bar (if available)
            if let secondary = account.secondaryUsedPercent {
                MiniProgressBar(
                    label: "7d",
                    percent: secondary,
                    resetSeconds: account.secondaryResetSeconds
                )
            }
            
            // Line 4: Metadata for providers without % signals (Antigravity & Meta)
            if account.primaryUsedPercent == nil, let details = account.planDetails {
                HStack(spacing: 4) {
                    Text(details)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 1)
            }
            
            // Line 5: Locked Models (if in cooldown)
            if !account.coolingModels.isEmpty {
                HStack(spacing: 3) {
                    Text("Locked:")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(Color(NSColor.systemOrange).opacity(0.8))
                    
                    Text(account.coolingModels.joined(separator: ", "))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

// MARK: - Mini Progress Bar (Sleek Apple Track)

struct MiniProgressBar: View {
    let label: String
    let percent: Double
    let resetSeconds: Int?
    
    var tintColor: Color {
        if percent >= 95 { return Color(NSColor.systemRed) }
        if percent >= 75 { return Color(NSColor.systemOrange) }
        return Color(NSColor.systemGreen)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .leading)
            
            // Progress Bar Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(NSColor.separatorColor).opacity(0.2))
                        .frame(height: 2.5)
                    
                    Capsule()
                        .fill(tintColor)
                        .frame(width: max(0, min(geo.size.width * CGFloat(percent / 100.0), geo.size.width)), height: 2.5)
                }
            }
            .frame(height: 2.5)
            
            HStack(spacing: 2) {
                Text("\(Int(percent))%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(tintColor)
                
                if let sec = resetSeconds, sec > 0 {
                    Text("(\(formatSeconds(sec)))")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 80, alignment: .trailing)
        }
    }
}

// MARK: - Empty State View

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
            
            Button("Retry Connection") {
                Task { await client.fetchAuthFiles() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text("Updated \(timeString)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(client.totalCount) accounts loaded")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
