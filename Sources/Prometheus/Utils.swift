import Foundation

public struct EmptyCodable: MetricLabels {
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

func calculateQuantiles(quantiles: [Double], values: [Double]) -> [Double: Double] {
    let values = values.sorted()
    var quantilesMap: [Double: Double] = [:]
    quantiles.forEach { (q) in
        quantilesMap[q] = quantile(q, values)
    }
    return quantilesMap
}

func quantile(_ q: Double, _ values: [Double]) -> Double {
    if values.count == 1 {
        return values[0]
    }
    
    let n = Double(values.count)
    if let pos = Int(exactly: n*q) {
        if pos < 2 {
            return values[0]
        } else if pos == values.count {
            return values[pos - 1]
        }
        return (values[pos - 1] + values[pos]) / 2.0
    } else {
        let pos = Int((n*q).rounded(.up))
        return values[pos - 1]
    }
}

extension Double {
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
