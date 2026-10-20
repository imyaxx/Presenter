// Compares two wallpaper stores (Index.plist) for the adapter check protocol (docs/13-adapter-check.md).
//
// Usage: swift Scripts/compare-wallpaper-store.swift <expected Index.plist> <actual Index.plist>
//
// Independent of the app: decodes both with PropertyListSerialization, decodes nested binary property lists
// recursively, ignores every `LastUse` entry and nothing else, and prints the path of each difference.
// Exits 0 when the stores are equal, 1 when they differ, 2 on a read error.
import Foundation

let volatileKey = "LastUse"

func normalized(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]:
        var result: [String: Any] = [:]
        for (key, item) in dictionary where key != volatileKey {
            result[key] = normalized(item)
        }
        return result
    case let array as [Any]:
        return array.map(normalized)
    case let data as Data:
        guard data.starts(with: Data("bplist".utf8)),
            let nested = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else {
            return data
        }
        return ["(nested)": normalized(nested)]
    default:
        return value
    }
}

func differences(_ expected: Any, _ actual: Any, at path: String) -> [String] {
    switch (expected, actual) {
    case let (expected as [String: Any], actual as [String: Any]):
        return Set(expected.keys).union(actual.keys).sorted().flatMap { key -> [String] in
            let child = "\(path)/\(key.isEmpty ? "\"\"" : key)"
            switch (expected[key], actual[key]) {
            case let (left?, right?): return differences(left, right, at: child)
            case (nil, _): return ["\(child): only in actual"]
            case (_, nil): return ["\(child): only in expected"]
            }
        }
    case let (expected as [Any], actual as [Any]):
        guard expected.count == actual.count else {
            return ["\(path): \(expected.count) items expected, \(actual.count) actual"]
        }
        return zip(expected, actual).enumerated().flatMap { differences($1.0, $1.1, at: "\(path)[\($0)]") }
    default:
        return (expected as AnyObject).isEqual(actual) ? [] : ["\(path): values differ"]
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: compare-wallpaper-store.swift <expected> <actual>\n".utf8))
    exit(2)
}
do {
    let stores = try arguments[1...2].map { path in
        normalized(try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(filePath: path)), format: nil))
    }
    let found = differences(stores[0], stores[1], at: "")
    for line in found {
        print("wallpaper store differs at \(line)")
    }
    exit(found.isEmpty ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(2)
}
