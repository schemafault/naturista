import SwiftUI

// Paper-styled replacement for SwiftUI's stock confirmationDialog. Uses
// the design system fonts and button styles so confirmations look like
// the rest of the app instead of a system dialog. Present with `.sheet`
// (window-attached) for the same modal semantics.
struct ConfirmModal: View {
    let title: String
    let message: String
    let confirmLabel: String
    var cancelLabel: String = "Cancel"
    var eyebrow: String = "Confirm"
    var isDestructive: Bool = false
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(DS.serif(22, weight: .regular))
                .foregroundColor(DS.ink)
                .kerning(-0.2)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(DS.sans(12.5))
                .foregroundColor(DS.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                Button(cancelLabel, action: onCancel)
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                if isDestructive {
                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(DestructiveButtonStyle())
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 420)
        .background(DS.paper)
    }
}

extension View {
    // Bool-flag form: title and message are static.
    func confirmModal(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmLabel: String,
        cancelLabel: String = "Cancel",
        eyebrow: String = "Confirm",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmModal(
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                eyebrow: eyebrow,
                isDestructive: isDestructive,
                onCancel: { isPresented.wrappedValue = false },
                onConfirm: {
                    isPresented.wrappedValue = false
                    onConfirm()
                }
            )
        }
    }

    // Optional-data form: present only when `item` is non-nil; title and
    // message are computed from the bound value so the dialog can name
    // the thing being confirmed (e.g. "Delete \"ugly\"?").
    func confirmModal<T>(
        item: Binding<T?>,
        title: @escaping (T) -> String,
        message: @escaping (T) -> String,
        confirmLabel: String,
        cancelLabel: String = "Cancel",
        eyebrow: String = "Confirm",
        isDestructive: Bool = false,
        onConfirm: @escaping (T) -> Void
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
        return sheet(isPresented: isPresented) {
            if let value = item.wrappedValue {
                ConfirmModal(
                    title: title(value),
                    message: message(value),
                    confirmLabel: confirmLabel,
                    cancelLabel: cancelLabel,
                    eyebrow: eyebrow,
                    isDestructive: isDestructive,
                    onCancel: { item.wrappedValue = nil },
                    onConfirm: {
                        item.wrappedValue = nil
                        onConfirm(value)
                    }
                )
            }
        }
    }
}
