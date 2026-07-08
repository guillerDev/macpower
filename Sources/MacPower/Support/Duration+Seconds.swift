import Foundation

extension Duration {
    /// The duration expressed as a floating-point number of seconds.
    var inSeconds: Double {
        let (s, attos) = components
        return Double(s) + Double(attos) / 1e18
    }
}
