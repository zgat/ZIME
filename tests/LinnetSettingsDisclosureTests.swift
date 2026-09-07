import AppKit
import SwiftUI

private final class DisclosureProbeState: ObservableObject {
  @Published var expanded = false
  var labelFrame = CGRect.zero
}

private struct DisclosureLabelFrame: PreferenceKey {
  static var defaultValue = CGRect.zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct DisclosureProbe: View {
  @ObservedObject var state: DisclosureProbeState
  let title: String

  var body: some View {
    VStack {
      DisclosureGroup(isExpanded: $state.expanded) {
        Text("Revealed content").frame(height: 40)
      } label: {
        Text(verbatim: title)
          .background(GeometryReader { proxy in
            Color.clear.preference(key: DisclosureLabelFrame.self,
              value: proxy.frame(in: .named("probe")))
          })
      }
      .disclosureGroupStyle(LinnetSettingsDisclosureStyle())
      Spacer()
    }
    .padding(12)
    .coordinateSpace(name: "probe")
    .onPreferenceChange(DisclosureLabelFrame.self) { state.labelFrame = $0 }
  }
}

@main
struct LinnetSettingsDisclosureTests {
  @MainActor
  static func main() {
    _ = NSApplication.shared
    for width: CGFloat in [300, 680] {
      for title in ["Manual recovery & transfer", "Diagnostics", "手动恢复与迁移", "诊断"] {
        verify(title: title, width: width)
      }
    }
    print("LinnetSettingsDisclosureTests: PASS (arrow, label, blank header, repeat toggle)")
  }

  @MainActor
  private static func verify(title: String, width: CGFloat) {
    let state = DisclosureProbeState()
    let host = NSHostingView(rootView: DisclosureProbe(state: state, title: title))
    let window = NSPanel(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 160),
      styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.close() }
    settle(host)
    require(!state.expanded && state.labelFrame.width > 0, "disclosure must start collapsed")
    let label = state.labelFrame
    // Local view events only: never activate an application or inject global input.
    for point in [CGPoint(x: label.minX - 14, y: label.midY),
                  CGPoint(x: label.midX, y: label.midY),
                  CGPoint(x: width - 24, y: label.midY)] {
      for expected in [true, false] {
        click(point, host: host, window: window)
        settle(host)
        require(state.expanded == expected,
          "header hit did not toggle \(title), width \(width), point \(point)")
      }
    }

  }

  @MainActor
  private static func click(_ point: CGPoint, host: NSView, window: NSWindow) {
    let location = host.convert(point, to: nil)
    for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
      guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
      else { fatalError("could not create local mouse event") }
      NSApp.sendEvent(event)
    }
  }

  @MainActor
  private static func settle(_ host: NSView) {
    for _ in 0..<8 {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
  }

  private static func require(_ condition: Bool, _ message: String) {
    if !condition {
      fputs("LinnetSettingsDisclosureTests: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
