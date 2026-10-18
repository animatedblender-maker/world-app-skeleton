import SwiftUI

/// Branded Matterya splash — system launch screen + SwiftUI shell handoff.
struct MatteryaSplashView: View {
    var showsProgress: Bool = true
    var message: String? = nil

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                Text("Matterya")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .tracking(0.4)

                if showsProgress {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(.top, 8)
                }

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Matterya")
    }
}

#Preview {
    MatteryaSplashView(message: "Loading…")
}
