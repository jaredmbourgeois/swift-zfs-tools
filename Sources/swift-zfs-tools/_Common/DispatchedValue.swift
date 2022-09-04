import Dispatch
import Foundation

public class DispatchedValue<ValueType: Any> {
  private let queue: DispatchQueue
//  private let valueSemaphore = DispatchSemaphore(value: 1)

  private var _value: ValueType
  public var value: ValueType {
    get {
//      valueSemaphore.wait()
//      let value = _value
//      valueSemaphore.signal()
//      return value
      queue.sync {
        return _value
      }
    }
    set {
//      valueSemaphore.wait()
//      _value = newValue
//      valueSemaphore.signal()
      queue.sync {
        _value = newValue
      }
    }
  }

  public init(
    _ _value: ValueType,
    queue: DispatchQueue? = nil
  ) {
    self.queue = queue ?? DispatchQueue(
      label: "DispatchedValue<\(String(describing: ValueType.self))>\(UUID().uuidString)",
      qos: .default
    )
    self._value = _value
  }
}
