import Foundation
import SwiftData
import Testing
@testable import KumbaraData

@Suite("Depo yeri (specs/09 §0)")
struct ContainerTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ContainerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Eski depo ve yan dosyaları yeni klasöre taşınır")
    func movesLegacyStore() throws {
        let source = try temporaryDirectory(), destination = try temporaryDirectory()
        for suffix in ["", "-wal", "-shm"] {
            try Data("x\(suffix)".utf8).write(to: source.appending(path: "Kumbara.store\(suffix)"))
        }
        try KumbaraContainer.moveLegacyStore(from: source, to: destination)
        for suffix in ["", "-wal", "-shm"] {
            #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Kumbara.store\(suffix)").path))
            #expect(!FileManager.default.fileExists(atPath: source.appending(path: "Kumbara.store\(suffix)").path))
        }
    }

    @Test("Hedefte depo varsa hiçbir şeyin üzerine yazılmaz")
    func neverOverwrites() throws {
        let source = try temporaryDirectory(), destination = try temporaryDirectory()
        try Data("old".utf8).write(to: source.appending(path: "Kumbara.store"))
        try Data("new".utf8).write(to: destination.appending(path: "Kumbara.store"))
        try KumbaraContainer.moveLegacyStore(from: source, to: destination)
        #expect(try Data(contentsOf: destination.appending(path: "Kumbara.store")) == Data("new".utf8))
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "Kumbara.store").path))
    }

    @Test("Açılamayan depo silinmez, yan dosyalarıyla kenara alınır")
    func setAsideKeepsData() throws {
        let directory = try temporaryDirectory()
        let main = directory.appending(path: "Kumbara.store")
        for suffix in ["", "-wal", "-shm"] { try Data("v\(suffix)".utf8).write(to: URL(fileURLWithPath: main.path + suffix)) }
        let target = try #require(try KumbaraContainer.setAside(main, now: Date(timeIntervalSince1970: 1_793_000_000),
                                                                fileManager: .default))
        #expect(target.lastPathComponent == "Kumbara-acilamayan-1793000000.store")
        #expect(!FileManager.default.fileExists(atPath: main.path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: target.path + "-wal")) == Data("v-wal".utf8))
    }

    @Test("Kaynakta depo yoksa bir şey yapılmaz")
    func noLegacyStore() throws {
        let source = try temporaryDirectory(), destination = try temporaryDirectory()
        try KumbaraContainer.moveLegacyStore(from: source, to: destination)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
}

/// Testlerde oluşturulan bellek içi kapsayıcıları test boyunca canlı tutar.
@MainActor
final class ContainerBag {
    private var containers: [ModelContainer] = []

    func make() throws -> ModelContext {
        let container = try KumbaraContainer.make(inMemory: true)
        containers.append(container)
        return container.mainContext
    }
}
