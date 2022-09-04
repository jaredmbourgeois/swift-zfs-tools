import Foundation

extension ZFSTools {
  public class Poller {
    public typealias IsBusy = () -> Bool

    private var _isBusy: DispatchedValue<Bool>
    public var isBusy: Bool { _isBusy.value }
    public let isBusyHandler: IsBusy

    private let pollingQueue: DispatchQueue
    private let pollingTime: TimeInterval

    public init(
      pollingQueue: DispatchQueue = .global(),
      pollingTime: TimeInterval = 1,
      isBusy: @escaping IsBusy
    ) {
      self.pollingQueue = pollingQueue
      self.pollingTime = pollingTime
      isBusyHandler = isBusy
      _isBusy = .init(isBusy())
      queueUpdate()
    }

    private func queueUpdate() {
      guard _isBusy.value else { return }
      pollingQueue.asyncAfter(deadline: .now() + pollingTime) { [weak self] in
        self?.updateIsBusy()
        self?.queueUpdate()
      }
    }

    private func updateIsBusy() {
      _isBusy.value = isBusyHandler()
    }
  }
}
