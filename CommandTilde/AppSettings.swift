import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let playDropSound = "playDropSound"
    }

    @Published var playDropSound: Bool {
        didSet {
            UserDefaults.standard.set(playDropSound, forKey: Keys.playDropSound)
        }
    }

    init() {
        UserDefaults.standard.register(defaults: [Keys.playDropSound: true])
        self.playDropSound = UserDefaults.standard.bool(forKey: Keys.playDropSound)
    }
}
