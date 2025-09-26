import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)

            Form {
                Section("Feedback") {
                    Toggle("Play sound after files are added", isOn: $settings.playDropSound)
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .padding()
        .frame(width: 480, height: 320)
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}
