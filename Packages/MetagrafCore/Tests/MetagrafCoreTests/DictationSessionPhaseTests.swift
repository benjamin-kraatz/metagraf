import Testing

@testable import MetagrafCore

@Test func copiedPhaseIsNotBusy() {
    let phase = DictationSession.Phase.copied("Copied instead — no text field is focused.")
    #expect(!phase.isBusy)
    #expect(DictationSession.Phase.failed("boom").isBusy == false)
    #expect(DictationSession.Phase.inserting.isBusy)
}

@Test func deliveryOutcomeDistinguishesCopied() {
    let inserted = DictationSession.DeliveryOutcome.inserted
    let copied = DictationSession.DeliveryOutcome.copied("on clipboard")
    #expect(inserted != copied)
    #expect(copied == .copied("on clipboard"))
}
