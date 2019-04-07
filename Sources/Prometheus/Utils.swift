import Foundation

/// Empty labels class
public struct EmptyLabels: MetricLabels {
    public init() { }
}

/// Empty labels class
public struct EmptyHistogramLabels: HistogramLabels {
    public var le: String = ""
    public init() { }
}

/// Empty labels class
public struct EmptySummaryLabels: SummaryLabels {
    public var quantile: String = ""
    public init() { }
}

internal extension Foundation.NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}

/// Creates a Prometheus String representation of a `MetricLabels` instance
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
        dictionary.sorted { $0.key > $1.key }.forEach { (key, value) in
            output.append("\(key)=\"\(value)\"")
        }
        return output.isEmpty ? "" : "{\(output.joined(separator: ", "))}"
    } catch {
        return ""
    }
}

/// A generic `String` based `CodingKey` implementation.
fileprivate struct StringCodingKey: CodingKey {
    /// `CodingKey` conformance.
    public var stringValue: String
    
    /// `CodingKey` conformance.
    public var intValue: Int? {
        return Int(self.stringValue)
    }
    
    /// Creates a new `StringCodingKey`.
    public init(_ string: String) {
        self.stringValue = string
    }
    
    /// `CodingKey` conformance.
    public init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    /// `CodingKey` conformance.
    public init(intValue: Int) {
        self.stringValue = intValue.description
    }
}

internal struct DimensionLabels: MetricLabels {
    let dimensions: [(String, String)]
    
    init() {
        self.dimensions = []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
    }
    
    static func == (lhs: DimensionLabels, rhs: DimensionLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"}
    }
}

internal struct DimensionHistogramLabels: HistogramLabels {
    var le: String
    let dimensions: [(String, String)]
    
    init() {
        self.le = ""
        self.dimensions = []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
        try container.encode(le, forKey: .init("le"))
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
        hasher.combine(le)
    }
    
    static func == (lhs: DimensionHistogramLabels, rhs: DimensionHistogramLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"} && rhs.le == lhs.le
    }
}

internal struct DimensionSummaryLabels: SummaryLabels {
    var quantile: String
    let dimensions: [(String, String)]
    
    init() {
        self.quantile = ""
        self.dimensions = []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try self.dimensions.forEach {
            try container.encode($0.1, forKey: .init($0.0))
        }
        try container.encode(quantile, forKey: .init("quantile"))
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(dimensions.map { "\($0.0)-\($0.1)"})
        hasher.combine(quantile)
    }
    
    static func == (lhs: DimensionSummaryLabels, rhs: DimensionSummaryLabels) -> Bool {
        return lhs.dimensions.map { "\($0.0)-\($0.1)"} == rhs.dimensions.map { "\($0.0)-\($0.1)"} && rhs.quantile == lhs.quantile
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
    var doubleValue: Double {get}
}

/// Numbers that convert to other types
public protocol ConvertibleNumberType: DoubleRepresentable {}
public extension ConvertibleNumberType {
    var floatValue: Float {get {return Float(doubleValue)}}
    var intValue: Int {get {return lrint(doubleValue)}}
    var CGFloatValue: CGFloat {get {return CGFloat(doubleValue)}}
}

/// Double Representable Conformance
extension FixedWidthInteger {
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
