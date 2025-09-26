import SwiftUI
import AppKit

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
            }

            Text("CommandTilde")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Made with 🍵 by Vladyslav Shvedov")
                .font(.body)

            VStack(spacing: 8) {
                Button(action: {
                    if let url = URL(string: "mailto:mail@vlad.codes") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("mail@vlad.codes")
                        .foregroundColor(.blue)
                        .underline()
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    if let url = URL(string: "https://vlad.codes") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("https://vlad.codes")
                        .foregroundColor(.blue)
                        .underline()
                }
                .buttonStyle(PlainButtonStyle())
            }
            .font(.caption)

            Spacer()
        }
        .padding()
        .frame(width: 360, height: 320)
    }
}

#Preview {
    AboutView()
}