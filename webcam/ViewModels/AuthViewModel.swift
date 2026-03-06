import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Input (UI)
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var phone = ""

    // MARK: - State
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isLoggedIn = false

    private let authService = AuthService.shared

    init() {
        isLoggedIn = authService.isLoggedIn()
    }

    // MARK: - LOGIN
    func login() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Введите email и пароль"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await authService.login(email: email, password: password)
            isLoggedIn = authService.isLoggedIn()
            print("✅ Вход успешен")
        } catch {
            print("❌ Login failed:", error)
            errorMessage = "Неверный email или пароль"
        }
    }

    // MARK: - REGISTER
    func register() async {
        guard validateRegistration() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await authService.register(
                email: email,
                password: password,
                passwordConfirm: confirmPassword,
                firstName: firstName,
                lastName: lastName,
                phone: phone
            )

            isLoggedIn = authService.isLoggedIn()
            print("✅ Регистрация успешна")
            print("🔑 ACCESS:", response.resolvedAccess ?? "nil")
            print("🔑 REFRESH:", response.resolvedRefresh ?? "nil")

        } catch {
            print("❌ Ошибка регистрации:", error)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - LOGOUT
    func logout() {
        authService.logout()
        clearFields()
        isLoggedIn = false
    }

    // MARK: - Validation
    private func validateRegistration() -> Bool {
        if email.isEmpty ||
            password.isEmpty ||
            confirmPassword.isEmpty ||
            firstName.isEmpty ||
            lastName.isEmpty {
            errorMessage = "Заполните все обязательные поля"
            return false
        }

        if password != confirmPassword {
            errorMessage = "Пароли не совпадают"
            return false
        }

        if password.count < 6 {
            errorMessage = "Пароль минимум 6 символов"
            return false
        }

        return true
    }

    private func clearFields() {
        email = ""
        password = ""
        confirmPassword = ""
        firstName = ""
        lastName = ""
        phone = ""
    }
}
