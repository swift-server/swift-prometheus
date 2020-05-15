import Foundation

#if os(iOS) || os(watchOS) || os(tvOS)
import CoreGraphics
#endif

/// Empty labels class
public struct EmptyLabels: MetricLabels {
    /// Creates empty labels
    public init() { }
}

/// Empty labels class
public struct EmptyHistogramLabels: HistogramLabels {
    /// Bucket
    public var le: String = ""
    /// Creates empty labels
    public init() { }
}

/// Empty labels class
public struct EmptySummaryLabels: SummaryLabels {
    /// Quantile
    public var quantile: String = ""
    /// Creates empty labels
    public init() { }
}

/// Creates a Prometheus String representation of a `MetricLabels` instance
func encodeLabels<Labels: MetricLabels>(_ labels: Labels, _ excludingKeys: [String] = []) -> String {
    do {
        let data = try JSONEncoder().encode(labels)
        guard var dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            return ""
        }
        excludingKeys.forEach { (key) in
            dictionary[key] = nil
        }
        var output = [String]()
        dictionary.sorted { $0.key > $1.key }.forEach { (key, value) in
            output.append("\(key)=\"\(value)\"")
        }
        return output.isEmpty ? "" : "{\(output.joined(separator: ", "))}"
    } catch {
        return ""
    }
}

extension Double {
    /// Overwrite for use by Histogram bucketing
    var description: String {
        if self == Double.greatestFiniteMagnitude {
            return "+Inf"
        } else if self == Double.leastNonzeroMagnitude {
            return "-Inf"
        } else {
            return "\(self)"
        }
    }
}

/// Numbers that can be represented as Double instances
public protocol DoubleRepresentable: Numeric {
    /// Double value of the number
    var doubleValue: Double {get}
    
    init(_ double: Double)
    
    init(_ int: Int)
}

/// Numbers that convert to other types
public protocol ConvertibleNumberType: DoubleRepresentable {}
public extension ConvertibleNumberType {
    /// Number as a Float
    var floatValue: Float { return Float(doubleValue) }
    /// Number as an Int
    var intValue: Int { return lrint(doubleValue) }
    /// Number as a CGFloat
    var CGFloatValue: CGFloat { return CGFloat(doubleValue) }
}

/// Double Representable Conformance
extension FixedWidthInteger {
    /// Double value of the number
    public var doubleValue: Double {
        return Double(self)
    }
}

/// Double Representable Conformance
extension Double: ConvertibleNumberType { public var doubleValue: Double { return self }}
/// Double Representable Conformance
extension CGFloat: ConvertibleNumberType { public var doubleValue: Double { return Double(self) }}
/// Double Representable Conformance
extension Float: ConvertibleNumberType { public var doubleValue: Double { return Double(self) }}
/// Double Representable Conformance
extension Int: ConvertibleNumberType { }
/// Double Representable Conformance
extension Int8: ConvertibleNumberType { }
/// Double Representable Conformance
extension Int16: ConvertibleNumberType { }
/// Double Representable Conformance
extension Int32: ConvertibleNumberType { }
/// Double Representable Conformance
extension Int64: ConvertibleNumberType { }
/// Double Representable Conformance
extension UInt: ConvertibleNumberType { }
/// Double Representable Conformance
extension UInt8: ConvertibleNumberType { }
/// Double Representable Conformance
extension UInt16: ConvertibleNumberType { }
/// Double Representable Conformance
extension UInt32: ConvertibleNumberType { }
/// Double Representable Conformance
extension UInt64: ConvertibleNumberType { }
