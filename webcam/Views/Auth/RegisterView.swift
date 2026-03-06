import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    enum Field {
        case firstName
        case lastName
        case email
        case phone
        case password
        case confirmPassword
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        Text("Регистрация")
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.top)

                        VStack(spacing: 12) {

                            TextField("Имя*", text: $viewModel.firstName)
                                .textFieldStyle(AuthTextFieldStyle())
                                .focused($focusedField, equals: .firstName)
                                .submitLabel(.next)

                            TextField("Фамилия*", text: $viewModel.lastName)
                                .textFieldStyle(AuthTextFieldStyle())
                                .focused($focusedField, equals: .lastName)
                                .submitLabel(.next)

                            TextField("Email*", text: $viewModel.email)
                                .textFieldStyle(AuthTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)

                            TextField("Телефон", text: $viewModel.phone)
                                .textFieldStyle(AuthTextFieldStyle())
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .phone)
                                .submitLabel(.next)

                            SecureField("Пароль*", text: $viewModel.password)
                                .textFieldStyle(AuthTextFieldStyle())
                                .focused($focusedField, equals: .password)
                                .submitLabel(.next)

                            SecureField("Подтвердите пароль*", text: $viewModel.confirmPassword)
                                .textFieldStyle(AuthTextFieldStyle())
                                .focused($focusedField, equals: .confirmPassword)
                                .submitLabel(.go)
                        }
                        .padding(.horizontal)

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button {
                            Task {
                                await viewModel.register()
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(
                                        CircularProgressViewStyle(tint: .white)
                                    )
                            } else {
                                Text("Зарегистрироваться")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(viewModel.isLoading)
                        .padding(.horizontal)

                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .onChange(of: viewModel.isLoggedIn) { _, newValue in
                if newValue {
                    dismiss()
                }
            }
        }
    }
}
