#if os(macOS)
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import MetagrafCore

/// Reads only the currently focused accessibility element. It never traverses
/// the rest of the window or consults the clipboard.
@MainActor
struct FocusedContextReader {
    func capture(applicationName: String?) -> RefinementDestinationContext {
        guard AXIsProcessTrusted(), let focused = focusedElement() else {
            return RefinementDestinationContext(applicationName: applicationName)
        }

        let role = stringAttribute(kAXRoleAttribute, from: focused)
        let subrole = stringAttribute(kAXSubroleAttribute, from: focused)
        let isSecure = IsSecureEventInputEnabled()
            || subrole == kAXSecureTextFieldSubrole
            || role?.localizedCaseInsensitiveContains("secure") == true

        let windowTitle = elementAttribute(kAXWindowAttribute, from: focused)
            .flatMap { stringAttribute(kAXTitleAttribute, from: $0) }
        let title = stringAttribute(kAXTitleAttribute, from: focused)
        let elementDescription = stringAttribute(kAXDescriptionAttribute, from: focused)
            ?? stringAttribute(kAXHelpAttribute, from: focused)
        let placeholder = stringAttribute(kAXPlaceholderValueAttribute, from: focused)

        var selectedText: String?
        var nearbyText: String?

        if !isSecure {
            let selection = rangeAttribute(kAXSelectedTextRangeAttribute, from: focused)
            let characterCount = numberAttribute(kAXNumberOfCharactersAttribute, from: focused)

            if let selection, let characterCount {
                if selection.length > 0 {
                    let selectedRange = CFRange(
                        location: selection.location,
                        length: min(selection.length, RefinementContextLimit.maximumTextCharacters)
                    )
                    selectedText = string(for: selectedRange, from: focused)
                }

                let remaining = RefinementContextLimit.maximumTextCharacters - (selectedText?.count ?? 0)
                let excerpt = RefinementContextLimit.excerptRange(
                    totalLength: characterCount,
                    selection: NSRange(location: selection.location, length: selection.length),
                    maximumLength: remaining
                )
                if excerpt.length > 0 {
                    nearbyText = string(
                        for: CFRange(location: excerpt.location, length: excerpt.length),
                        from: focused
                    )
                }
            } else {
                // Some custom controls expose selected text but not ranges.
                selectedText = stringAttribute(kAXSelectedTextAttribute, from: focused)
            }
        }

        return RefinementContextLimit.bounded(
            applicationName: applicationName,
            windowTitle: windowTitle,
            focusedElementRole: role,
            focusedElementTitle: title,
            focusedElementDescription: elementDescription,
            placeholder: placeholder,
            selectedText: selectedText,
            nearbyText: nearbyText,
            isSecure: isSecure
        )
    }

    private func focusedElement() -> AXUIElement? {
        elementAttribute(kAXFocusedUIElementAttribute, from: AXUIElementCreateSystemWide())
    }

    private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private func numberAttribute(_ name: String, from element: AXUIElement) -> Int? {
        (attribute(name, from: element) as? NSNumber)?.intValue
    }

    private func elementAttribute(_ name: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, from: element), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func rangeAttribute(_ name: String, from element: AXUIElement) -> CFRange? {
        guard
            let value = attribute(name, from: element),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func string(for range: CFRange, from element: AXUIElement) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else { return nil }
        return value as? String
    }
}
#endif
