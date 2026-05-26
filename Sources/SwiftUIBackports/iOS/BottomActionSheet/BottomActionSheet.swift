import SwiftUI
import SwiftBackports

@available(macOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@MainActor
public extension Backport where Wrapped: View {

    /// Presents a bottom-anchored action-sheet card that always slides up from
    /// the bottom of the screen and sizes to its content, on every iOS device
    /// and size class.
    ///
    /// This is an *extra* — not an API-matching backport. Apple has no
    /// equivalent built-in modifier; the closest replacements are
    /// `.confirmationDialog` (which renders as a popover on iPad regular size
    /// class) and `.sheet` + `.presentationDetents([.height(...)])`
    /// (iOS 16+, similarly popover-on-iPad). When `bottomActionSheet` matters
    /// to you, it's typically because those replacements don't.
    ///
    /// On iOS 16.4+, the underlying `.fullScreenCover` uses the native
    /// `.presentationBackground(.clear)` to drop its system background. On
    /// iOS 15-16.3, it goes through the
    /// ``Backport/presentationBackground(_:)`` fallback in this library.
    ///
    /// Dismissal is exposed through the `\.bottomActionSheetDismiss`
    /// environment value. Inside `content` (or any descendant of it) write:
    ///
    ///     @Environment(\.bottomActionSheetDismiss) private var dismiss
    ///     // ...
    ///     Button("Cancel") { dismiss() }
    ///
    /// The action sheet does not vend a system "Cancel" button — the consumer
    /// is responsible for providing one (or any other dismissal affordance) in
    /// `content`. Tapping the dim backdrop, swiping the card downwards,
    /// performing the VoiceOver Escape gesture (two-finger Z), or pressing
    /// Escape on a hardware keyboard will also dismiss the action sheet.
    ///
    /// - Parameters:
    ///   - isPresented: A binding to a Boolean value that determines whether
    ///     to present the action sheet.
    ///   - onDismiss: The closure to execute when dismissing the action sheet.
    ///   - content: A view builder that defines the action sheet's content.
    @ViewBuilder
    @available(iOS, introduced: 15)
    func bottomActionSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        wrapped.modifier(BottomActionSheet.IsPresentedModifier(
            isPresented: isPresented,
            onDismiss: onDismiss,
            sheetContent: content
        ))
        #else
        wrapped
        #endif
    }

    /// Presents a bottom-anchored action-sheet card using the given item as
    /// the source of truth, mirroring `View.sheet(item:onDismiss:content:)`.
    ///
    /// See ``bottomActionSheet(isPresented:onDismiss:content:)`` for details
    /// on visual presentation, accessibility, and dismissal model.
    ///
    /// - Parameters:
    ///   - item: A binding to an optional source of truth for the action sheet.
    ///   - onDismiss: The closure to execute when dismissing the action sheet.
    ///   - content: A closure returning the content of the action sheet.
    @ViewBuilder
    @available(iOS, introduced: 15)
    func bottomActionSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        wrapped.modifier(BottomActionSheet.ItemModifier(
            item: item,
            onDismiss: onDismiss,
            sheetContent: content
        ))
        #else
        wrapped
        #endif
    }
}

#if os(iOS)

// MARK: - Namespace and tunables

/// Namespace for the bottom-action-sheet Extras module.
public enum BottomActionSheet {
    /// Default dim opacity behind the action-sheet card.
    public static let defaultBackdropOpacity: Double = 0.4
    /// Default horizontal/vertical padding around the action-sheet card.
    public static let defaultOuterPadding: CGFloat = 12
    /// Default present-animation curve.
    public static let defaultPresentAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    /// Default dismiss-animation curve.
    public static let defaultDismissAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.9)
    /// Reduce-motion fallback animation curve.
    public static let reduceMotionAnimation: Animation = .easeInOut(duration: 0.2)
    /// Drag distance (in points) at which a release dismisses the sheet.
    public static let defaultDragDismissThreshold: CGFloat = 100
    /// Minimum drag distance before the gesture begins, so taps still hit
    /// underlying buttons reliably.
    public static let defaultDragMinimumDistance: CGFloat = 20
}

// MARK: - Environment key

/// Environment-injected dismiss action for the enclosing
/// ``Backport/bottomActionSheet(isPresented:onDismiss:content:)`` or
/// ``Backport/bottomActionSheet(item:onDismiss:content:)`` presentation.
///
/// Read this via `@Environment(\.bottomActionSheetDismiss)` inside the
/// `content` closure to dismiss the action sheet:
///
///     @Environment(\.bottomActionSheetDismiss) private var dismiss
///     Button("Cancel") { dismiss() }
///
/// Outside of a bottom action sheet the action is a no-op.
public struct BottomActionSheetDismissAction {
    fileprivate let action: () -> Void
    public func callAsFunction() { action() }
}

private struct BottomActionSheetDismissKey: EnvironmentKey {
    static let defaultValue: BottomActionSheetDismissAction = .init(action: {})
}

public extension EnvironmentValues {
    /// An action that dismisses the enclosing bottom action sheet, or a no-op
    /// when read outside of one. See ``BottomActionSheetDismissAction``.
    var bottomActionSheetDismiss: BottomActionSheetDismissAction {
        get { self[BottomActionSheetDismissKey.self] }
        set { self[BottomActionSheetDismissKey.self] = newValue }
    }
}

// MARK: - View modifiers

@available(iOS 15, *)
private extension BottomActionSheet {

    /// `isPresented:` variant of the action-sheet modifier.
    struct IsPresentedModifier<SheetContent: View>: ViewModifier {
        @Binding var isPresented: Bool
        let onDismiss: (() -> Void)?
        let sheetContent: () -> SheetContent

        func body(content: Content) -> some View {
            // Both the cover's presentation binding *and* the binding passed
            // into Cover need to suppress system animations — otherwise
            // dismissals initiated from inside Cover would slide the cover
            // out via the system transition we explicitly suppressed when
            // presenting it.
            let binding = animationDisabledBinding
            return content
                .fullScreenCover(isPresented: binding, onDismiss: onDismiss) {
                    Cover(content: sheetContent, isPresented: binding)
                }
        }

        /// Wraps the `isPresented` binding so that mutations of *this* binding
        /// are committed inside a transaction with animations disabled. This
        /// suppresses the default `fullScreenCover` slide-up/slide-down system
        /// animation without affecting other transactions in the view tree.
        private var animationDisabledBinding: Binding<Bool> {
            Binding(
                get: { isPresented },
                set: { newValue in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { isPresented = newValue }
                }
            )
        }
    }

    /// `item:` variant of the action-sheet modifier.
    struct ItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
        @Binding var item: Item?
        let onDismiss: (() -> Void)?
        let sheetContent: (Item) -> SheetContent

        func body(content: Content) -> some View {
            content
                .fullScreenCover(item: animationDisabledBinding, onDismiss: onDismiss) { coveredItem in
                    Cover(
                        content: { sheetContent(coveredItem) },
                        isPresented: Binding(
                            get: { item != nil },
                            set: { newValue in
                                guard newValue == false else { return }
                                // Route dismissals through an animation-
                                // disabled transaction so the system slide-
                                // down animation of fullScreenCover is
                                // suppressed; the Cover's own card animation
                                // is what the user sees.
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { item = nil }
                            }
                        )
                    )
                }
        }

        private var animationDisabledBinding: Binding<Item?> {
            Binding(
                get: { item },
                set: { newValue in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { item = newValue }
                }
            )
        }
    }

    // MARK: - Cover

    /// Shared cover content: dim backdrop + bottom-anchored card with
    /// spring-driven entry, drag-to-dismiss, and reduce-motion fallback.
    struct Cover<SheetContent: View>: View {
        let content: () -> SheetContent
        @Binding var isPresented: Bool

        @State private var isVisible: Bool = false
        @State private var dragTranslation: CGFloat = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    backdrop
                    card
                        .offset(y: cardOffset(within: proxy))
                }
            }
            .backport.presentationBackground(.clear)
            .task {
                withAnimation(presentAnimation) { isVisible = true }
            }
        }

        private var backdrop: some View {
            Color.black
                .opacity(isVisible ? BottomActionSheet.defaultBackdropOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("Dismiss"))
                .accessibilityAction { dismiss() }
                .onTapGesture { dismiss() }
        }

        private var card: some View {
            content()
                .environment(\.bottomActionSheetDismiss, .init(action: dismiss))
                .padding(.horizontal, BottomActionSheet.defaultOuterPadding)
                .padding(.bottom, BottomActionSheet.defaultOuterPadding)
                .opacity(reduceMotion ? (isVisible ? 1 : 0) : 1)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { dismiss() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: BottomActionSheet.defaultDragMinimumDistance)
                        .onChanged { value in
                            // Track downward drag only; upward drags don't
                            // make a card-dismiss gesture meaningful here.
                            dragTranslation = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            let translation = value.translation.height
                            let predicted = value.predictedEndTranslation.height
                            let threshold = BottomActionSheet.defaultDragDismissThreshold
                            if translation > threshold || predicted > threshold * 2 {
                                dismiss()
                            } else {
                                // Snap back to the resting position with an
                                // animation so the card doesn't jump.
                                withAnimation(presentAnimation) {
                                    dragTranslation = 0
                                }
                            }
                        }
                )
        }

        /// Computes the card's vertical offset for the current state.
        ///
        /// - Reduce Motion: card stays at its resting position; entry/exit is
        ///   conveyed by an opacity cross-fade instead.
        /// - Default: when hidden, the card sits just below the cover's bottom
        ///   edge (using the GeometryReader-supplied height) so the spring has
        ///   a meaningful starting point that adapts to the device size. When
        ///   visible, the offset tracks any in-progress drag.
        private func cardOffset(within proxy: GeometryProxy) -> CGFloat {
            if reduceMotion {
                return 0
            }
            if isVisible == false {
                return proxy.size.height
            }
            return max(0, dragTranslation)
        }

        private var presentAnimation: Animation {
            reduceMotion ? BottomActionSheet.reduceMotionAnimation : BottomActionSheet.defaultPresentAnimation
        }

        private var dismissAnimation: Animation {
            reduceMotion ? BottomActionSheet.reduceMotionAnimation : BottomActionSheet.defaultDismissAnimation
        }

        private func dismiss() {
            // Animate the card out, then drop the fullScreenCover binding from
            // the CATransaction completion block. SwiftUI's `withAnimation`
            // commits its driving state changes into a CATransaction, so the
            // completion block fires once the animation actually settles —
            // which avoids the need for a magic-number `asyncAfter` that has
            // to be kept in sync with the animation's spring response.
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                isPresented = false
            }
            withAnimation(dismissAnimation) {
                isVisible = false
                // Reset any in-progress drag so the card animates from its
                // current visual position to off-screen rather than jumping
                // back to the drag offset before sliding out.
                dragTranslation = 0
            }
            CATransaction.commit()
        }
    }
}

#endif
