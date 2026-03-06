import SwiftUI

struct EditCameraView: View {
    let camera: Camera

    let onSave: (_ name: String, _ address: String) async -> Void
    let onDelete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var address: String = ""

    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Form {
                    Section("Данные камеры") {
                        TextField("Имя камеры", text: $name)
                            .textInputAutocapitalization(.words)

                        TextField("Адрес камеры", text: $address)
                            .textInputAutocapitalization(.never)
                    }
                }
                .scrollDismissesKeyboard(.interactively) // свайп вниз прячет клаву (iOS 16+)
                .onTapGesture { hideKeyboard() }

                Button {
                    Task { await saveTapped() }
                } label: {
                    if isSaving {
                        HStack { ProgressView(); Text("Сохранение...") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Сохранить изменения")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !canSave)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .navigationTitle("Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Удалить камеру?", isPresented: $showDeleteConfirm) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) {
                    Task { await deleteTapped() }
                }
            } message: {
                Text("Вы точно уверены, что хотите удалить камеру «\(camera.name)»? Это действие нельзя отменить.")
            }
            .onAppear {
                name = camera.name
                address = cameraAddressFromModel(camera) // ⚠️ подставь поле адреса, если есть
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveTapped() async {
        hideKeyboard()
        isSaving = true
        defer { isSaving = false }

        await onSave(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }

    private func deleteTapped() async {
        hideKeyboard()
        isSaving = true
        defer { isSaving = false }

        await onDelete()
        dismiss()
    }

    private func cameraAddressFromModel(_ camera: Camera) -> String {
        // ⚠️ Вставь реальное поле из Camera:
        // return camera.address
        // return camera.url
        // return camera.rtsp
        return ""
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
