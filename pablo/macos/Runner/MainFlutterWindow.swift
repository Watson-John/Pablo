import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Pablo's shell (sidebar + gallery + optional panels) is designed for a
    // minimum of 960x600; below that the justified gallery + top/bottom bars
    // are squeezed past their content and Flutter throws RenderFlex/hit-test
    // layout errors that also eat pointer events. Enforce the design minimum so
    // the app can't be resized into that broken state.
    self.contentMinSize = NSSize(width: 960, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
