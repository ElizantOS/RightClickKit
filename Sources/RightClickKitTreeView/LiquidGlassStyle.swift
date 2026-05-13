import SwiftUI

struct RCKGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        #if swift(>=6.3)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

extension View {
    func rckGlassSurface<S: Shape>(
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        modifier(RCKGlassSurfaceModifier(shape: shape, interactive: interactive))
    }

    func rckGlassButton(prominent: Bool = false) -> some View {
        modifier(RCKGlassButtonModifier(prominent: prominent))
    }
}

private struct RCKGlassSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if swift(>=6.3)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(interactive ? Glass.regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        #else
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        #endif
    }
}

private struct RCKGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if swift(>=6.3)
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
        #else
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
        #endif
    }
}
