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
    /// Dismissal: any of the following flips the `isPresented` binding to
    /// `false`, which triggers the custom card-exit animation before the
    /// underlying `.fullScreenCover` drops:
    ///
    /// - Setting the binding to `false` directly from consumer code.
    /// - Reading `@Environment(\.dismiss)` (iOS 15+) inside `content` and
    ///   calling it from a button.
    /// - Tapping the dim backdrop.
    /// - Swiping the card downwards.
    /// - Performing the VoiceOver Escape gesture (two-finger Z).
    /// - Pressing Escape on a hardware keyboard.
    ///
    /// The action sheet does not vend a system "Cancel" button — the consumer
    /// is responsible for providing one (or any other dismissal affordance) in
    /// `content`.
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

// MARK: - View modifiers

@available(iOS 15, *)
private extension BottomActionSheet {

    /// `isPresented:` variant of the action-sheet modifier.
    ///
    /// The `.fullScreenCover` is driven by an internal `coverPresented`
    /// @State that is decoupled from the consumer's binding. When the
    /// consumer's binding flips to `false` (from any source: their own code,
    /// `\.dismiss`, backdrop tap, drag, VoiceOver escape), the Cover
    /// observes it via `.onChange`, plays the card-exit animation, and only
    /// then drops `coverPresented` so the system slide-down is suppressed
    /// against an already-empty cover.
    struct IsPresentedModifier<SheetContent: View>: ViewModifier {
        @Binding var isPresented: Bool
        let onDismiss: (() -> Void)?
        let sheetContent: () -> SheetContent

        @State private var coverPresented: Bool = false

        func body(content: Content) -> some View {
            content
                .fullScreenCover(isPresented: coverBridge, onDismiss: onDismiss) {
                    Cover(
                        content: sheetContent,
                        isPresented: $isPresented,
                        onCardExitComplete: dropCover
                    )
                }
                .onChange(of: isPresented) { newValue in
                    if newValue && !coverPresented { presentCover() }
                }
                .onAppear {
                    if isPresented && !coverPresented { presentCover() }
                }
        }

        /// Binding handed to `.fullScreenCover`. The `get` reports our
        /// internal `coverPresented`; any external set-to-false (e.g.
        /// `\.dismiss` from inside the cover content) is routed back
        /// through the consumer's binding so the Cover's `.onChange`
        /// triggers the custom exit animation.
        private var coverBridge: Binding<Bool> {
            Binding(
                get: { coverPresented },
                set: { newValue in
                    if newValue == false { isPresented = false }
                }
            )
        }

        private func presentCover() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { coverPresented = true }
        }

        private func dropCover() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { coverPresented = false }
        }
    }

    /// `item:` variant of the action-sheet modifier. Mirrors
    /// `IsPresentedModifier` but with `Item?` semantics; see its doc comment
    /// for the dismissal flow.
    struct ItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
        @Binding var item: Item?
        let onDismiss: (() -> Void)?
        let sheetContent: (Item) -> SheetContent

        @State private var coverItem: Item? = nil

        func body(content: Content) -> some View {
            content
                .fullScreenCover(item: coverBridge, onDismiss: onDismiss) { presentedItem in
                    Cover(
                        content: { sheetContent(presentedItem) },
                        isPresented: Binding(
                            get: { item != nil },
                            set: { newValue in
                                if newValue == false { item = nil }
                            }
                        ),
                        onCardExitComplete: dropCover
                    )
                }
                .onChange(of: item?.id) { newId in
                    if newId == nil { return }
                    if coverItem == nil {
                        presentCover()
                    } else {
                        // Item swap inside an already-open cover; mirror the
                        // new value without re-running the entry animation.
                        coverItem = item
                    }
                }
                .onAppear {
                    if let item = item, coverItem == nil { coverItem = item }
                }
        }

        private var coverBridge: Binding<Item?> {
            Binding(
                get: { coverItem },
                set: { newValue in
                    if newValue == nil { item = nil }
                }
            )
        }

        private func presentCover() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { coverItem = item }
        }

        private func dropCover() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { coverItem = nil }
        }
    }

    // MARK: - Cover

    /// Shared cover content: dim backdrop + bottom-anchored card with
    /// spring-driven entry, drag-to-dismiss, and reduce-motion fallback.
    struct Cover<SheetContent: View>: View {
        let content: () -> SheetContent
        @Binding var isPresented: Bool
        let onCardExitComplete: () -> Void

        @State private var isVisible: Bool = false
        @State private var dragTranslation: CGFloat = 0
        @State private var isAnimatingExit: Bool = false
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
            .onChange(of: isPresented) { newValue in
                // The consumer's binding became false — from any path:
                // their own code, `\.dismiss`, backdrop tap, drag-to-dismiss,
                // VoiceOver escape, hardware Escape. Play the exit animation
                // and let the outer modifier drop the cover when it settles.
                if newValue == false { animateExit() }
            }
        }

        private var backdrop: some View {
            // The card below carries .accessibilityAddTraits(.isModal), which
            // restricts VoiceOver to card content only — so any backdrop-level
            // accessibility traits / actions would be unreachable. VoiceOver
            // dismissal goes through .accessibilityAction(.escape) on the card.
            Color.black
                .opacity(isVisible ? BottomActionSheet.defaultBackdropOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
        }

        private var card: some View {
            content()
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

        /// Single user-initiated dismiss path. Flips the consumer's binding to
        /// `false`; `.onChange(of: isPresented)` above sees the change and
        /// drives the exit animation. Funnelling through the same binding
        /// means every dismissal source (consumer code, `\.dismiss`, backdrop
        /// tap, drag, escape gestures) gets the same animation treatment.
        private func dismiss() {
            guard !isAnimatingExit else { return }
            isPresented = false
        }

        /// Animate the card off-screen, then ask the outer modifier to drop
        /// the cover.
        ///
        /// SwiftUI's `withAnimation` commits its driving state changes into a
        /// CATransaction, so the `setCompletionBlock` fires once the animation
        /// actually settles — which avoids the need for a magic-number
        /// `asyncAfter` that has to be kept in sync with the spring response.
        /// This sequencing relies on an undocumented SwiftUI behaviour; see
        /// the BottomActionSheet entry in `TECH_DEBT.md`.
        private func animateExit() {
            guard !isAnimatingExit else { return }
            isAnimatingExit = true
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                onCardExitComplete()
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
