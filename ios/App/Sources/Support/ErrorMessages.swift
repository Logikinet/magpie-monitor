import Foundation
import MagpieKit

enum ErrorMessages {
    static func chinese(for error: Error) -> String {
        if let error = error as? MagpieError {
            switch error {
            case .unauthorized, .forbidden: return String(localized: "认证失败，请检查连接密钥和局域网访问设置。")
            case .sshAuthFailed: return String(localized: "SSH 认证失败，请检查用户名和凭据。")
            case .sshHostKeyChanged: return String(localized: "SSH 主机指纹已改变，请核实服务器身份后重置指纹。")
            case .cancelled: return String(localized: "操作已取消。")
            default: return String(localized: "连接或读取失败，请检查配置后重试。")
            }
        }
        if error is CancellationError { return String(localized: "操作已取消。") }
        // Security framework descriptions are intentionally omitted; they can expose item details.
        return String(localized: "操作失败，请检查配置和连接后重试。")
    }
}
