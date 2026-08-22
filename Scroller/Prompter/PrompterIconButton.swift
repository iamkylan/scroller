import SwiftUI

struct PrompterIconButton: View {
    let symbol: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? .black : .white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isOn ? .regular.tint(.scrollerAccent).interactive() : .regular.interactive(),
            in: .circle
        )
    }
}
