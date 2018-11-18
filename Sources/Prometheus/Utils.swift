import Foundation

public struct EmptyCodable: MetricLabels {
    public init() { }
}

public struct EmptyHistogramCodable: HistogramLabels {
    public var le: String = ""
    public init() { }
}

public struct EmptySummaryCodable: SummaryLabels {
    public var quantile: String = ""
    public init() { }
}

public func encodeLabels<Labels: MetricLabels>(_ labels: Labels, _ excludingKeys: [String] = []) -> String {
    // TODO: Fix this up to a custom decoder or something
    do {
        let data = try JSONEncoder().encode(labels)
        guard var dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            return ""
        }
        excludingKeys.forEach { (key) in
            dictionary[key] = nil
        }
        var output = [String]()
        dictionary.forEach { (key, value) in
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
        } else if self == Double.leastNormalMagnitude {
            return "-Inf"
        } else {
            return "\(self)"
        }
    }
}

//: Numbers that can be represented as Double instances
public protocol DoubleRepresentable: Numeric {
    var doubleValue: Double {get}
}

//: Numbers that convert to other types
public protocol ConvertibleNumberType: DoubleRepresentable {}
public extension ConvertibleNumberType {
    public var floatValue: Float {get {return Float(doubleValue)}}
    public var intValue: Int {get {return lrint(doubleValue)}}
    public var CGFloatValue: CGFloat {get {return CGFloat(doubleValue)}}
}

extension FixedWidthInteger {
    public var doubleValue: Double {
        return Double(self)
    }
}

// Double Representable Conformance
extension Double: ConvertibleNumberType {public var doubleValue: Double {return self}}
extension CGFloat: ConvertibleNumberType {public var doubleValue: Double {return Double(self)}}
extension Float: ConvertibleNumberType {public var doubleValue: Double {return Double(self)}}
extension Int: ConvertibleNumberType { }
extension Int8: ConvertibleNumberType { }
extension Int16: ConvertibleNumberType { }
extension Int32: ConvertibleNumberType { }
extension Int64: ConvertibleNumberType { }
extension UInt: ConvertibleNumberType { }
extension UInt8: ConvertibleNumberType { }
extension UInt16: ConvertibleNumberType { }
extension UInt32: ConvertibleNumberType { }
extension UInt64: ConvertibleNumberType { }
