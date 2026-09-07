import Carbon
import Darwin
import Foundation

@main
struct LinnetInputSourceRegistrationInspector {
  static func main() {
    let arguments = CommandLine.arguments
    guard (2...3).contains(arguments.count),
      arguments.dropFirst().allSatisfy({ !$0.isEmpty && !$0.contains("\n") })
    else {
      FileHandle.standardError.write(
        Data("usage: input-source-registration-inspector BUNDLE_IDENTIFIER [MODE_IDENTIFIER]\n".utf8))
      exit(EX_USAGE)
    }
    if arguments.count == 3 {
      print(LinnetInputSourceRegistration.state(
        identifier: arguments[2], bundleIdentifier: arguments[1],
        type: kTISTypeKeyboardInputMode as String).wireValue)
    } else {
      print(LinnetInputSourceRegistration.state(identifier: arguments[1]).wireValue)
    }
  }
}
