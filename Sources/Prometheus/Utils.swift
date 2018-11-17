import Foundation

public struct EmptyCodable: MetricLabels {
    public init() { }
}

public func encodeLabels<Labels: MetricLabels>(_ labels: Labels) -> String {
    let encoder = JSONEncoder()
    do {
        let data = try encoder.encode(labels)
        let encodedString = String(data: data, encoding: .utf8)?.replacingOccurrences(of: "{\"", with: "{").replacingOccurrences(of: "\":", with: "=") ?? ""
        return encodedString
    } catch {
        return ""
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
