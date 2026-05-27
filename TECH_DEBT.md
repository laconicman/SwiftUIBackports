# Tech debt

Open architectural questions and known limitations. New entries go at the top of the relevant section; resolved entries get a short "Resolved in #PR" line and stay for one release before being removed.

## Presentation extras

### `Backport.presentationBackground`: `UIViewRepresentable` + responder-chain vs. `UIViewControllerRepresentable` + `presentationController.presentedViewController`

**Current state.** The iOS 15–16.3 fallback in `Sources/SwiftUIBackports/iOS/Presentation/Background.swift` is implemented as a `UIViewRepresentable` (`BackgroundClearer`) wrapping a `UIView` (`BackgroundClearingView`). The view walks the responder chain via `parentController` to find the enclosing `UIHostingController` (matched by Objective-C class name through `NSStringFromClass`) and clears its `view.backgroundColor`. Re-applies on `didMoveToWindow` and `traitCollectionDidChange`.

This diverges from the rest of `iOS/Presentation/` (`Detents.swift`, `DragIndicator.swift`, `CornerRadius.swift`, `BackgroundInteraction.swift`, `InteractiveDetent.swift`, `InteractiveDismiss.swift`, `ContentInteraction.swift`) which all use the `UIViewControllerRepresentable` + nested `Controller: UIViewController` pattern and reach the active sheet via `parent?.sheetPresentationController`.

**Why the divergence exists today.** The peer pattern reaches the *sheet presentation controller* — useful for setting `detents`, `cornerRadius`, etc. — but not the *hosting controller's `view.backgroundColor`*. Devin Review's analysis on PR #1 flagged the divergence and judged it "intentional and appropriate" on that basis. The current implementation is correct for its narrow goal.

**Alternative: switch to `UIViewControllerRepresentable`.** From inside a child `UIViewController` inserted by SwiftUI, the public chain `self.presentationController?.presentedViewController` walks the ancestor chain and returns the modal's root view controller as a non-generic `UIViewController` pointer. That root IS the `UIHostingController`. Calling `.view.backgroundColor = .clear` on it produces the same effect as the current implementation.

What we gain if we ever revisit:

- Harmonises the file with the rest of the Presentation directory (one fewer architectural pattern to maintain in a small library).
- Drops the `parentController` responder-chain walk.
- Drops the `NSStringFromClass(...).contains("UIHostingController")` class-name match — `presentedViewController` is already a non-generic `UIViewController`, so we never need to *identify* the host as a `UIHostingController` to operate on it. The stringly-typed detection was judged "necessary" by Devin Review (R170) *given the current architecture*; under this alternative it ceases to be necessary at all.
- Drops the explicit `presentingViewController != nil` guard — `presentationController?.presentedViewController` is nil outside any modal context, so the "don't clear the app root host" protection is preserved by the natural nil-coalesce.

What it costs:

- ~60 LOC of churn for a private representable + controller, with no public API or behaviour change.
- Slightly larger view-hierarchy footprint (a child VC instead of a 1×1 hidden UIView). In practice this is what every other Presentation backport already does.
- Re-application points shift: `viewWillAppear` / `viewDidLayoutSubviews` / `traitCollectionDidChange` on the new Controller replace `didMoveToWindow` / `traitCollectionDidChange` on the current UIView. Equivalent in coverage but worth re-verifying on a device matrix before merging.

**Why deferred.** Pure refactor with no behaviour change and a bounded gain. PR #5 addressed the highest-impact Devin Review flag on the current implementation (the `as?` downcast) and the extension-level `@available(iOS, deprecated: 16.4)` consistency nit without touching this larger question. The cost/benefit on the deeper refactor isn't enough on its own; it earns its keep when paired with one of the triggers below.

**Triggers to revisit.**

- Apple renames or wraps `UIHostingController` in a way that breaks the `NSStringFromClass(...).contains("UIHostingController")` match. Switching to the alternative kills the dependency on that match.
- The `BottomActionSheet` `UIWindow`-overlay alternative (see entry below) is ever picked up — combine the architectural cleanup with that work so we end up with one consistent presentation backend.
- The library adds a third presentation modifier that wants the same "clear the host's chrome" capability, making the divergent pattern more expensive to maintain.

**References.**

- PR [#1](https://github.com/laconicman/SwiftUIBackports/pull/1) — original implementation.
- PR [#5](https://github.com/laconicman/SwiftUIBackports/pull/5) — minimum-impact refactor (drops the `as?` downcast, adds extension-level iOS deprecation). The deeper refactor described above was the sibling option deferred in favour of this entry.
- Devin Review analysis on PR #1: file-level "Different architectural approach from other presentation backports" flag (verdict: intentional and appropriate); `R170` "String-based UIHostingController detection is fragile but standard" flag (verdict: necessary under the current architecture).

### `BottomActionSheet`: `.fullScreenCover`-based vs. `UIWindow`-overlay implementation

**Current state.** `Backport.bottomActionSheet(...)` is implemented on top of `.fullScreenCover`. The system slide-up animation of the cover is suppressed by routing the presentation `Binding` through a wrapper that commits mutations inside `Transaction(disablesAnimations: true)`. The card's own slide-up / fade is driven by an internal `@State` flag plus `withAnimation`. The cover's outer view applies `.backport.presentationBackground(.clear)` so the host's background does not show through.

**Soft spots in the current implementation.**

- `Transaction.disablesAnimations` on a binding-mutation site is undocumented behaviour. SwiftUI honours it today on iOS 15–18, but Apple has never contractually promised it. If a future iOS release stops honouring it, the cover will gain back the default slide-up animation underneath the custom card animation. Failure mode is cosmetic, not functional.
- The `.backport.presentationBackground(.clear)` fallback on iOS 15–16.3 walks the responder chain to find the enclosing `UIHostingController` and clears its background. This is robust against intermediate-container shifts (matched by Objective-C class name via `NSStringFromClass`) and guarded by `presentingViewController != nil`, but is still a UIKit-level monkey-patch.
- The card-dismiss sequencing uses `CATransaction.setCompletionBlock` to drop the cover only after `withAnimation` settles. Widely used pattern, not strictly contractual; an obvious safety-net would be a `Task.sleep` deadline that re-introduces the magic-number problem we set out to avoid.

**Alternative implementation: own a `UIWindow` at `UIWindow.Level.alert`.**

Considered and not adopted in PR #3. The shape would be:

- Add a `UIWindow` on the active `UIWindowScene` with `windowLevel = .alert`.
- Install a `UIHostingController` whose `view.backgroundColor = .clear` from the start.
- Manage layout / safe-area / rotation / multi-window manually.

What we gain if we ever revisit:

- No `Transaction.disablesAnimations` trick at all — there is no system modal animation to suppress.
- No `BackgroundClearer` / `presentationBackground` fallback path needed for the cover itself — the host's background is clear from construction.
- Deployment floor for this modifier could drop to iOS 13 (the current floor is constrained by `.fullScreenCover` + the binding-wrapper trick).
- Works above other modals (`.sheet` / `.fullScreenCover` opened by the same screen) because the overlay is on its own window.

What it costs:

- ~40 LOC of pure scaffolding plus rotation and iPad multi-window edge cases.
- A second presentation backend in the library that has to be maintained alongside the existing `.fullScreenCover`-based path (or migrated wholesale, which is its own project).
- The current `.fullScreenCover`-based path is good enough for the iOS-15 floor this lib targets, so the cost has not paid for itself yet.

**Triggers to revisit.**

- The library opens a "robust modal extras" track (overlays that need to escape sheet contexts, in-app toasts that survive across navigation, etc.) and ends up needing a UIWindow overlay anyway — fold `bottomActionSheet` into that backend so we delete both SwiftUI tricks above.
- Apple changes the behaviour of `Transaction.disablesAnimations` at the binding-mutation site in a future iOS release.
- `CATransaction.setCompletionBlock` stops firing reliably under `withAnimation` for any reason.

**References.**

- PR [#3](https://github.com/laconicman/SwiftUIBackports/pull/3) — `feat/bottom-action-sheet`.
- PR [#1](https://github.com/laconicman/SwiftUIBackports/pull/1) — `feat/presentation-background-backport`. The responder-chain `BackgroundClearer` lives here and is reused by `bottomActionSheet`.
