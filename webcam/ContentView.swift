import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        Group {
            if authViewModel.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var cameraViewModel = CameraListViewModel()
    
    var body: some View {
        TabView {
            NavigationStack {
                CameraListView()
                    .environmentObject(cameraViewModel)
            }
            .tabItem {
                Label("Камеры", systemImage: "video.fill")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Настройки", systemImage: "gear")
            }
        }
    }
}
