import ModeKit
import Testing

struct SchemaVersionTests {
    @Test
    func currentVersionIsPositive() {
        #expect(SchemaVersion.current > 0)
    }

    /// Bumping the version must come with a migration from the previous one;
    /// this test changes in the same commit as that migration.
    @Test
    func currentVersionIsInitialVersionWhileNoMigrationExists() {
        let initialSchemaVersion = 1

        #expect(SchemaVersion.current == initialSchemaVersion)
    }
}
