import Foundation

struct BatchTestResult: Sendable {
    let completed: Int
    let succeeded: Int
    let failed: Int
    let duration: TimeInterval
}

@MainActor
struct BatchTestRunner {
    let testOne: (String) async throws -> ModelTestSummary

    func run(models: [ModelInfo], onResult: @escaping (String, Result<ModelTestSummary, Error>) async -> Void, onProgress: @escaping (Int, Int) -> Void) async -> BatchTestResult {
        let start = ContinuousClock.now
        var succeeded = 0
        var completed = 0
        for model in models {
            if Task.isCancelled { break }
            let result: Result<ModelTestSummary, Error>
            do {
                result = .success(try await testOne(model.id))
            } catch {
                result = .failure(error)
            }
            if case .success(let summary) = result, summary.success { succeeded += 1 }
            completed += 1
            await onResult(model.id, result)
            onProgress(completed, models.count)
        }
        return BatchTestResult(completed: completed, succeeded: succeeded, failed: completed - succeeded, duration: start.duration(to: .now).timeInterval)
    }
}
