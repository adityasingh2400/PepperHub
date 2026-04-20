import SwiftUI
import SwiftData

struct AskPepperView: View {
    @EnvironmentObject private var purchases: PurchasesManager
    @AppStorage("pepper_consent_granted") private var consentGranted = false

    var body: some View {
        NavigationStack {
            chatContent
                .background(Color.appBackground.ignoresSafeArea())
                .navigationTitle("Pepper")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var chatContent: some View {
        if !purchases.isPro {
            PepperProGateView()
        } else if consentGranted {
            PepperChatView()
        } else {
            PepperConsentView(onAccept: { consentGranted = true })
        }
    }
}

// MARK: - Pepper Pro Gate

struct PepperProGateView: View {
    @State private var showPaywall = false
    @State private var appeared = false

    var body: some View {
        ScrollView {

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(Color.appAccentTint)
                        .frame(width: 96, height: 96)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 44))
                        .foregroundColor(Color.appAccent)
                }
                .scaleEffect(appeared ? 1.0 : 0.7)
                .opacity(appeared ? 1.0 : 0)

                VStack(spacing: 10) {
                    Text("Meet Pepper")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                    Text("ChatGPT doesn't know your stack.\nPepper does.")
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextTertiary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    PepperFeatureRow(icon: "person.text.rectangle.fill", title: "Knows your exact protocol", detail: "Your compounds, doses, timing, and frequency — already loaded in.")
                    PepperFeatureRow(icon: "chart.bar.xaxis", title: "Reads your logged data", detail: "Ask about your side effects, food patterns, and dose history.")
                    PepperFeatureRow(icon: "bolt.fill", title: "Takes actions for you", detail: "Log a dose, add a meal, or note a symptom — just tell Pepper.")
                    PepperFeatureRow(icon: "shield.lefthalf.filled", title: "Private by default", detail: "Your data goes to Claude API only when you send a message.")
                }
                .padding(.horizontal, 4)

                Button(action: { showPaywall = true }) {
                    Text("Start 7-Day Free Trial")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appAccent)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 4)

                Text("$4.99/month or $50/year · Cancel anytime")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextMeta)

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
        .onAppear {
            Analytics.capture(.paywallViewed)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}

private struct PepperFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appAccentTint)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color.appAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Color.appTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Consent Gate

struct PepperConsentView: View {
    let onAccept: () -> Void
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                ZStack {
                    Circle()
                        .fill(Color.appAccentTint)
                        .frame(width: 88, height: 88)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.appAccent)
                }
                .scaleEffect(appeared ? 1.0 : 0.7)
                .opacity(appeared ? 1.0 : 0)

                VStack(spacing: 8) {
                    Text("Meet Pepper")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(Color.appTextPrimary)
                    Text("Your AI assistant that knows your data")
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextTertiary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ConsentFeatureRow(icon:"chart.bar.fill", title: "Interprets your logs", detail: "Ask questions about your protocol, food, workouts, and side effects")
                    ConsentFeatureRow(icon:"pencil.and.list.clipboard", title: "Takes actions for you", detail: "Log food, doses, and workouts by just telling Pepper what you did")
                    ConsentFeatureRow(icon:"shield.lefthalf.filled", title: "Data disclosure", detail: "Your health data is sent to Anthropic's Claude API to generate responses. It is not stored by Anthropic beyond your conversation.")
                }
                .padding(.horizontal, 4)

                VStack(spacing: 10) {
                    Text("By continuing, you agree to share your logged health data with the Claude API.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextMeta)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Button(action: onAccept) {
                        Text("Enable Pepper")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.appAccent)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 4)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }
}

private struct ConsentFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appAccentTint)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color.appAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(Color.appTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(12)
    }
}

// MARK: - Chat View

struct PepperChatView: View {
    @EnvironmentObject private var pepperService: PepperService
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext

    @State private var inputText = ""
    @State private var scrollProxy: ScrollViewProxy? = nil
    @FocusState private var inputFocused: Bool

    private let quickActions = [
        "How am I doing today?",
        "Log my lunch",
        "Summarize this week"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Context pill
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(Color.appAccent)
                Text("Pepper knows: 14 days of data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.appAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appAccentTint)
            .cornerRadius(20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if pepperService.messages.isEmpty {
                            PepperEmptyStateView(quickActions: quickActions) { action in
                                sendMessage(action)
                            }
                            .id("empty")
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                        } else {
                            ForEach(pepperService.messages) { message in
                                Group {
                                    if message.isUser {
                                        UserMessageBubble(text: message.text)
                                    } else {
                                        AssistantMessageBubble(message: message) { call in
                                            Task {
                                                await pepperService.confirmToolCall(call, editedInput: nil, modelContext: modelContext, userId: userId)
                                            }
                                        } onCancel: { call in
                                            Task {
                                                await pepperService.cancelToolCall(call, modelContext: modelContext, userId: userId)
                                            }
                                        }
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                            if pepperService.isStreaming && (pepperService.messages.last?.isUser ?? true) {
                                TypingIndicator()
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.78), value: pepperService.messages.count)
                    .animation(.easeInOut(duration: 0.2), value: pepperService.isStreaming)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .onChange(of: pepperService.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: pepperService.isStreaming) { _, streaming in
                    if streaming {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                .onAppear { scrollProxy = proxy }
            }

            // Input area
            VStack(spacing: 0) {
                Divider()
                if pepperService.messages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickActions, id: \.self) { action in
                                Button(action: { sendMessage(action) }) {
                                    Text(action)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color.appAccent)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.appAccentTint)
                                        .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                HStack(spacing: 10) {
                    TextField("Ask Pepper anything...", text: $inputText, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(1...5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.appDivider)
                        .cornerRadius(22)
                        .focused($inputFocused)
                        .disabled(pepperService.pendingToolCall != nil || pepperService.isStreaming)
                        .onSubmit { if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sendMessage(inputText) } }

                    Button(action: { sendMessage(inputText) }) {
                        Image(systemName: pepperService.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(canSend ? Color.appAccent : Color(hex: "d1d5db"))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pepperService.isStreaming)
                            .scaleEffect(canSend ? 1.0 : 0.9)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appCard)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Pepper")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { pepperService.clearConversation() }) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(Color.appAccent)
                }
            }
        }
    }

    private var canSend: Bool {
        !pepperService.isStreaming &&
        pepperService.pendingToolCall == nil &&
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var userId: String {
        authManager.session?.user.id.uuidString ?? ""
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !pepperService.isStreaming, pepperService.pendingToolCall == nil else { return }
        inputText = ""
        Task {
            await pepperService.send(userMessage: trimmed, modelContext: modelContext, userId: userId)
        }
    }
}

// MARK: - Message Bubbles

private struct UserMessageBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appAccent)
                .cornerRadius(18, corners: [.topLeft, .topRight, .bottomLeft])
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: PepperMessage
    let onConfirm: (PepperToolCall) -> Void
    let onCancel: (PepperToolCall) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Pepper avatar
            ZStack {
                Circle()
                    .fill(Color.appAccentTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appAccent)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundColor(Color.appTextPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.appCard)
                        .cornerRadius(18, corners: [.topLeft, .topRight, .bottomRight])
                        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                }

                if let toolCall = message.toolCall {
                    ToolConfirmationCard(
                        toolCall: toolCall,
                        status: message.toolStatus,
                        onConfirm: onConfirm,
                        onCancel: onCancel
                    )
                }
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Tool Confirmation Card

private struct ToolConfirmationCard: View {
    let toolCall: PepperToolCall
    let status: PepperMessage.ToolStatus
    let onConfirm: (PepperToolCall) -> Void
    let onCancel: (PepperToolCall) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: toolIcon)
                    .font(.system(size: 13))
                    .foregroundColor(statusColor)
                Text(toolCall.displaySummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.appTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            switch status {
            case .pending:
                HStack(spacing: 8) {
                    Button(action: { onCancel(toolCall) }) {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.appTextTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color(hex: "f3f4f6"))
                            .cornerRadius(10)
                    }
                    Button(action: { onConfirm(toolCall) }) {
                        Text("Confirm")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.appAccent)
                            .cornerRadius(10)
                    }
                }

            case .confirmed(let result):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "16a34a"))
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "16a34a"))
                        .lineLimit(2)
                }

            case .cancelled:
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color.appTextTertiary)
                    Text("Cancelled")
                        .font(.system(size: 12))
                        .foregroundColor(Color.appTextTertiary)
                }

            case .failed(let error):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "dc2626"))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "dc2626"))
                        .lineLimit(2)
                }

            case .none:
                EmptyView()
            }
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusBorderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }

    private var toolIcon: String {
        switch toolCall.toolName {
        case "log_food_entry": return "fork.knife"
        case "log_dose": return "syringe"
        case "search_food": return "magnifyingglass"
        case "log_exercise_set": return "dumbbell.fill"
        case "log_side_effect": return "heart.text.square.fill"
        default: return "square.and.pencil"
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return Color.appAccent
        case .confirmed: return Color(hex: "16a34a")
        case .cancelled, .none: return Color.appTextTertiary
        case .failed: return Color(hex: "dc2626")
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .pending: return Color.appAccentTint
        case .confirmed: return Color(hex: "dcfce7")
        case .cancelled, .none: return Color(hex: "f3f4f6")
        case .failed: return Color(hex: "fee2e2")
        }
    }
}

// MARK: - Empty State

private struct PepperEmptyStateView: View {
    let quickActions: [String]
    let onAction: (String) -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 60)
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.appAccentTint)
                        .frame(width: 72, height: 72)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color.appAccent)
                }
                Text("Ask Pepper anything")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.appTextPrimary)
                Text("Pepper knows your protocol, food logs,\nworkouts, and side effects.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                ForEach(quickActions, id: \.self) { action in
                    Button(action: { onAction(action) }) {
                        HStack {
                            Text(action)
                                .font(.system(size: 15))
                                .foregroundColor(Color.appTextSecondary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundColor(Color.appTextMeta)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color.appCard)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
                    }
                }
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appAccentTint)
                    .frame(width: 28, height: 28)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.appAccent)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.0 : 0.4)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.appCard)
            .cornerRadius(18, corners: [.topLeft, .topRight, .bottomRight])
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            Spacer(minLength: 40)
        }
        .onAppear { animating = true }
    }
}

// MARK: - Corner Radius Helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
