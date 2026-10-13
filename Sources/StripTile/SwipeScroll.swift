import Foundation

private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
private typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32

private func contactFrame(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?, _ count: Int32, _ timestamp: Double, _ frame: Int32) -> Int32 {
    SwipeScroll.shared.handle(touches, Int(count))
    return 0
}

final class SwipeScroll {
    static let shared = SwipeScroll()

    private static let touchStride = 96
    private static let normalizedXOffset = 32
    private static let normalizedYOffset = 36
    private static let axisLockDistance: CGFloat = 0.03
    private static let verticalWeight: CGFloat = 0.65
    private static let minInertiaVelocity: CGFloat = 0.0015

    var onScroll: ((CGFloat) -> Void)?
    var onSettle: (() -> Void)?

    private let lock = NSLock()
    private var targetFingers = 4
    private enum Axis { case undecided, horizontal, vertical }

    private var lastX: Float?
    private var lastY: Float?
    private var axis = Axis.undecided
    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var velocity: CGFloat = 0
    private var inertia: Timer?

    var fingers: Int {
        get { lock.withLock { targetFingers } }
        set { lock.withLock { targetFingers = newValue } }
    }

    @discardableResult
    func start() -> Bool {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createSym = dlsym(lib, "MTDeviceCreateList"),
              let registerSym = dlsym(lib, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(lib, "MTDeviceStart"),
              let list = unsafeBitCast(createSym, to: CreateList.self)()?.takeRetainedValue() else { return false }
        let register = unsafeBitCast(registerSym, to: Register.self)
        let startDevice = unsafeBitCast(startSym, to: Start.self)
        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, contactFrame)
            _ = startDevice(device, 0)
        }
        return count > 0
    }

    fileprivate func handle(_ touches: UnsafeMutableRawPointer?, _ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard count == targetFingers, let touches else {
            if lastX != nil { endGesture() }
            return
        }
        var sumX: Float = 0
        var sumY: Float = 0
        for index in 0..<count {
            let base = index * Self.touchStride
            sumX += touches.load(fromByteOffset: base + Self.normalizedXOffset, as: Float.self)
            sumY += touches.load(fromByteOffset: base + Self.normalizedYOffset, as: Float.self)
        }
        let x = sumX / Float(count)
        let y = sumY / Float(count)
        guard x.isFinite, y.isFinite, x > -0.1, x < 1.1 else { return }
        defer {
            lastX = x
            lastY = y
        }
        guard let previousX = lastX, let previousY = lastY else { return }
        let dx = CGFloat(x - previousX)
        let dy = CGFloat(y - previousY) * Self.verticalWeight

        switch axis {
        case .undecided:
            accumulatedX += dx
            accumulatedY += dy
            guard max(abs(accumulatedX), abs(accumulatedY)) > Self.axisLockDistance else { return }
            if abs(accumulatedX) > abs(accumulatedY) * 1.2 {
                axis = .horizontal
                emit(accumulatedX)
            } else {
                axis = .vertical
            }
        case .horizontal:
            emit(dx)
        case .vertical:
            break
        }
    }

    private func emit(_ dx: CGFloat) {
        velocity = velocity * 0.5 + dx * 0.5
        DispatchQueue.main.async { [self] in
            inertia?.invalidate()
            onScroll?(dx)
        }
    }

    private func endGesture() {
        let wasHorizontal = axis == .horizontal
        lastX = nil
        lastY = nil
        axis = .undecided
        accumulatedX = 0
        accumulatedY = 0
        let v = velocity
        velocity = 0
        guard wasHorizontal else { return }
        guard abs(v) > Self.minInertiaVelocity else {
            DispatchQueue.main.async { [self] in onSettle?() }
            return
        }
        DispatchQueue.main.async { [self] in
            var current = v
            inertia?.invalidate()
            inertia = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                current *= 0.95
                if abs(current) < 0.0003 {
                    timer.invalidate()
                    self?.onSettle?()
                    return
                }
                self?.onScroll?(current)
            }
        }
    }
}
