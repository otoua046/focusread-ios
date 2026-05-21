import SwiftUI

enum FocusReadUISettingsKey {
    static let liquidGlassEnabled = "liquidGlassEnabled"
}

enum FocusReadControlShapeKind {
    case circle
    case capsule
    case rounded(CGFloat)

    var shape: AnyShape {
        switch self {
        case .circle:
            return AnyShape(Circle())
        case .capsule:
            return AnyShape(Capsule())
        case .rounded(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

private enum FocusReadControlRole {
    case primary
    case secondary
    case icon
    case iconProminent
    case selectableCard(isSelected: Bool)
    case selectableChip(isSelected: Bool)

    var pressedScale: CGFloat {
        switch self {
        case .selectableCard:
            return 0.985
        default:
            return 0.97
        }
    }

    var pressedOpacity: Double {
        switch self {
        case .iconProminent:
            return 0.88
        default:
            return 0.82
        }
    }

    var disabledOpacity: Double {
        switch self {
        case .selectableCard, .selectableChip:
            return 0.7
        default:
            return 0.45
        }
    }

    func foregroundColor(theme: FocusReadResolvedTheme) -> Color {
        switch self {
        case .primary, .iconProminent:
            return Color(uiColor: theme.palette.primaryButtonForeground)
        case .secondary, .icon:
            return theme.primaryText
        case .selectableCard(let isSelected), .selectableChip(let isSelected):
            return isSelected ? Color(uiColor: theme.palette.primaryButtonForeground) : theme.primaryText
        }
    }

    func fallbackBackground(theme: FocusReadResolvedTheme) -> Color {
        switch self {
        case .primary, .iconProminent:
            return Color(uiColor: theme.palette.primaryButtonBackground)
        case .secondary, .icon:
            return theme.controlBackground
        case .selectableCard(let isSelected), .selectableChip(let isSelected):
            return isSelected ? Color(uiColor: theme.palette.primaryButtonBackground) : theme.controlBackground
        }
    }

    func fallbackStroke(theme: FocusReadResolvedTheme) -> Color? {
        switch self {
        case .primary, .iconProminent:
            return nil
        case .secondary, .icon:
            return theme.border.opacity(0.72)
        case .selectableCard(let isSelected), .selectableChip(let isSelected):
            return isSelected ? theme.accent.opacity(0.9) : theme.border.opacity(0.68)
        }
    }

    @available(iOS 26.0, *)
    func glass(theme: FocusReadResolvedTheme, reduceMotion: Bool) -> Glass {
        let baseGlass: Glass
        switch self {
        case .primary:
            baseGlass = .regular.tint(theme.accent)
        case .secondary:
            baseGlass = .regular
        case .icon:
            baseGlass = .clear
        case .iconProminent:
            baseGlass = .regular.tint(theme.accent)
        case .selectableCard(let isSelected), .selectableChip(let isSelected):
            baseGlass = isSelected ? .regular.tint(theme.accent) : .clear
        }
        return reduceMotion ? baseGlass : baseGlass.interactive()
    }
}

private struct FocusReadLiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var focusReadLiquidGlassEnabled: Bool {
        get { self[FocusReadLiquidGlassEnabledKey.self] }
        set { self[FocusReadLiquidGlassEnabledKey.self] = newValue }
    }
}

private struct FocusReadControlSurfaceModifier: ViewModifier {
    @Environment(\.focusReadTheme) private var theme
    @Environment(\.focusReadLiquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let role: FocusReadControlRole
    let shape: FocusReadControlShapeKind
    let isPressed: Bool
    let isDisabled: Bool

    func body(content: Content) -> some View {
        let surfaceShape = shape.shape

        content
            .foregroundStyle(role.foregroundColor(theme: theme))
            .background {
                if usesLiquidGlass {
                    if #available(iOS 26.0, *) {
                        surfaceShape
                            .fill(.clear)
                            .glassEffect(role.glass(theme: theme, reduceMotion: reduceMotion), in: surfaceShape)
                    } else {
                        fallbackSurface(shape: surfaceShape)
                    }
                } else {
                    fallbackSurface(shape: surfaceShape)
                }
            }
            .overlay {
                if !usesLiquidGlass, let strokeColor = role.fallbackStroke(theme: theme) {
                    surfaceShape
                        .stroke(strokeColor, lineWidth: 1)
                }
            }
            .contentShape(surfaceShape)
            .opacity(isDisabled ? role.disabledOpacity : (isPressed ? role.pressedOpacity : 1))
            .scaleEffect(isPressed ? role.pressedScale : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.14), value: isPressed)
    }

    private var usesLiquidGlass: Bool {
        liquidGlassEnabled && !reduceTransparency
    }

    @ViewBuilder
    private func fallbackSurface(shape: AnyShape) -> some View {
        shape
            .fill(role.fallbackBackground(theme: theme))
    }
}

private struct FocusReadStyledControl<Content: View>: View {
    let content: Content
    let role: FocusReadControlRole
    let shape: FocusReadControlShapeKind
    let isPressed: Bool
    let isDisabled: Bool

    var body: some View {
        content
            .modifier(FocusReadControlSurfaceModifier(
                role: role,
                shape: shape,
                isPressed: isPressed,
                isDisabled: isDisabled
            ))
    }
}

struct FocusReadProminentActionButtonStyle: ButtonStyle {
    let shape: FocusReadControlShapeKind
    let fullWidth: Bool
    let minHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let font: Font

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        FocusReadStyledControl(
            content: configuration.label
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: minHeight),
            role: .primary,
            shape: shape,
            isPressed: configuration.isPressed,
            isDisabled: !isEnabled
        )
    }
}

struct FocusReadSecondaryActionButtonStyle: ButtonStyle {
    let shape: FocusReadControlShapeKind
    let fullWidth: Bool
    let minHeight: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let font: Font

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        FocusReadStyledControl(
            content: configuration.label
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(minHeight: minHeight),
            role: .secondary,
            shape: shape,
            isPressed: configuration.isPressed,
            isDisabled: !isEnabled
        )
    }
}

enum FocusReadIconButtonTone {
    case regular
    case prominent
}

enum FocusReadAccessoryToolbarTone {
    case scope
    case action
}

struct FocusReadIconButtonStyle: ButtonStyle {
    let tone: FocusReadIconButtonTone
    let visualSize: CGFloat
    let tapTargetSize: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        FocusReadStyledControl(
            content: configuration.label
                .frame(width: visualSize, height: visualSize),
            role: tone == .prominent ? .iconProminent : .icon,
            shape: .circle,
            isPressed: configuration.isPressed,
            isDisabled: !isEnabled
        )
        .frame(width: tapTargetSize, height: tapTargetSize)
    }
}

private struct FocusReadAccessoryToolbarGroupModifier: ViewModifier {
    @Environment(\.focusReadTheme) private var theme
    @Environment(\.focusReadLiquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let tone: FocusReadAccessoryToolbarTone

    func body(content: Content) -> some View {
        content
            .padding(4)
            .background {
                if usesLiquidGlass, #available(iOS 26.0, *) {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(glass, in: Capsule())
                } else {
                    Capsule()
                        .fill(theme.controlBackground)
                }
            }
            .overlay {
                if !usesLiquidGlass {
                    Capsule()
                        .stroke(theme.border.opacity(0.72), lineWidth: 1)
                }
            }
    }

    private var usesLiquidGlass: Bool {
        liquidGlassEnabled && !reduceTransparency
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        let baseGlass: Glass
        switch tone {
        case .scope:
            baseGlass = .clear
        case .action:
            baseGlass = .regular
        }
        return reduceMotion ? baseGlass : baseGlass.interactive()
    }
}

extension ButtonStyle where Self == FocusReadProminentActionButtonStyle {
    static func focusReadProminentAction(
        shape: FocusReadControlShapeKind = .rounded(18),
        fullWidth: Bool = true,
        minHeight: CGFloat = 50,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 15,
        font: Font = .headline.weight(.semibold)
    ) -> FocusReadProminentActionButtonStyle {
        FocusReadProminentActionButtonStyle(
            shape: shape,
            fullWidth: fullWidth,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            font: font
        )
    }
}

extension ButtonStyle where Self == FocusReadSecondaryActionButtonStyle {
    static func focusReadSecondaryAction(
        shape: FocusReadControlShapeKind = .rounded(18),
        fullWidth: Bool = true,
        minHeight: CGFloat = 50,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 12,
        font: Font = .headline.weight(.semibold)
    ) -> FocusReadSecondaryActionButtonStyle {
        FocusReadSecondaryActionButtonStyle(
            shape: shape,
            fullWidth: fullWidth,
            minHeight: minHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            font: font
        )
    }
}

extension ButtonStyle where Self == FocusReadIconButtonStyle {
    static func focusReadIconControl(
        tone: FocusReadIconButtonTone = .regular,
        visualSize: CGFloat = 44,
        tapTargetSize: CGFloat = 56
    ) -> FocusReadIconButtonStyle {
        FocusReadIconButtonStyle(
            tone: tone,
            visualSize: visualSize,
            tapTargetSize: tapTargetSize
        )
    }
}

extension View {
    func focusReadLiquidGlassEnabled(_ enabled: Bool) -> some View {
        environment(\.focusReadLiquidGlassEnabled, enabled)
    }

    func focusReadSelectableCard(
        isSelected: Bool,
        shape: FocusReadControlShapeKind = .rounded(22),
        isPressed: Bool = false
    ) -> some View {
        modifier(FocusReadControlSurfaceModifier(
            role: .selectableCard(isSelected: isSelected),
            shape: shape,
            isPressed: isPressed,
            isDisabled: false
        ))
    }

    func focusReadSelectableChip(
        isSelected: Bool,
        shape: FocusReadControlShapeKind = .capsule,
        isPressed: Bool = false
    ) -> some View {
        modifier(FocusReadControlSurfaceModifier(
            role: .selectableChip(isSelected: isSelected),
            shape: shape,
            isPressed: isPressed,
            isDisabled: false
        ))
    }

    func focusReadIconControlSurface(
        tone: FocusReadIconButtonTone = .regular,
        shape: FocusReadControlShapeKind = .circle
    ) -> some View {
        modifier(FocusReadControlSurfaceModifier(
            role: tone == .prominent ? .iconProminent : .icon,
            shape: shape,
            isPressed: false,
            isDisabled: false
        ))
    }

    func focusReadAccessoryToolbarGroup(
        tone: FocusReadAccessoryToolbarTone = .action
    ) -> some View {
        modifier(FocusReadAccessoryToolbarGroupModifier(tone: tone))
    }
}
