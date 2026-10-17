import Foundation

public enum MockFixtures {
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    public static func data(named resource: String) throws -> Data {
        let path = resource as NSString
        let ext = path.pathExtension
        let name = ext.isEmpty ? resource : path.deletingPathExtension
        guard let url = bundle.url(
            forResource: name,
            withExtension: ext.isEmpty ? "json" : ext,
            subdirectory: "MockData"
        ) else {
            throw MagpieError.decoding("找不到模拟数据文件")
        }
        return try Data(contentsOf: url)
    }
}
