import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)

            Text(HimatchApp.displayName)
                .font(.largeTitle.bold())

            Text("空いている時間を、いっしょに見つけよう。")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
