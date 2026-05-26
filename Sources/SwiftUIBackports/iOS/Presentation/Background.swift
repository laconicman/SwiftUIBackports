import SwiftUI
import SwiftBackports

@available(tvOS, deprecated: 16.4)
@available(macOS, deprecated: 13.3)
@available(watchOS, deprecated: 9.4)
@MainActor
public extension Backport where Wrapped: View {

    /// Sets the presentation background of the enclosing sheet using a shape style.
    ///
    /// The following example uses the `thick` material as the sheet background:
    ///
    ///     struct ContentView: View {
    ///         @State private var showSettings = false
    ///
    ///         var body: some View {
    ///             Button("View Settings") {
    ///                 showSettings = true
    ///             }
    ///             .sheet(isPresented: $showSettings) {
    ///                 SettingsView()
    ///                     .backport.presentationBackground(.thickMaterial)
    ///             }
    ///         }
    ///     }
    ///
    /// The `presentationBackground(_:)` modifier differs from the `background(_:)`
    /// modifier in several key ways. A presentation background:
    ///
    /// - Automatically fills the entire presentation.
    /// - Allows views behind the presentation to show through translucent styles
    ///   on supported platforms.
    ///
    /// On iOS 15 the background is rendered behind the sheet content via SwiftUI's
    /// regular `background` modifier, and the underlying `UIHostingController` view
    /// background is cleared so the supplied style is what the user sees. This
    /// approximates the native behavior closely for the common case where the
    /// modifier is applied to the root of a presented modal.
    ///
    /// - Parameter style: The shape style to use as the presentation background.
    @ViewBuilder
    @available(iOS, introduced: 15, deprecated: 16.4, message: "Presentation background is supported natively on iOS 16.4+")
    func presentationBackground<S: ShapeStyle>(_ style: S) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            wrapped.presentationBackground(style)
        } else {
            wrapped
                .background(style, ignoresSafeAreaEdges: .all)
                .background(BackgroundClearer())
        }
        #else
        wrapped
        #endif
    }

    /// Sets the presentation background of the enclosing sheet to a custom view.
    ///
    /// The following example uses a yellow view as the sheet background:
    ///
    ///     struct ContentView: View {
    ///         @State private var showSettings = false
    ///
    ///         var body: some View {
    ///             Button("View Settings") {
    ///                 showSettings = true
    ///             }
    ///             .sheet(isPresented: $showSettings) {
    ///                 SettingsView()
    ///                     .backport.presentationBackground {
    ///                         Color.yellow
    ///                     }
    ///             }
    ///         }
    ///     }
    ///
    /// A presentation background automatically fills the entire presentation and,
    /// where supported, lets views behind the presentation show through translucent
    /// styles.
    ///
    /// - Parameters:
    ///   - alignment: The alignment that the modifier uses to position the
    ///     implicit `ZStack` that groups the background views. The default is
    ///     `center`.
    ///   - content: The view to use as the background of the presentation.
    @ViewBuilder
    @available(iOS, introduced: 15, deprecated: 16.4, message: "Presentation background is supported natively on iOS 16.4+")
    func presentationBackground<V: View>(
        alignment: Alignment = .center,
        @ViewBuilder content: () -> V
    ) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) {
            wrapped.presentationBackground(alignment: alignment, content: content)
        } else {
            wrapped
                .background(alignment: alignment) {
                    content().ignoresSafeArea()
                }
                .background(BackgroundClearer())
        }
        #else
        wrapped
        #endif
    }
}

#if os(iOS)
/// Clears the background color of the enclosing `UIHostingController`'s view so
/// that a SwiftUI-provided background renders through.
///
/// Only acts when the hosting controller is actually being presented modally,
/// guarding against accidentally clearing the background of the application's
/// root host. Idempotent: re-applies on `updateUIView` and `didMoveToWindow`,
/// so any subsequent system re-paint (e.g. after a trait collection change) is
/// undone.
@available(iOS 15, *)
private struct BackgroundClearer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        BackgroundClearingView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? BackgroundClearingView)?.clearHostBackground()
    }
}

@available(iOS 15, *)
private final class BackgroundClearingView: UIView {
    init() {
        super.init(frame: .zero)
        isHidden = true
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clearHostBackground()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        clearHostBackground()
    }

    func clearHostBackground() {
        // Walk the responder chain to find the first enclosing UIHostingController.
        // The host controller's view carries the system-provided background that
        // we want to replace; SwiftUI lays our own `.background` modifier *behind*
        // the content but *in front* of the host's view, so clearing the host's
        // background is what makes the supplied style visible.
        var controller: UIViewController? = parentController
        while let candidate = controller {
            // `UIHostingController` is generic (`UIHostingController<Content>`) and
            // Swift generics are invariant, so there is no `is` / `as?` form that
            // matches "any specialisation" of it: `is UIHostingController` fails
            // to compile (the Content parameter cannot be inferred), and
            // `as? UIHostingController<Any>` / `as? UIHostingController<AnyView>`
            // only match that exact specialisation. There is also no public
            // non-generic base class or protocol to test against. Name-based
            // identification via the Objective-C class name is the standard
            // workaround used by UIKit-bridge libraries in the SwiftUI ecosystem.
            if NSStringFromClass(type(of: candidate)).contains("UIHostingController") {
                // Only clear when the host is actually being presented as a modal,
                // so we never accidentally make the application's root host
                // transparent.
                if candidate.presentingViewController != nil {
                    candidate.view.backgroundColor = .clear
                    candidate.view.isOpaque = false
                }
                return
            }
            controller = candidate.parent
        }
    }
}
#endif
