import Foundation

/// Light or dark: the system's appearance, unless the reader picked the other one.
///
/// The override is a single optional flag (`true` dark, `false` light, `nil` follow macOS).
/// Swapping (`⇧⌘N`, the toolbar's sun) always shows the other appearance; when that is the
/// system's own, the override goes away and the reader follows macOS again. The same happens
/// when macOS itself switches to the appearance the reader had picked.
public enum AppearanceChoice {
    public static func isDark(override: Bool?, systemIsDark: Bool) -> Bool {
        override ?? systemIsDark
    }

    /// The override after swapping light and dark.
    public static func override(afterSwapping current: Bool?, systemIsDark: Bool) -> Bool? {
        let wanted = !isDark(override: current, systemIsDark: systemIsDark)
        return wanted == systemIsDark ? nil : wanted
    }

    /// The override once macOS has changed appearance: dropped if it now says the same.
    public static func reconciled(_ current: Bool?, systemIsDark: Bool) -> Bool? {
        current == systemIsDark ? nil : current
    }
}
