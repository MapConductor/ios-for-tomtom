import XCTest

final class DragTest: XCTestCase {
    func testMarkerDrag() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(9) // let the TomTom map + marker finish loading on-device
        attach(name: "01-before")

        // Pin sits near the center (Amsterdam). Press-and-drag it down-right.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.51, dy: 0.49))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.64))
        start.press(forDuration: 0.2, thenDragTo: end)

        sleep(2)
        attach(name: "02-after")
        XCTAssertEqual(app.state, .runningForeground) // no freeze / crash
    }

    private func attach(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
