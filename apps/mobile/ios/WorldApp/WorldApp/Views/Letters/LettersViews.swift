import SwiftUI

// MARK: - Feed strip (replaces Moments)

struct LettersStripView: View {
    @Environment(AppState.self) private var appState
    @State private var letters = LettersService.shared
    @State private var tick = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.open.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.oceanWash.opacity(0.95))
                Text("Letters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text("\(letters.remainingToday)/5 left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(letters.remainingToday == 0 ? Theme.inkMuted : Theme.accentBright)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    writeLetterCard
                    inboxCard
                    if !letters.inFlightThreads.isEmpty {
                        ForEach(letters.inFlightThreads.prefix(6)) { thread in
                            flightChip(thread)
                        }
                    }
                    if !letters.penFriendThreads.isEmpty {
                        ForEach(letters.penFriendThreads.prefix(4)) { thread in
                            penFriendChip(thread)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
        .background {
            LinearGradient(
                colors: [Theme.oceanWash.opacity(0.10), Theme.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .lettersDidChange)) { _ in
            letters.expireStaleThreads()
            tick = Date()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            letters.rolloverQuotaIfNeeded(now: date)
            letters.expireStaleThreads(now: date)
            tick = date
        }
        .onAppear {
            letters.rolloverQuotaIfNeeded()
            letters.expireStaleThreads()
        }
    }

    private var writeLetterCard: some View {
        Button {
            appState.presentLetterCompose()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.93, blue: 0.88),
                                    Color(red: 0.90, green: 0.86, blue: 0.78),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    VStack(spacing: 6) {
                        Image(systemName: "pencil.and.scribble")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Text(letters.remainingToday > 0 ? "Write" : "Full")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                Text("New letter")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.plain)
        .opacity(letters.remainingToday > 0 ? 1 : 0.72)
    }

    private var inboxCard: some View {
        Button {
            appState.navigate(to: .letters)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: 92, height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    VStack(spacing: 6) {
                        Image(systemName: "tray.full.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.oceanWash.opacity(0.95))
                        Text("Inbox")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(width: 92, height: 92)

                    if letters.unreadIncomingCount > 0 {
                        Text("\(min(letters.unreadIncomingCount, 9))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.danger, in: Capsule())
                            .offset(x: -6, y: 6)
                    }
                }

                Text(letters.unreadIncomingCount > 0 ? "\(letters.unreadIncomingCount) waiting" : "Open box")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.plain)
    }

    private func flightChip(_ thread: LetterThread) -> some View {
        Button {
            appState.navigate(to: .letterThread(thread.id))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surface)
                        .frame(width: 92, height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    VStack(spacing: 4) {
                        Text(CountryFlag.emoji(for: thread.destinationCountryCode))
                            .font(.largeTitle)
                        Text(thread.status == .expired ? "Expired" : "In flight")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(.uppercase)
                    }
                }

                Text(thread.destinationCountryName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.plain)
        .opacity(thread.status == .expired ? 0.55 : 1)
    }

    private func penFriendChip(_ thread: LetterThread) -> some View {
        Button {
            appState.navigate(to: .letterThread(thread.id))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.oceanWash.opacity(0.35), Theme.surface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    VStack(spacing: 4) {
                        Text(CountryFlag.emoji(for: thread.destinationCountryCode))
                            .font(.largeTitle)
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.like.opacity(0.85))
                    }
                }

                Text("Pen friend")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .frame(width: 92)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compose

struct LetterComposeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var letters = LettersService.shared
    @State private var bodyText = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private let maxChars = 500

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        letterPaper
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Theme.danger)
                        }
                        Text("One letter, one stranger, one country. They have 24 hours to answer — then you become pen friends.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(Theme.pagePadding)
                }

                sealBar
            }
            .screenBackground()
            .navigationTitle("Write a letter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                letters.rolloverQuotaIfNeeded()
                focused = true
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.americas.fill")
                .font(.title2)
                .foregroundStyle(Theme.oceanWash.opacity(0.95))
            VStack(alignment: .leading, spacing: 3) {
                Text("To a random stranger")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(letters.remainingToday) of 5 letters left today · resets at local midnight")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var letterPaper: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextEditor(text: $bodyText)
                .focused($focused)
                .frame(minHeight: 180)
                .padding(14)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(red: 0.99, green: 0.97, blue: 0.93))
                )
                .overlay(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("Dear stranger…")
                            .font(.body)
                            .foregroundStyle(Theme.inkMuted.opacity(0.7))
                            .padding(20)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
                .shadow(color: Theme.ink.opacity(0.04), radius: 8, y: 3)

            HStack {
                Spacer()
                Text("\(bodyText.count)/\(maxChars)")
                    .font(.caption2)
                    .foregroundStyle(bodyText.count > maxChars ? Theme.danger : Theme.inkMuted)
            }
        }
    }

    private var sealBar: some View {
        VStack(spacing: 0) {
            Theme.divider.frame(height: 0.5)
            Button {
                sealAndSend()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge.fill")
                    Text(letters.remainingToday > 0 ? "Seal & send (\(letters.sentToday + 1)/5)" : "No letters left today")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(letters.remainingToday > 0 && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.accent : Theme.buttonMuted)
                .foregroundStyle(letters.remainingToday > 0 && !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white : Theme.inkMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(letters.remainingToday == 0)
            .padding(Theme.pagePadding)
            .background(Theme.surface)
        }
    }

    private func sealAndSend() {
        errorMessage = nil
        do {
            let event = try letters.sendNewLetter(
                body: bodyText,
                myCountryCode: appState.currentProfile?.countryCode,
                myCountryName: appState.currentProfile?.countryCode
            )
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                appState.presentLetterFlight(event)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Flight animation (seal → globe → country)

struct LetterFlightView: View {
    @Environment(AppState.self) private var appState
    let event: LetterFlightEvent

    @State private var phase: Phase = .folding
    @State private var envelopeScale: CGFloat = 1
    @State private var envelopeOpacity: Double = 1
    @State private var globePulse: CGFloat = 0.92
    @State private var letterOffset: CGSize = .zero
    @State private var showCountry = false
    @State private var trailOpacity: Double = 0

    private enum Phase {
        case folding, launching, landing, done
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.22),
                    Color(red: 0.12, green: 0.18, blue: 0.32),
                    Color(red: 0.06, green: 0.09, blue: 0.16),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft stars
            ForEach(0..<18, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(Double((i % 5) + 2) / 20))
                    .frame(width: CGFloat((i % 3) + 1))
                    .offset(x: CGFloat((i * 47) % 300) - 150, y: CGFloat((i * 73) % 500) - 250)
            }

            VStack(spacing: 28) {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .animation(.easeInOut, value: phase)

                ZStack {
                    // Globe
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.72, blue: 0.95),
                                    Color(red: 0.15, green: 0.35, blue: 0.55),
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 90
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(globePulse)
                        .overlay {
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(Color.white.opacity(0.88))
                                .scaleEffect(globePulse)
                        }
                        .shadow(color: Color.cyan.opacity(0.35), radius: 24)

                    // Flight trail
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 4, height: 48)
                        .offset(letterOffset)
                        .opacity(trailOpacity)
                        .blur(radius: 1)

                    // Envelope
                    envelopeCard
                        .scaleEffect(envelopeScale)
                        .opacity(envelopeOpacity)
                        .offset(letterOffset)
                }
                .frame(height: 280)

                if showCountry {
                    VStack(spacing: 8) {
                        Text(CountryFlag.emoji(for: event.destinationCountryCode))
                            .font(.system(size: 48))
                        Text("Landed in \(event.destinationCountryName)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("They have 24 hours to answer.\nYou only know their country — not who they are.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                if phase == .done {
                    Button {
                        LettersService.shared.completeFlight(threadID: event.threadID)
                        appState.dismissLetterFlight()
                        appState.navigate(to: .letterThread(event.threadID))
                    } label: {
                        Text("Watch for a reply")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .foregroundStyle(Theme.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                }
            }
            .padding(.top, 48)
        }
        .onAppear { runSequence() }
        .interactiveDismissDisabled(phase != .done)
    }

    private var headerTitle: String {
        switch phase {
        case .folding: "Sealing your letter…"
        case .launching: "Letter \(event.slotUsed)/\(event.dailyLimit) · launching"
        case .landing, .done: "Across the world"
        }
    }

    private var envelopeCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.97, green: 0.93, blue: 0.86))
                .frame(width: 140, height: 90)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

            // Fold triangle
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 140, y: 0))
                path.addLine(to: CGPoint(x: 70, y: 42))
                path.closeSubpath()
            }
            .fill(Color(red: 0.92, green: 0.86, blue: 0.76))
            .frame(width: 140, height: 90)

            VStack(spacing: 4) {
                Image(systemName: "seal.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent.opacity(0.7))
                Text("Matterya")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.accent)
            }
            .offset(y: 12)
        }
    }

    private func runSequence() {
        // Fold / seal
        withAnimation(.easeInOut(duration: 0.55)) {
            envelopeScale = 0.92
            phase = .folding
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            // Launch
            withAnimation(.easeIn(duration: 0.85)) {
                phase = .launching
                trailOpacity = 1
                letterOffset = CGSize(width: 0, height: -40)
                envelopeScale = 0.55
                globePulse = 1.08
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.easeIn(duration: 0.55)) {
                letterOffset = CGSize(width: 0, height: -8)
                envelopeOpacity = 0
                envelopeScale = 0.2
                trailOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                phase = .landing
                globePulse = 1.0
                showCountry = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeOut(duration: 0.3)) {
                phase = .done
            }
            LettersService.shared.completeFlight(threadID: event.threadID)
        }
    }
}

// MARK: - Inbox / library

struct LettersHomeView: View {
    @Environment(AppState.self) private var appState
    @State private var letters = LettersService.shared
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Letters")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 4)

            quotaBanner
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 4)

            Picker("Section", selection: $segment) {
                Text("Inbox").tag(0)
                Text("Sent").tag(1)
                Text("Pen friends").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)

            List {
                switch segment {
                case 0:
                    if letters.inboxThreads.isEmpty {
                        emptyRow("No letters waiting", "When a stranger writes you — or you reply — it shows here.")
                    } else {
                        ForEach(letters.inboxThreads) { thread in
                            threadRow(thread, badge: "Reply")
                        }
                    }
                case 1:
                    if letters.inFlightThreads.isEmpty {
                        emptyRow("No letters in flight", "Write up to 5 a day. Each lands in a random country.")
                    } else {
                        ForEach(letters.inFlightThreads) { thread in
                            threadRow(thread, badge: thread.status == .expired ? "Expired" : "Waiting")
                        }
                    }
                default:
                    if letters.penFriendThreads.isEmpty {
                        emptyRow("No pen friends yet", "A reply turns a letter into a living chain.")
                    } else {
                        ForEach(letters.penFriendThreads) { thread in
                            threadRow(thread, badge: "Pen friend")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button {
                appState.presentLetterCompose()
            } label: {
                Label("Write a letter", systemImage: "pencil.line")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 12)
            .background(Theme.canvas.opacity(0.95))
        }
        .onReceive(NotificationCenter.default.publisher(for: .lettersDidChange)) { _ in
            letters.expireStaleThreads()
        }
        .onAppear {
            letters.rolloverQuotaIfNeeded()
            letters.expireStaleThreads()
        }
    }

    private var quotaBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(Theme.accentBright)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(letters.remainingToday) letters left today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Resets at your local midnight · \(letters.sentToday)/5 used")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func emptyRow(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func threadRow(_ thread: LetterThread, badge: String) -> some View {
        Button {
            appState.navigate(to: .letterThread(thread.id))
        } label: {
            HStack(spacing: 12) {
                Text(CountryFlag.emoji(for: thread.destinationCountryCode))
                    .font(.largeTitle)
                    .frame(width: 48, height: 48)
                    .background(Theme.canvasMuted, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(thread.destinationCountryName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                    Text(thread.latestMessage?.body ?? "")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(2)
                    if let remaining = thread.replySecondsRemaining, remaining > 0, thread.awaitingTheirReply {
                        Text(Self.formatCountdown(remaining) + " left to answer")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
    }

    static func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Thread

struct LetterThreadView: View {
    @Environment(AppState.self) private var appState
    let threadID: String

    @State private var letters = LettersService.shared
    @State private var replyText = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var thread: LetterThread? { letters.thread(id: threadID) }

    var body: some View {
        Group {
            if let thread {
                content(thread)
            } else {
                ContentUnavailableView("Letter not found", systemImage: "envelope.badge.shield.half.filled")
            }
        }
        .screenBackground()
        .navigationTitle(thread.map { "\(CountryFlag.emoji(for: $0.destinationCountryCode)) \($0.destinationCountryName)" } ?? "Letter")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .lettersDidChange)) { _ in }
    }

    @ViewBuilder
    private func content(_ thread: LetterThread) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identityCard(thread)

                    ForEach(thread.messages) { message in
                        messageBubble(message)
                    }

                    if thread.status == .expired {
                        Text("This letter expired after 24 hours without a reply. The stranger stays a mystery.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if thread.isPenFriend {
                        penFriendRequests(thread)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.pagePadding)
            }

            if thread.status != .expired {
                replyComposer(thread)
            }
        }
    }

    private func identityCard(_ thread: LetterThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(CountryFlag.emoji(for: thread.destinationCountryCode))
                    .font(.system(size: 36))
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.destinationCountryName)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(thread.isPenFriend ? "Pen friend · country only" : "Stranger · country only")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
            Text("You never see their name or face unless you both request profile and it becomes mutual.")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func messageBubble(_ message: LetterMessage) -> some View {
        HStack {
            if message.authorIsMe { Spacer(minLength: 40) }
            VStack(alignment: message.authorIsMe ? .trailing : .leading, spacing: 6) {
                Text(message.authorIsMe ? "You" : "\(CountryFlag.emoji(for: message.fromCountryCode)) \(message.fromCountryName)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .background(
                        message.authorIsMe
                            ? Theme.accent.opacity(0.12)
                            : Color(red: 0.99, green: 0.97, blue: 0.93),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
                    )
            }
            if !message.authorIsMe { Spacer(minLength: 40) }
        }
    }

    private func penFriendRequests(_ thread: LetterThread) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Requests")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("Only mutual requests unlock the real thing.")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)

            ForEach(PenFriendRequestKind.allCases) { kind in
                let state = thread.requestState(for: kind)
                HStack(spacing: 12) {
                    Image(systemName: kind.systemImage)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(state.isMutual ? "Mutual — unlocked" : kind.subtitle)
                            .font(.caption)
                            .foregroundStyle(state.isMutual ? Theme.success : Theme.inkMuted)
                    }
                    Spacer()
                    if state.isMutual {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                    } else if state.iRequested {
                        Text("Sent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    } else {
                        Button("Request") {
                            letters.request(kind, threadID: thread.id)
                            if kind == .chat || kind == .follow || kind == .profile {
                                let stateAfter = letters.thread(id: thread.id)?.requestState(for: kind)
                                if stateAfter?.isMutual == true {
                                    appState.showToast("Mutual \(kind.title.lowercased()) — unlocked!", style: .success)
                                } else {
                                    appState.showToast("Request sent — unlocks only if mutual", style: .info)
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
            }
        }
        .padding(.top, 8)
    }

    private func replyComposer(_ thread: LetterThread) -> some View {
        VStack(spacing: 0) {
            Theme.divider.frame(height: 0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField(thread.awaitingMyReply ? "Write your reply…" : "Continue the chain…", text: $replyText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(10)
                    .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    sendReply(thread)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 10)
            .background(Theme.surface)
        }
    }

    private func sendReply(_ thread: LetterThread) {
        errorMessage = nil
        do {
            _ = try letters.reply(
                to: thread.id,
                body: replyText,
                myCountryCode: appState.currentProfile?.countryCode,
                myCountryName: appState.currentProfile?.countryCode
            )
            replyText = ""
            focused = false
            appState.showToast(thread.isPenFriend || thread.messages.count >= 1 ? "Letter sent" : "You're pen friends now", style: .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
