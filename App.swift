import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CLIProxyBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var client = ProxyClient()
    
    var body: some Scene {
        MenuBarExtra {
            MainView(client: client)
        } label: {
            MenuBarLabelView(client: client)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Glance Label (Multi-Account Grouped by Provider)

func createGlanceImage(groups: [ProviderGlanceGroup]) -> NSImage {
    // Native macOS menu bar typography: Apple San Francisco with tabular figures
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
    
    let logoSize: CGFloat = 14.0
    let spacingAfterLogo: CGFloat = 4.5
    let spacingBetweenGroups: CGFloat = 10.0
    let height: CGFloat = 22.0
    
    let sepStr = " • " as NSString
    let sepWidth = ceil(sepStr.size(withAttributes: [.font: font]).width)
    
    struct AccountMeasure {
        let isCooldown: Bool
        let text: String
        let textWidth: CGFloat
    }
    
    struct GroupMeasure {
        let img: NSImage?
        let accounts: [AccountMeasure]
        let groupWidth: CGFloat
    }
    
    var groupMeasures: [GroupMeasure] = []
    var totalWidth: CGFloat = 0
    
    for (gIdx, g) in groups.enumerated() {
        let img = loadProviderLogo(provider: g.provider)
        
        var accMeasures: [AccountMeasure] = []
        var gWidth: CGFloat = logoSize + spacingAfterLogo
        
        for (aIdx, acc) in g.accounts.enumerated() {
            let isCooldown = (acc.status == .cooldown && acc.cooldownRemainingSeconds > 0)
            let strText: String
            if isCooldown {
                strText = formatSeconds(acc.cooldownRemainingSeconds)
            } else if let pct = acc.primaryUsedPercent {
                strText = "\(Int(pct))%"
            } else {
                strText = acc.status == .ready ? "Ready" : acc.status.rawValue
            }
            
            let w = ceil((strText as NSString).size(withAttributes: [.font: font]).width)
            accMeasures.append(AccountMeasure(isCooldown: isCooldown, text: strText, textWidth: w))
            
            if aIdx > 0 {
                gWidth += sepWidth
            }
            gWidth += w
        }
        
        groupMeasures.append(GroupMeasure(img: img, accounts: accMeasures, groupWidth: gWidth))
        totalWidth += gWidth
        if gIdx < groups.count - 1 {
            totalWidth += spacingBetweenGroups
        }
    }
    
    guard totalWidth > 0 else {
        return NSImage(size: NSSize(width: 1, height: height))
    }
    
    let result = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { bounds in
        // Dynamically resolve colors according to current menu bar drawing appearance (Light vs Dark)
        let isDark = NSAppearance.currentDrawing().name.rawValue.lowercased().contains("dark")
        let textColor = isDark ? NSColor(white: 0.98, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
        let sepColor = isDark ? NSColor(white: 0.60, alpha: 0.75) : NSColor(white: 0.35, alpha: 0.75)
        let orangeColor = isDark ? NSColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 1.0) : NSColor(red: 0.82, green: 0.38, blue: 0.0, alpha: 1.0)
        
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let orangeAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: orangeColor]
        let sepAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: sepColor]
        
        var currentX: CGFloat = 0
        for (gIdx, gm) in groupMeasures.enumerated() {
            // Draw logo centered vertically
            if let logo = gm.img {
                let logoY = (height - logoSize) / 2.0
                logo.draw(in: NSRect(x: currentX, y: logoY, width: logoSize, height: logoSize),
                          from: .zero,
                          operation: .sourceOver,
                          fraction: 1.0)
            }
            currentX += logoSize + spacingAfterLogo
            
            // Draw accounts
            for (aIdx, am) in gm.accounts.enumerated() {
                if aIdx > 0 {
                    let sepY = (height - sepStr.size(withAttributes: sepAttrs).height) / 2.0
                    sepStr.draw(at: NSPoint(x: currentX, y: sepY), withAttributes: sepAttrs)
                    currentX += sepWidth
                }
                
                let attrs = am.isCooldown ? orangeAttrs : textAttrs
                let textY = (height - (am.text as NSString).size(withAttributes: attrs).height) / 2.0
                (am.text as NSString).draw(at: NSPoint(x: currentX, y: textY), withAttributes: attrs)
                currentX += am.textWidth
            }
            
            if gIdx < groupMeasures.count - 1 {
                currentX += spacingBetweenGroups
            }
        }
        
        return true
    }
    
    result.isTemplate = false
    return result
}

struct MenuBarLabelView: View {
    @ObservedObject var client: ProxyClient
    
    var groups: [ProviderGlanceGroup] {
        client.glanceGroups
    }
    
    var body: some View {
        if !client.isConnected {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .medium))
                Text("Offline")
                    .font(.system(size: 12.5, weight: .medium))
            }
        } else if groups.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .medium))
                Text("0/0")
                    .font(.system(size: 12.5, weight: .medium))
            }
        } else {
            Image(nsImage: createGlanceImage(groups: groups))
        }
    }
}
