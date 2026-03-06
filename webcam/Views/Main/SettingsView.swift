import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("videoQuality") private var videoQuality = "HD"
    @AppStorage("autoPlay") private var autoPlay = true
    
    var body: some View {
        List {
            Section("Аккаунт") {
                if let email = UserDefaults.standard.string(forKey: "userEmail") {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Пользователь")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(email)
                        }
                    }
                }
                
                Button("Выйти") {
                    authViewModel.logout()
                }
                .foregroundColor(.red)
            }
            
            Section("Настройки видео") {
                Picker("Качество видео", selection: $videoQuality) {
                    Text("SD (480p)").tag("SD")
                    Text("HD (720p)").tag("HD")
                    Text("Full HD (1080p)").tag("FHD")
                }
                
                Toggle("Автовоспроизведение", isOn: $autoPlay)
                
                Toggle("Уведомления", isOn: $notificationsEnabled)
            }
            
            Section("О приложении") {
                HStack {
                    Text("Версия")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                Link("Политика конфиденциальности",
                     destination: URL(string: "https://example.com/privacy")!)
                
                Link("Поддержка",
                     destination: URL(string: "mailto:support@example.com")!)
            }
        }
        .navigationTitle("Настройки")
    }
}
