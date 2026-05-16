// ABOUTME: Tiny argv parser. POC understands only --dev and --port N.
// ABOUTME: Errors exit(2); --help / -h exit(0). No test target wires App in.

import Foundation

public struct Args {
    public var dev: Bool = false
    public var port: UInt16 = 9876

    public static func parse(_ argv: [String]) -> Args {
        var args = Args()
        var i = 1
        while i < argv.count {
            switch argv[i] {
            case "--dev":
                args.dev = true
                i += 1
            case "--port":
                guard i + 1 < argv.count, let p = UInt16(argv[i + 1]) else {
                    FileHandle.standardError.write(Data("--port requires a number\n".utf8))
                    exit(2)
                }
                args.port = p
                i += 2
            case "--help", "-h":
                print("Usage: fiti [--dev] [--port N]")
                exit(0)
            default:
                FileHandle.standardError.write(Data("unknown arg: \(argv[i])\n".utf8))
                exit(2)
            }
        }
        return args
    }
}
