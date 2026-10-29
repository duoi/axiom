import AppKit

extension HUDController {
    func plateScreenFrame() -> CGRect? {
        guard let plate = chrome?.plate, let window = plate.window else {
            return panel.isVisible ? panel.cardFrame : nil
        }
        let rect = plate.convert(plate.bounds, to: nil)
        return window.convertToScreen(rect)
    }

    func syncDictationGlow() {
        guard IntelligenceGlowPolicy.showsDictationBorder(dictating: model.dictating), panel.isVisible else {
            CaptureHighlight.hidePersistent()
            return
        }
        CaptureHighlight.showPersistent(
            frame: plateScreenFrame(),
            cornerRadius: IntelligenceGlowPolicy.cornerRadius(isHUD: true),
            context: .listening
        )
    }

    func refreshActiveGlow() {
        if IntelligenceGlowPolicy.showsDictationBorder(dictating: model.dictating), panel.isVisible {
            CaptureHighlight.refreshPersistentIfNeeded(
                frame: plateScreenFrame(),
                cornerRadius: IntelligenceGlowPolicy.cornerRadius(isHUD: true),
                context: .listening
            )
        }
    }

    func flashHUDGlow() {
        CaptureHighlight.flash(
            frame: plateScreenFrame(),
            cornerRadius: IntelligenceGlowPolicy.cornerRadius(isHUD: true),
            context: .capture,
            space: .appKit
        )
    }
}
