import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("CommandTilde")
                .font(.title)
                .fontWeight(.bold)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutView()
        .frame(width: 350, height: 200)
}