import SwiftUI

// MARK: - Buttons

/// Filled, full-width call to action. One per screen region.
struct HimatchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: HimatchMetrics.primaryButtonHeight)
            .padding(.horizontal, HimatchSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                    .fill(isEnabled ? HimatchColor.accent : Color(uiColor: .systemGray3))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

/// Tinted button for secondary actions next to a primary one.
struct HimatchSecondaryButtonStyle: ButtonStyle {
    var tint: Color = HimatchColor.accent
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? tint : HimatchColor.secondaryText)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: HimatchMetrics.minTapTarget)
            .padding(.horizontal, HimatchSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                    .fill(isEnabled ? HimatchColor.tint(tint) : HimatchColor.unavailable)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == HimatchPrimaryButtonStyle {
    static var himatchPrimary: HimatchPrimaryButtonStyle { HimatchPrimaryButtonStyle() }
}

extension ButtonStyle where Self == HimatchSecondaryButtonStyle {
    static var himatchSecondary: HimatchSecondaryButtonStyle { HimatchSecondaryButtonStyle() }

    static func himatchSecondary(tint: Color, fullWidth: Bool = true) -> HimatchSecondaryButtonStyle {
        HimatchSecondaryButtonStyle(tint: tint, fullWidth: fullWidth)
    }
}

// MARK: - Surfaces

struct HimatchCardModifier: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding(HimatchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HimatchRadius.card, style: .continuous)
                    .fill(tint.map(HimatchColor.tint) ?? HimatchColor.surface)
            )
    }
}

extension View {
    /// Rounded card surface. Pass a tint for status cards (availability, plan, hosting).
    func himatchCard(tint: Color? = nil) -> some View {
        modifier(HimatchCardModifier(tint: tint))
    }
}

// MARK: - Text blocks

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
            Text(title)
                .font(HimatchFont.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(HimatchFont.supporting)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, HimatchSpacing.xxs)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: HimatchSpacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(HimatchColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(HimatchFont.cardTitle)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(HimatchFont.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.himatchSecondary(tint: HimatchColor.accent, fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(HimatchSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: HimatchRadius.card, style: .continuous)
                .fill(HimatchColor.surface)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Tappable banner that points to something needing attention.
struct NoticeBanner: View {
    let icon: String
    let title: String
    var detail: String?
    var tint: Color = HimatchColor.attention
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HimatchSpacing.s) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: HimatchSpacing.xs)
                if let detail {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, HimatchSpacing.m)
            .frame(maxWidth: .infinity, minHeight: HimatchMetrics.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: HimatchRadius.control, style: .continuous)
                    .fill(HimatchColor.tint(tint))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Selectable pill. Selection is shown with a checkmark and the `isSelected` trait, not color alone.
struct SelectableChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    var tint: Color = HimatchColor.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HimatchSpacing.xxs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, HimatchSpacing.s)
            .frame(minWidth: HimatchMetrics.minTapTarget, minHeight: HimatchMetrics.minTapTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? tint : HimatchColor.surface)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : HimatchColor.separator, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Icon + text badge used for status such as visibility.
struct StatusBadge: View {
    let title: String
    let systemImage: String
    var tint: Color = HimatchColor.secondaryText

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, HimatchSpacing.xs)
            .padding(.vertical, HimatchSpacing.xxs)
            .background(Capsule().fill(HimatchColor.tint(tint)))
    }
}

struct IconAvatar: View {
    let systemImage: String
    var size: CGFloat = 32
    var tint: Color = HimatchColor.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(HimatchColor.tint(tint)))
            .accessibilityHidden(true)
    }
}

/// Leading icon with a title and supporting text.
struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = HimatchColor.accent

    var body: some View {
        HStack(alignment: .top, spacing: HimatchSpacing.s) {
            IconAvatar(systemImage: icon, size: 36, tint: tint)
            VStack(alignment: .leading, spacing: HimatchSpacing.xxs) {
                Text(title).font(HimatchFont.cardTitle)
                Text(detail)
                    .font(HimatchFont.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
