import Foundation

public struct SSHConfig: Sendable {
    public enum Authentication: Sendable {
        case password(String)
        /// OpenSSH private key; encrypted keys are supported as allowed by Citadel.
        /// Legacy PKCS#1/PKCS#8 PEM must first be converted to OpenSSH format.
        case privateKey(pem: String, passphrase: String?)
    }

    public var host: String
    public var port: Int
    public var user: String
    public var auth: Authentication

    public init(host: String, port: Int = 22, user: String, auth: Authentication) {
        self.host = host
        self.port = port
        self.user = user
        self.auth = auth
    }
}
