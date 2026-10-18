import Testing

/// Deletes a ``ThrowawayPreferencesDomain`` once, after every test of the suite has run, so the suite waits for
/// cfprefsd's single delayed rewrite only once.
struct ThrowawayDomainCleanup: SuiteTrait, TestScoping {
    let domain: ThrowawayPreferencesDomain

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        do {
            try await function()
        } catch {
            await domain.delete()
            throw error
        }
        await domain.delete()
    }
}

extension Trait where Self == ThrowawayDomainCleanup {
    /// Deletes `domain` after the suite.
    static func deletes(_ domain: ThrowawayPreferencesDomain) -> Self {
        ThrowawayDomainCleanup(domain: domain)
    }
}
