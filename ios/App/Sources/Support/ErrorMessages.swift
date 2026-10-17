import Foundation
import MagpieKit

enum ErrorMessages {
    static func chinese(for error: Error) -> String {
        if let error = error as? MagpieError { return error.localizedChinese }
        if error is CancellationError { return "操作已取消。" }
        // Security framework descriptions are intentionally omitted; they can expose item details.
        return "操作失败，请检查配置和连接后重试。"
    }
}
