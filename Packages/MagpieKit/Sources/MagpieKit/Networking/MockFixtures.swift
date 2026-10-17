import Foundation

public enum MockFixtures {
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    public static func data(named name: String) throws -> Data {
        let name = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "MockData") else {
            throw MagpieError.decoding("找不到模拟数据文件")
        }
        return try Data(contentsOf: url)
    }
}
