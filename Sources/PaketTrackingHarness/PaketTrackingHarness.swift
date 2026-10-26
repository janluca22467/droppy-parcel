import DroppyKit
import DroppyKitHarness
import PaketTracking

@main
struct PaketTrackingHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { PaketTrackingDroplet() }
}
