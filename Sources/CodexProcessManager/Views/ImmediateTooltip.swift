import SwiftUI

extension View {
    func immediateTooltip(_ text: String) -> some View {
        modifier(ImmediateTooltipModifier(text: text))
    }
}

private struct ImmediateTooltipModifier: ViewModifier {
    let text: String

    @State private var isHovering = false
    @State private var isShowing = false
    @State private var pendingTask: Task<Void, Never>?

    private var tooltipWidth: CGFloat {
        min(260, max(120, CGFloat(text.count * 12)))
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isShowing {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: tooltipWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                        .offset(y: 34)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(20)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                isHovering = hovering
                pendingTask?.cancel()

                if hovering {
                    pendingTask = Task {
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            if isHovering {
                                withAnimation(.easeOut(duration: 0.08)) {
                                    isShowing = true
                                }
                            }
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.06)) {
                        isShowing = false
                    }
                }
            }
    }
}
