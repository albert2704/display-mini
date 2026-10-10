import Foundation
import DisplayCore

enum AdvancedControlTests {
    static let uuid = "00000000-0000-4000-8000-00000000F009"
    static func run() {
        let good: [String: Any] = ["schema": 1, "uuid": uuid, "transport": "standard", "serviceCount": 1, "delayMS": 50,
            "contrast": ["status": "ok", "attempts": 1, "current": 100, "maximum": 200],
            "input": ["status": "ok", "attempts": 1, "current": 17, "maximum": 0]]
        func parse(_ json: [String: Any]) -> AdvancedDDCProbe? {
            AdvancedDDCProbe.parse(try! JSONSerialization.data(withJSONObject: json), expectedUUID: uuid, timing: .standard)
        }
        precondition(parse(good)?.contrast.fraction == 0.5)
        precondition(parse(good)?.currentInput == 17, "Input is noncontinuous; zero maximum is valid")
        var zeroInput = good; zeroInput["input"] = ["status": "ok", "attempts": 1, "current": 0, "maximum": 0]
        precondition(parse(zeroInput)?.currentInput == nil && parse(zeroInput)?.contrast.fraction == 0.5,
                     "Zero is not an identified input and must never enable switching")
        for (key, bad) in [("schema", 2 as Any), ("uuid", UUID().uuidString), ("delayMS", 150), ("serviceCount", 2), ("transport", "ambiguous")] {
            var json = good; json[key] = bad
            precondition(parse(json) == nil, "Reject mismatched \(key)")
        }
        for invalid in [
            ["status": "ok", "attempts": 0, "current": 20, "maximum": 100],
            ["status": "ok", "attempts": 1, "current": 101, "maximum": 100],
            ["status": "ok", "attempts": 1, "current": 20, "maximum": 0],
            ["status": "ok", "attempts": 4, "current": 20, "maximum": 100]] as [[String: Any]] {
            var json = good; json["contrast"] = invalid; precondition(parse(json) == nil)
        }
        var unsupported = good
        unsupported["contrast"] = ["status": "unsupported", "attempts": 1]
        unsupported["input"] = ["status": "unsupported", "attempts": 1]
        precondition(parse(unsupported)?.contrast.fraction == nil && parse(unsupported)?.currentInput == nil)
        var noRoute = good; noRoute["transport"] = "none"; noRoute["serviceCount"] = 0
        noRoute["contrast"] = ["status": "notAvailable", "attempts": 0]
        noRoute["input"] = ["status": "notAvailable", "attempts": 0]
        precondition(parse(noRoute) != nil)
        var badInput = good; badInput["input"] = ["status": "ok", "attempts": 1, "current": -1]
        precondition(parse(badInput) == nil)
        precondition(MonitorInput.title(for: 17) == "HDMI 1")
        precondition(MonitorInput.title(for: 999).contains("0x03E7"))
        precondition(MonitorInput(rawValue: 999) == nil)

        func mode(_ refresh: Double, width: Int = 1920, pixelWidth: Int = 3840, pixelHeight: Int = 2160) -> FavoriteResolution {
            .init(width: width, height: 1080, pixelWidth: pixelWidth, pixelHeight: pixelHeight, refresh: refresh)!
        }
        let current = mode(60)
        let choices = RefreshRateSelection.options([mode(60), mode(59.94), mode(60), mode(0), mode(120),
            mode(75, width: 1280), mode(144, pixelWidth: 1920), mode(100, pixelHeight: 1080)], current: current)
        precondition(choices.map(\.refreshMilliHz) == [0, 59940, 60000, 120000])
        precondition(choices[0].refreshTitle == "Variable / system")
        precondition(choices[1].refreshTitle != choices[2].refreshTitle)
        print("Passed 3 advanced model scenarios (probe validation, input codes, exact refresh geometry).")
    }
}
