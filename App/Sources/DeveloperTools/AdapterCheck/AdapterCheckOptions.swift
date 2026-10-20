#if DEBUG
/// The tool's arguments after `--adapter-check`: the command name and `--option value` pairs.
struct AdapterCheckOptions {
    let commandName: String?
    private var values: [String: String] = [:]

    /// - Throws: ``AdapterCheckArgumentError`` for an option without a value or given twice.
    init(_ arguments: ArraySlice<String>) throws(AdapterCheckArgumentError) {
        var remaining = arguments
        var commandName: String?
        while let argument = remaining.popFirst() {
            if argument.hasPrefix("--") {
                guard let value = remaining.popFirst(), !value.hasPrefix("--") else {
                    throw AdapterCheckArgumentError.missingValue(argument)
                }
                guard values.updateValue(value, forKey: argument) == nil else {
                    throw AdapterCheckArgumentError.duplicateOption(argument)
                }
            } else if argument.hasPrefix("-") {
                // A system argument such as -AppleLanguages "(ru)": not the tool's, skipped with its value.
                remaining = remaining.dropFirst()
            } else if commandName == nil {
                commandName = argument
            } else {
                throw AdapterCheckArgumentError.unexpectedArgument(argument)
            }
        }
        self.commandName = commandName
    }

    /// Removes and returns the option's value.
    mutating func take(_ option: String) throws(AdapterCheckArgumentError) -> String? {
        values.removeValue(forKey: option)
    }

    /// Removes and returns the option's value as a whole number of at least `minimum`.
    mutating func takeCount(_ option: String, minimum: Int = 1) throws(AdapterCheckArgumentError) -> Int? {
        guard let text = try take(option) else {
            return nil
        }
        guard let count = Int(text), count >= minimum else {
            throw AdapterCheckArgumentError.invalidValue(option: option, value: text)
        }
        return count
    }

    /// - Throws: ``AdapterCheckArgumentError/unknownOption(_:)`` for any option no command consumed.
    func requireNothingLeft() throws(AdapterCheckArgumentError) {
        if let option = values.keys.sorted().first {
            throw AdapterCheckArgumentError.unknownOption(option)
        }
    }
}

/// A command line the tool cannot run.
enum AdapterCheckArgumentError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case unknownOption(String)
    case missingValue(String)
    case duplicateOption(String)
    case unexpectedArgument(String)
    case invalidValue(option: String, value: String)

    var description: String {
        switch self {
        case .missingCommand: "no command after --adapter-check"
        case .unknownCommand(let name): "unknown command \(name)"
        case .unknownOption(let option): "unknown option \(option) for this command"
        case .missingValue(let option): "missing value for \(option)"
        case .duplicateOption(let option): "\(option) given twice"
        case .unexpectedArgument(let argument): "unexpected argument \(argument)"
        case .invalidValue(let option, let value): "invalid value \(value) for \(option)"
        }
    }
}
#endif
