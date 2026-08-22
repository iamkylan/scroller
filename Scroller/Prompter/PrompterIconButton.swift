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
                .frame(width: 40, height: 40)
                .background(
                    isOn ? AnyShapeStyle(Color.scrollerAccent) : AnyShapeStyle(.ultraThinMaterial),
                    in: .circle
                )
        }
    }
}
