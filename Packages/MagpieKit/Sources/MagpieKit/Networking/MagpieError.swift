import Foundation

public enum MagpieError: Error, Equatable, Sendable {
    case badStatus(Int), unauthorized, forbidden, network(String), timeout, cancelled
    case decoding(String), sshHostKeyChanged, sshAuthFailed, sshFailed(String)

    /// Returns nil for successful HTTP responses.
    public static func classify(status: Int) -> MagpieError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        default: return .badStatus(status)
        }
    }

    public static func map(_ error: Error) -> MagpieError {
        if let error = error as? MagpieError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return .timeout
            case .cancelled: return .cancelled
            default: return .network(error.localizedDescription)
            }
        }
        return .network(error.localizedDescription)
    }

    public var localizedChinese: String {
        switch self {
        case .badStatus(let status): return "服务器返回错误（\(status)），请稍后重试。"
        case .unauthorized: return "认证失败，请检查 gateway key；若为 Web 认证，runtime key 失效，请重新从 web GUI 复制，建议固定 MAGPIE_WEB_KEY。"
        case .forbidden: return "请在 magpie 设置中开启 \"Share on local network\" 并检查 gateway key。"
        case .network: return "网络连接失败，请检查网络和服务器地址。"
        case .timeout: return "请求超时，请稍后重试。"
        case .cancelled: return "请求已取消。"
        case .decoding: return "无法解析服务器数据，请检查服务端版本。"
        case .sshHostKeyChanged: return "主机指纹变化，可能存在中间人攻击或主机重装，请确认后重置指纹并重连。"
        case .sshAuthFailed: return "SSH 认证失败，请检查私钥、密码与主机用户。"
        case .sshFailed: return "SSH 连接或命令执行失败，请检查主机状态后重试。"
        }
    }
}
