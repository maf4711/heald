import Foundation
import OSLog

let app = HealdApp()
do {
    try await app.run()
} catch {
    fputs("heald fatal: \(error)\n", stderr)
    Foundation.exit(1)
}
