import SwiftUI

struct LoginView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var showingRegister = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Logo
                        Image(systemName: "video.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .padding(.top, 50)
                        
                        Text("Видеонаблюдение")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Вход в систему")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        // Form
                        VStack(spacing: 16) {
                            TextField("Email", text: $viewModel.email)
                                .textFieldStyle(AuthTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                            
                            SecureField("Пароль", text: $viewModel.password)
                                .textFieldStyle(AuthTextFieldStyle())
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                        }
                        .padding(.horizontal, 24)
                        
                        // Error Message
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Login Button
                        Button(action: {
                            Task {
                                await viewModel.login()
                            }
                        }) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Войти")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(viewModel.isLoading)
                        .padding(.horizontal, 24)
                        
                        // Register Button
                        Button("Нет аккаунта? Зарегистрироваться") {
                            showingRegister = true
                        }
                        .foregroundColor(.blue)
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $viewModel.isLoggedIn) {
                MainTabView()
            }
            .sheet(isPresented: $showingRegister) {
                RegisterView()
            }
            .onSubmit {
                switch focusedField {
                case .email:
                    focusedField = .password
                case .password:
                    Task {
                        await viewModel.login()
                    }
                default:
                    break
                }
            }
        }
    }
}
