// ABOUTME: Tests for the Args argv parser. Lives in fiti-integration
// ABOUTME: because Sources/App isn't visible to fiti-unit.

import Testing

@Suite("Args")
struct ArgsTests {
    @Test("defaults: dev=false, port=9876")
    func defaults() {
        let args = Args.parse(["fiti"])
        #expect(args.dev == false)
        #expect(args.port == 9876)
    }

    @Test("--dev sets dev=true")
    func dev() {
        let args = Args.parse(["fiti", "--dev"])
        #expect(args.dev == true)
        #expect(args.port == 9876)
    }

    @Test("--port N sets the port")
    func port() {
        let args = Args.parse(["fiti", "--dev", "--port", "8080"])
        #expect(args.dev == true)
        #expect(args.port == 8080)
    }
}
