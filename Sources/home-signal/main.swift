import Foundation
import HomeSignalCLI

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@main
enum HomeSignalMain {
    static func main() async {
        let code = await CLI.run(Array(CommandLine.arguments.dropFirst()))
        if code != 0 {
            exit(code)
        }
    }
}
