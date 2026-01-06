import SwiftUI

struct ReusableCurrencyTextField: View {

    @Binding var value: String?
    @State private var stringValue: String = ""

    init(value: Binding<String?>) {
        _value = value
        _stringValue = State(initialValue: value.wrappedValue ?? "")
    }

    var body: some View {
        let stringBinding = Binding<String>(
            get: { stringValue },
            set: { newValue in
                stringValue = newValue
                value = newValue.isEmpty ? nil : newValue
            }
        )

        return TextField("", text: stringBinding)
            .modifier(ReusableTextFieldModifier(binding: stringBinding))
            .truncationMode(.tail)
            .onChange(of: value) { newValue in
                stringValue = newValue ?? ""
            }
    }
}
