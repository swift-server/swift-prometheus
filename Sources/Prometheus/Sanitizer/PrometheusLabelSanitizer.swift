/// Default implementation of `LabelSanitizer` that sanitizes any characters not
/// allowed by Prometheus to an underscore (`_`).
///
/// See `https://prometheus.io/docs/concepts/data_model/#metric-names-and-labels` for more info.
public struct PrometheusLabelSanitizer: LabelSanitizer {
    private static let uppercaseAThroughZ = UInt8(ascii: "A") ... UInt8(ascii: "Z")
    private static let lowercaseAThroughZ = UInt8(ascii: "a") ... UInt8(ascii: "z")
    private static let zeroThroughNine = UInt8(ascii: "0") ... UInt8(ascii: "9")

    public init() { }

    public func sanitize(_ label: String) -> String {
        if PrometheusLabelSanitizer.isSanitized(label) {
            return label
        } else {
            return PrometheusLabelSanitizer.sanitizeLabel(label)
        }
    }

    /// Returns a boolean indicating whether the label is already sanitized.
    private static func isSanitized(_ label: String) -> Bool {
        return label.utf8.allSatisfy(PrometheusLabelSanitizer.isValidCharacter(_:))
    }
    
    /// Returns a boolean indicating whether the character may be used in a label.
    private static func isValidCharacter(_ codePoint: String.UTF8View.Element) -> Bool {
        switch codePoint {
        case PrometheusLabelSanitizer.lowercaseAThroughZ,
             PrometheusLabelSanitizer.zeroThroughNine,
             UInt8(ascii: ":"),
             UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    private static func sanitizeLabel(_ label: String) -> String {
        let sanitized: [UInt8] = label.utf8.map { character in
            if PrometheusLabelSanitizer.isValidCharacter(character) {
                return character
            } else {
                return PrometheusLabelSanitizer.sanitizeCharacter(character)
            }
        }
        
        return String(decoding: sanitized, as: UTF8.self)
    }
    
    private static func sanitizeCharacter(_ character: UInt8) -> UInt8 {
        if PrometheusLabelSanitizer.uppercaseAThroughZ.contains(character) {
            // Uppercase, so shift to lower case.
            return character + (UInt8(ascii: "a") - UInt8(ascii: "A"))
        } else {
            return UInt8(ascii: "_")
        }
    }
}
