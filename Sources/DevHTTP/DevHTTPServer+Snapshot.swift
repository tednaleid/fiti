// ABOUTME: DevHTTPServer extension — image-capture routes: GET /snapshot.png (canvas)
// ABOUTME: and GET /toolbar.png (toolbar chrome). Debug builds only.

#if DEBUG
import Foundation

extension DevHTTPServer {
    func installSnapshotRoute() {
        router.add("GET", "/snapshot.png") { [weak self] _, _ in
            guard let data = self?.surface.snapshotPNG() else {
                return HTTPResponse(status: 500, reason: "Internal Server Error",
                                    body: Data("snapshot unavailable".utf8))
            }
            return .png(data)
        }

        router.add("GET", "/toolbar.png") { [weak self] _, _ in
            guard let data = self?.surface.toolbarPNG() else {
                return HTTPResponse(status: 409, reason: "Conflict",
                                    body: Data("toolbar unavailable".utf8))
            }
            return .png(data)
        }
    }
}
#endif
