import ServiceLifecycle
import OSLog

struct HealdService: Service {
    func run() async throws {
        Logger.lifecycle.info("HealdService running — idle (phase 1 skeleton)")

        try await withGracefulShutdownHandler {
            // Suspend until graceful shutdown is triggered.
            // This is a true suspension — no busy loop, no Timer, no Task.sleep loop.
            // CPU usage while suspended: 0%. RAM: Swift runtime only (~5-10MB).
            try await Task.sleep(for: .seconds(Int.max))
        } onGracefulShutdown: {
            // This callback runs synchronously on the shutdown signal.
            // Write shutdown log here — guaranteed before process exits.
            Logger.lifecycle.info("HealdService shutting down cleanly")
        }
    }
}
