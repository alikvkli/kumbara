// kumbara-ocr <girdi-klasörü> <çıktı-klasörü>
//
// Her `ad.jpg|png|pdf` için uygulamadaki `TextRecognizer` ile OCR yapar ve yanındaki
// `ad.truth.json` doğru cevabıyla birlikte KumbaraCore test fixture biçiminde `ad.json` yazar
// (specs/04 §6). Görüntü cihazdan/makineden çıkmaz; ağ kullanılmaz.
import Foundation
import KumbaraCapture
import KumbaraCore
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("kullanım: kumbara-ocr <girdi> <çıktı>\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter { ["jpg", "jpeg", "png", "pdf", "heic"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var failures = 0
for file in files {
    let name = file.deletingPathExtension().lastPathComponent
    let truthURL = input.appendingPathComponent(name + ".truth.json")
    var truth = (try? JSONSerialization.jsonObject(with: Data(contentsOf: truthURL))) as? [String: Any] ?? ["kind": "?"]
    do {
        let data = try Data(contentsOf: file)
        let document = try await TextRecognizer.recognize(data: data, contentType: UTType(filenameExtension: file.pathExtension))
        let source = truth.removeValue(forKey: "source") as? String ?? "device"
        let now = truth.removeValue(forKey: "now") as? String ?? ISO8601DateFormatter().string(from: .now)
        let description = truth.removeValue(forKey: "description") as? String ?? name
        var object: [String: Any] = [
            "source": source,
            "description": description,
            "now": now,
            "lines": document.lines.map { [$0.text, round4($0.box.x), round4($0.box.y), round4($0.confidence)] },
            "expect": truth.filter { !["generator", "seed", "license", "attribution", "url"].contains($0.key) },
        ]
        for key in ["license", "attribution", "url", "generator", "seed"] where truth[key] != nil {
            object[key] = truth[key]
        }
        let json = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: output.appendingPathComponent(name + ".json"))
        print("✓ \(name): \(document.lines.count) satır")
    } catch {
        failures += 1
        print("✗ \(name): \(error)")
    }
}
print("\(files.count - failures)/\(files.count) dosya okundu")

func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
