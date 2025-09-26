import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Settings panel coming soon...")
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .frame(width: 480, height: 320)
    }
}

#Preview {
    SettingsView()
}