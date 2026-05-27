![watchOS](https://img.shields.io/badge/watchOS-DE1F51)
![macOS](https://img.shields.io/badge/macOS-EE751F)
![tvOS](https://img.shields.io/badge/tvOS-00B9BB)
![ios](https://img.shields.io/badge/iOS-0C62C7)
[![swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fshaps80%2FSwiftUIBackports%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/shaps80/SwiftUIBackports)

# SwiftUI Backports

Introducing a collection of SwiftUI backports to make your iOS development easier.

Many backports support iOS 13+ but where UIKIt features were introduced in later versions, the same will be applicable to these backports, to keep parity with UIKit.

In some cases, I've also included additional APIs that bring more features to your SwiftUI development.

> Note, **all** backports will be API-matching to Apple's official APIs, any additional features will be provided separately.

All backports are fully documented, in most cases using Apple's own documentation for consistency. Please refer to the header docs or Apple's original documentation for more details.

There is also a [Demo project](https://github.com/shaps80/SwiftUIBackportsDemo) available where you can see full demonstrations of all backports and additional features, including reference code to help you get started.

> Lastly, I hope this repo also serves as a great resource for _how_ you can backport effectively with minimal hacks 👍

## Sponsor

Building useful libraries like these, takes time away from my family. I build these tools in my spare time because I feel its important to give back to the community. Please consider [Sponsoring](https://github.com/sponsors/shaps80) me as it helps keep me working on useful libraries like these 😬

You can also give me a follow and a 'thanks' anytime.

[![Twitter](https://img.shields.io/badge/Twitter-@shaps-4AC71B)](http://twitter.com/shaps)

## Usage

The library adopts a backport design by [Dave DeLong](https://davedelong.com/blog/2021/10/09/simplifying-backwards-compatibility-in-swift/) that makes use of a single type to improve discoverability and maintainability when the time comes to remove your backport implementations, in favour of official APIs.

Backports of pure types, can easily be discovered under the `Backport` namespace. Similarly, modifiers are discoverable under the `.backport` namespace.

> Unfortunately `Environment` backports cannot be access this way, in those cases the Apple API values will be prefixed with `backport` to simplify discovery.

Types:

```swift
@Backport.AppStorage("filter-enabled")
private var filterEnabled: Bool = false
```

Modifier:

```swift
Button("Show Prompt") {
    showPrompt = true
}
.sheet(isPresented: $showPrompt) {
    Prompt()
        .backport.presentationDetents([.medium, .large])
}
```

Environment:

```swift
@Environment(\.backportRefresh) private var refreshAction
```

## Scope

The library ships two layers, kept in separate sections below:

- **Backports** — API-matching polyfills for SwiftUI features introduced in later OS versions. Signatures, semantics, and naming track Apple's official APIs so consumers can drop the `.backport` namespace once they raise their deployment target.
- **Extras** — non-backport SwiftUI features that don't have a native equivalent. These follow the same `.backport.` discoverability convention but are intentionally scoped to gaps the platform doesn't fill. If you want a more general-purpose component (e.g. a detent-style bottom sheet that mirrors `presentationDetents` on iOS < 16.4), point a dedicated dependency at it instead — for instance [`c-villain/BottomSheets`](https://github.com/c-villain/BottomSheets).

## Backports

**SwiftUI**

- `AsyncImage`
- `AppStorage`
- `background` – ViewBuilder API
- `DismissAction`
- `DynamicTypeSize`
– `Label`
– `LabeledContent`
- `NavigationDestination` – uses a standard NavigationView
- `navigationTitle` – newer API
- `overlay` – ViewBuilder API
- `onChange`
- `openURL`
- `ProgressView`
- `presentationBackground`
- `presentationDetents`
- `presentationDragIndicator`
- `quicklookPreview`
- `requestReview`
- `Refreshable` – includes pull-to-refresh 
- `ScaledMetric`
- `ShareLink`
- `StateObject`
- `scrollDisabled`
- `scrollDismissesKeyboard`
- `scrollIndicators`
- `Section(_ header:)`
- `task` – async/await modifier

**UIKit**

- `UIHostingConfiguration` – simplifies embedding SwiftUI in `UICollectionViewCell` and `UITableViewCell`

## Extras

**Modal Presentations**

Adding this to your presented view, you can use the provided closure to present an `ActionSheet` to a user when they attempt to dismiss interactively. You can also use this to disable interactive dismissals entirely.

```swift
presentation(isModal: true) { /* attempt */ }
```

**FittingGeometryReader**

A custom `GeometryReader` implementation that correctly auto-sizes itself to its content. This is useful in many cases where you need a `GeometryReader` but don't want it to implicitly take up its parent View's bounds.

**FittingScrollView**

A custom `ScrollView` that respects `Spacer`'s when the content is not scrollable. This is useful when you need to place a view at the edges of your scrollview while its content is small enough to not require scrolling. Another great use case is vertically centered content that becomes `top` aligned once the content requires scrolling.

**BottomActionSheet** (iOS only)

A bottom-anchored action-sheet card that always slides up from the bottom of the screen and sizes to its content, on every iOS device and size class — including iPad regular size class, where `.confirmationDialog` and `.sheet + presentationDetents` fall back to popovers. Mirrors the `.sheet` API surface with `isPresented:` and `item:` overloads. Dismissal works via the consumer's binding, `@Environment(\.dismiss)` (iOS 15+) from inside `content`, backdrop tap, swipe-down, VoiceOver escape, and hardware Escape — all routed through the same card-exit animation. Supports `.isModal`, Reduce Motion, and drag-to-dismiss.

```swift
struct CancelSheetContent: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Cancel") { dismiss() }
    }
}

someView
    .backport.bottomActionSheet(isPresented: $isShowing) {
        CancelSheetContent()
    }
```

Different shape from a detent-style bottom sheet (fills modal heights, drag between detents). For that, see [`c-villain/BottomSheets`](https://github.com/c-villain/BottomSheets).

## Installation

You can install manually (by copying the files in the `Sources` directory) or using Swift Package Manager (**preferred**)

To install using Swift Package Manager, add this to the `dependencies` section of your `Package.swift` file:

`.package(url: "https://github.com/shaps80/SwiftUIBackports.git", .upToNextMajor(from: "2.0.0"))`
