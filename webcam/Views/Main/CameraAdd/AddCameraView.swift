import SwiftUI

struct AddCameraView: View {

    // MARK: - State
    @Environment(\.dismiss) var dismiss
    @State private var step: AddCameraStep = .name

    @State private var name = ""
    @State private var mac = ""
    @State private var login = "admin"
    @State private var password = "admin"

    @State private var showScanner = false
    @State private var showCancelAlert = false
    
    // Для управления клавиатурой
    @FocusState private var focusedField: Field?
    @State private var keyboardHeight: CGFloat = 0

    // MARK: - Enum для управления фокусом
    private enum Field: Int, Hashable {
        case name, mac, login, password
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Основной контент с прокруткой
                ScrollView {
                    VStack(spacing: 0) {
                        // Индикатор шагов
                        stepIndicator
                            .padding(.top, 20)
                            .padding(.bottom, 30)
                        
                        // Динамический контент шагов
                        Group {
                            switch step {
                            case .name:
                                stepNameContent
                            case .mac:
                                stepMacContent
                            case .credentials:
                                stepCredentialsContent
                            }
                        }
                        .padding(.horizontal)
                        
                        // Пустое пространство для клавиатуры
                        Color.clear
                            .frame(height: max(0, keyboardHeight - 100))
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                
                // Кнопки внизу (фиксированные)
                footerButtons
                    .background(
                        Rectangle()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 5, y: -2)
                    )
                    .padding(.bottom, keyboardHeight > 0 ? 0 : 20)
                    .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        if !name.isEmpty || !mac.isEmpty || login != "admin" || password != "admin" {
                            showCancelAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Добавление камеры")
                        .font(.headline)
                }
                
                // Кнопка "Готово" на клавиатуре
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    
                    Button("Готово") {
                        hideKeyboard()
                    }
                    .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedMac in
                    withAnimation {
                        mac = formatMAC(scannedMac)
                        showScanner = false
                        
                        // После сканирования переходим к следующему шагу
                        if step == .mac && mac.count == 17 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                step = .credentials
                            }
                        }
                    }
                }
            }
            .alert("Отменить добавление?", isPresented: $showCancelAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Да, отменить", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("Все введенные данные будут потеряны.")
            }
            .onAppear {
                // Начинаем с фокуса на первом поле
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    focusedField = .name
                }
                
                // Наблюдаем за клавиатурой
                setupKeyboardObservers()
            }
            .onDisappear {
                // Удаляем наблюдателей
                removeKeyboardObservers()
            }
            .gesture(
                TapGesture()
                    .onEnded { _ in
                        hideKeyboard()
                    }
            )
            .onChange(of: step) { newStep in
                // При смене шага сбрасываем фокус
                focusedField = nil
                
                // Автофокус на первом поле шага
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    switch newStep {
                    case .name:
                        focusedField = .name
                    case .mac:
                        focusedField = .mac
                    case .credentials:
                        focusedField = .login
                    }
                }
            }
        }
    }

    // MARK: - Step Indicator
    private var stepIndicator: some View {
        VStack(spacing: 8) {
            Text("Шаг \(step.rawValue + 1) из 3")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= step.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: index == step.rawValue ? 24 : 10, height: 8)
                        .animation(.spring(), value: step)
                }
            }
        }
    }

    // MARK: - Step 1 Content
    private var stepNameContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("Название камеры")
                    .font(.title2)
                    .bold()
                
                Text("Дайте камере понятное название")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            InputCard {
                TextField("Например: Прихожая", text: $name)
                    .font(.body)
                    .padding(.vertical, 12)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit {
                        // При нажатии "Далее" на клавиатуре
                        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                            step = .mac
                        }
                    }
            }
        }
    }

    // MARK: - Step 2 Content
    private var stepMacContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "number.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("MAC-адрес")
                    .font(.title2)
                    .bold()
                
                Text("Введите MAC-адрес камеры или отсканируйте QR-код")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            InputCard {
                HStack {
                    TextField("AA:BB:CC:DD:EE:FF", text: $mac)
                        .keyboardType(.asciiCapable)
                        .onChange(of: mac) { mac = formatMAC($0) }
                        .font(.body.monospaced())
                        .focused($focusedField, equals: .mac)
                        .submitLabel(.next)
                        .onSubmit {
                            // При нажатии "Далее" на клавиатуре
                            if mac.count == 17 {
                                step = .credentials
                            }
                        }

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 8)
                }
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Step 3 Content
    private var stepCredentialsContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.8))
            
            VStack(spacing: 8) {
                Text("Данные для входа")
                    .font(.title2)
                    .bold()
                
                Text("Введите логин и пароль для доступа к камере")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            InputCard {
                VStack(spacing: 16) {
                    TextField("Логин", text: $login)
                        .font(.body)
                        .padding(.vertical, 12)
                        .focused($focusedField, equals: .login)
                        .submitLabel(.next)
                        .onSubmit {
                            // При нажатии "Далее" на клавиатуре
                            focusedField = .password
                        }
                    
                    Divider()
                        .padding(.horizontal, -16)
                    
                    SecureField("Пароль", text: $password)
                        .font(.body)
                        .padding(.vertical, 12)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.done)
                        .onSubmit {
                            // При нажатии "Готово" на клавиатуре
                            if isStepValid {
                                addCamera()
                            }
                        }
                }
            }
        }
    }

    // MARK: - Footer Buttons
    private var footerButtons: some View {
        VStack(spacing: 12) {
            if step.rawValue > 0 {
                Button {
                    hideKeyboard()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = AddCameraStep(rawValue: step.rawValue - 1)!
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Назад")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 24)
            }

            Button {
                hideKeyboard()
                withAnimation(.easeInOut(duration: 0.3)) {
                    if step == .credentials {
                        addCamera()
                    } else {
                        step = AddCameraStep(rawValue: step.rawValue + 1)!
                    }
                }
            } label: {
                Text(step == .credentials ? "Добавить камеру" : "Далее")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isStepValid ? Color.blue : Color.gray.opacity(0.4))
                    .cornerRadius(10)
            }
            .disabled(!isStepValid)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .padding(.top, 16)
    }

    // MARK: - Validation
    private var isStepValid: Bool {
        switch step {
        case .name:
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .mac:
            return mac.count == 17
        case .credentials:
            return !login.isEmpty && !password.isEmpty
        }
    }
    
    // MARK: - Add Camera Action
    private func addCamera() {
        // TODO: Реализовать добавление камеры в базу данных/сервер
        print("Добавляем камеру:")
        print("Название: \(name)")
        print("MAC: \(mac)")
        print("Логин: \(login)")
        print("Пароль: \(password)")
        
        // Здесь должна быть логика сохранения камеры
        // После успешного сохранения:
        dismiss()
    }
    
    // MARK: - Keyboard Handling
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
