import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let trafficLightXOffset: CGFloat = 18
  private let trafficLightYOffset: CGFloat = -10
  private var trafficLightBaseFrames: [Int: NSRect] = [:]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Hide the native title bar so Flutter can own the top area.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(shiftTrafficLights),
      name: NSWindow.didBecomeKeyNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(shiftTrafficLights),
      name: NSWindow.didResizeNotification,
      object: self
    )

    scheduleTrafficLightShift()

    super.awakeFromNib()
  }

  private func scheduleTrafficLightShift() {
    DispatchQueue.main.async { [weak self] in
      self?.shiftTrafficLights()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.shiftTrafficLights()
    }
  }

  @objc private func shiftTrafficLights() {
    let buttons = [
      self.standardWindowButton(.closeButton),
      self.standardWindowButton(.miniaturizeButton),
      self.standardWindowButton(.zoomButton)
    ].compactMap { $0 }

    guard buttons.count == 3 else { return }

    if trafficLightBaseFrames.count != buttons.count {
      trafficLightBaseFrames = Dictionary(
        uniqueKeysWithValues: buttons.enumerated().map { ($0.offset, $0.element.frame) }
      )
    }

    buttons.enumerated().forEach { index, button in
      guard var frame = trafficLightBaseFrames[index] else { return }
      frame.origin.x += trafficLightXOffset
      frame.origin.y += trafficLightYOffset
      button.frame = frame
    }
  }
}
