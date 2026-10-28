import Foundation
import SwiftUI

/// 應用程式的相依組裝。啟動失敗時不崩潰，改成顯示可讀的錯誤畫面。
@MainActor
final class AppEnvironment: ObservableObject {

    struct Services {
        let taxonomy: Taxonomy
        let vocabulary: TagVocabulary
        let styles: StyleVocabulary
        let textures: TextureVocabulary
        let database: AppDatabase
        let repository: SoundRepository
        let collections: CollectionStore
        let metadata: ManualMetadataService
        let review: ReviewService
        let mapper: OrganizerResultMapper
        let validator: OrganizerSchemaValidator
        let organizer: OrganizerEngine
        let libraryManager: LibraryManager
        let scanner: LibraryScanner
        let waveforms: WaveformStore
        let folderPicker: FolderPicker
    }

    @Published private(set) var services: Services?
    @Published private(set) var startupError: String?

    init() {
        // Hosted XCTest must never open or migrate the user's persistent database.
        // Each test constructs its own in-memory or temporary database explicitly.
        guard ProcessInfo.processInfo.environment["FOLEY_TEST_HOST"] != "1" else { return }
        do {
            services = try AppEnvironment.boot()
            AppLog.app.info("啟動完成")
        } catch {
            startupError = error.localizedDescription
            AppLog.app.error("啟動失敗：\(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func boot() throws -> Services {
        let taxonomy = try Taxonomy.load()
        let vocabulary = try TagVocabulary.load()
        let styles = try StyleVocabulary.load()
        let textures = try TextureVocabulary.load()
        let database = try AppDatabase.makeShared(taxonomy: taxonomy)
        let repository = SoundRepository(database: database)
        let collections = CollectionStore(database: database)
        let metadata = ManualMetadataService(database: database)
        let review = ReviewService(database: database)
        let validator = OrganizerSchemaValidator(taxonomy: taxonomy, vocabulary: vocabulary)
        let mapper = OrganizerResultMapper(validator: validator, policy: .default)

        return Services(taxonomy: taxonomy,
                        vocabulary: vocabulary,
                        styles: styles,
                        textures: textures,
                        database: database,
                        repository: repository,
                        collections: collections,
                        metadata: metadata,
                        review: review,
                        mapper: mapper,
                        validator: validator,
                        organizer: LocalAnalysisEngine(taxonomy: taxonomy,
                                                      vocabulary: vocabulary,
                                                      styles: styles,
                                                      textures: textures),
                        libraryManager: LibraryManager(database: database),
                        scanner: LibraryScanner(database: database),
                        waveforms: WaveformStore(database: database),
                        folderPicker: SystemFolderPicker())
    }
}
