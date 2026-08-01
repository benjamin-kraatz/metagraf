import Foundation
import Testing

@testable import MetagrafCore

private let origin = Date(timeIntervalSinceReferenceDate: 0)

private func at(_ offset: TimeInterval) -> Date {
    origin.addingTimeInterval(offset)
}

@Suite("Hold to talk")
struct HoldToTalkMachineTests {
    @Test("A deliberate hold records and completes")
    func deliberateHold() {
        var machine = HoldToTalkMachine()

        #expect(machine.handle(.keyDown, at: at(0)) == .begin)
        #expect(machine.isDictating)
        #expect(machine.handle(.keyUp, at: at(1.2)) == .complete)
        #expect(!machine.isDictating)
    }

    @Test("A brush of the key is thrown away")
    func accidentalTap() {
        var machine = HoldToTalkMachine()

        #expect(machine.handle(.keyDown, at: at(0)) == .begin)
        #expect(machine.handle(.keyUp, at: at(0.1)) == .cancel)
    }

    @Test("A second quick tap latches recording on")
    func doubleTapLatches() {
        var machine = HoldToTalkMachine()

        // First tap: starts and is discarded.
        #expect(machine.handle(.keyDown, at: at(0)) == .begin)
        #expect(machine.handle(.keyUp, at: at(0.1)) == .cancel)

        // Second tap lands inside the double-tap window and latches instead.
        #expect(machine.handle(.keyDown, at: at(0.3)) == .begin)
        #expect(machine.handle(.keyUp, at: at(0.4)) == nil)
        #expect(machine.isLatchedOn)
        #expect(machine.isDictating)

        // Any later press ends the latched session.
        #expect(machine.handle(.keyDown, at: at(5)) == .complete)
        #expect(!machine.isLatchedOn)
        #expect(!machine.isDictating)
    }

    @Test("Two taps too far apart do not latch")
    func slowTapsDoNotLatch() {
        var machine = HoldToTalkMachine()

        #expect(machine.handle(.keyDown, at: at(0)) == .begin)
        #expect(machine.handle(.keyUp, at: at(0.1)) == .cancel)

        #expect(machine.handle(.keyDown, at: at(2)) == .begin)
        #expect(machine.handle(.keyUp, at: at(2.1)) == .cancel)
        #expect(!machine.isLatchedOn)
    }

    @Test("Escape abandons an in-flight dictation")
    func escapeAborts() {
        var machine = HoldToTalkMachine()

        #expect(machine.handle(.keyDown, at: at(0)) == .begin)
        #expect(machine.handle(.abort, at: at(0.5)) == .abort)
        #expect(!machine.isDictating)

        // And does nothing when idle.
        #expect(machine.handle(.abort, at: at(1)) == nil)
    }

    @Test("Repeated key-down events from other modifiers are ignored")
    func repeatedKeyDownIsIgnored() {
        var machine = HoldToTalkMachine()

        #expect(machine.handle(.keyDown, at: at(0)) == .begin)
        #expect(machine.handle(.keyDown, at: at(0.05)) == nil)
        #expect(machine.handle(.keyUp, at: at(1)) == .complete)
    }

    @Test("A release without a press does nothing")
    func strayKeyUp() {
        var machine = HoldToTalkMachine()
        #expect(machine.handle(.keyUp, at: at(0)) == nil)
    }

    @Test("Latching survives a long hold on the latching tap")
    func latchThenLongPressEnds() {
        var machine = HoldToTalkMachine()

        _ = machine.handle(.keyDown, at: at(0))
        _ = machine.handle(.keyUp, at: at(0.1))
        _ = machine.handle(.keyDown, at: at(0.3))
        _ = machine.handle(.keyUp, at: at(0.4))
        #expect(machine.isLatchedOn)

        // Ending a latched session works regardless of how long the key is held.
        #expect(machine.handle(.keyDown, at: at(10)) == .complete)
        #expect(machine.handle(.keyUp, at: at(11)) == nil)
    }
}
