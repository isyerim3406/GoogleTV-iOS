import Foundation
import Network
import Security
import BigInt

private let CNXN: UInt32 = 0x4e584e43
private let AUTH: UInt32 = 0x48545541
private let OPEN: UInt32 = 0x4e45504f
private let OKAY: UInt32 = 0x59414b4f
private let WRTE: UInt32 = 0x45545257
private let CLSE: UInt32 = 0x45534c43

private func le(_ x: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: x), UInt8(truncatingIfNeeded: x >> 8),
     UInt8(truncatingIfNeeded: x >> 16), UInt8(truncatingIfNeeded: x >> 24)]
}
private func word(_ b: [UInt8], _ p: Int) -> UInt32 {
    UInt32(b[p]) | UInt32(b[p+1]) << 8 | UInt32(b[p+2]) << 16 | UInt32(b[p+3]) << 24
}
private struct Packet {
    let command: UInt32
    let arg0: UInt32
    let arg1: UInt32
    let bytes: [UInt8]
    var encoded: Data {
        let sum = bytes.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        return Data(le(command) + le(arg0) + le(arg1) + le(UInt32(bytes.count)) +
                    le(sum) + le(command ^ 0xffffffff) + bytes)
    }
}
enum TVError: LocalizedError {
    case timeout, disconnected, key, protocolError
    var errorDescription: String? {
        switch self {
        case .timeout: return "TV yanıt vermedi. IP/port veya ADB iznini kontrol edin."
        case .disconnected: return "Bağlantı kesildi."
        case .key: return "RSA anahtarı oluşturulamadı."
        case .protocolError: return "ADB iletişim hatası."
        }
    }
}
private final class TVKey {
    let key: SecKey
    init() throws {
        let tag = Data("com.isyerim3406.googletv.adb".utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]
        var ref: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
           let saved = ref {
            key = saved as! SecKey
        } else {
            let attrs: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 2048,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: tag
                ]
            ]
            var error: Unmanaged<CFError>?
            guard let newKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else { throw TVError.key }
            key = newKey
        }
    }
    func signature(_ token: [UInt8]) throws -> [UInt8] {
        var err: Unmanaged<CFError>?
        guard let data = SecKeyCreateSignature(key, .rsaSignatureDigestPKCS1v15SHA1,
                                               Data(token) as CFData, &err) else { throw TVError.key }
        return [UInt8](data as Data)
    }
    func adbPublicKey() throws -> [UInt8] {
        guard let pub = SecKeyCopyPublicKey(key) else { throw TVError.key }
        var err: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(pub, &err) as Data? else { throw TVError.key }
        let der = [UInt8](data)
        var i = 0
        func length() throws -> Int {
            guard i < der.count else { throw TVError.key }
            let first = Int(der[i]); i += 1
            if first < 128 { return first }
            let count = first & 127
            guard count > 0 && count <= 4 && i + count <= der.count else { throw TVError.key }
            var n = 0
            for _ in 0..<count { n = (n << 8) | Int(der[i]); i += 1 }
            return n
        }
        func integer() throws -> [UInt8] {
            guard i < der.count && der[i] == 2 else { throw TVError.key }
            i += 1
            let n = try length()
            guard i + n <= der.count else { throw TVError.key }
            let v = Array(der[i..<(i+n)]); i += n
            return v.first == 0 ? Array(v.dropFirst()) : v
        }
        guard der.first == 0x30 else { throw TVError.key }
        i = 1; _ = try length()
        let modulus = try integer()
        let exponent = try integer().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard modulus.count == 256 && exponent == 65537 else { throw TVError.key }
        let n = BigUInt(Data(modulus))
        let low = UInt32(truncatingIfNeeded: n)
        var inv: UInt32 = 1
        for _ in 0..<5 { inv = inv &* (2 &- low &* inv) }
        let r2 = (BigUInt(1) << 4096) % n
        func little256(_ b: BigUInt) -> [UInt8] {
            let a = Array(b.serialize().reversed())
            return a + Array(repeating: 0, count: 256 - a.count)
        }
        let raw = le(64) + le(0 &- inv) + little256(n) + little256(r2) + le(exponent)
        return Array((Data(raw).base64EncodedString() + " googletv-ios@iphone\0").utf8)
    }
}
final class ADBClient {
    private let queue = DispatchQueue(label: "tv.ios.adb.network")
    private let lock = NSLock()
    private var pending: [Packet] = []
    private var receiveBuffer: [UInt8] = []
    private var failed = false
    private var conn: NWConnection?
    private let auth: TVKey
    private var nextID: UInt32 = 1
    private var maxPacket: Int = 4096

    init() throws { auth = try TVKey() }

    func close() {
        lock.lock(); failed = true; lock.unlock()
        conn?.cancel()
    }
    private func write(_ cmd: UInt32, _ a: UInt32 = 0, _ b: UInt32 = 0, _ bytes: [UInt8] = []) {
        conn?.send(content: Packet(command: cmd, arg0: a, arg1: b, bytes: bytes).encoded,
                   completion: .contentProcessed { _ in })
    }
    private func readLoop() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, err in
            guard let self else { return }
            self.lock.lock()
            if let data { self.receiveBuffer += data }
            while self.receiveBuffer.count >= 24 {
                let size = Int(word(self.receiveBuffer, 12))
                if size > 8_388_608 { self.failed = true; break }
                if self.receiveBuffer.count < 24 + size { break }
                let b = self.receiveBuffer
                let payload = Array(b[24..<(24+size)])
                let cmd = word(b, 0)
                let checksum = payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }
                if word(b, 20) == (cmd ^ 0xffffffff) && word(b, 16) == checksum {
                    self.pending.append(Packet(command: cmd, arg0: word(b, 4), arg1: word(b, 8), bytes: payload))
                }
                self.receiveBuffer.removeFirst(24+size)
            }
            if complete || err != nil { self.failed = true }
            let shouldContinue = !self.failed
            self.lock.unlock()
            if shouldContinue { self.readLoop() }
        }
    }
    private func receive(_ seconds: TimeInterval = 20) throws -> Packet {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            lock.lock()
            let p = pending.isEmpty ? nil : pending.removeFirst()
            let isFailed = failed
            lock.unlock()
            if let p { return p }
            if isFailed { throw TVError.disconnected }
            Thread.sleep(forTimeInterval: 0.025)
        }
        throw TVError.timeout
    }
    func connect(host: String, port: UInt16 = 5555) throws {
        guard let p = NWEndpoint.Port(rawValue: port) else { throw TVError.disconnected }
        lock.lock(); failed = false; pending.removeAll(); receiveBuffer.removeAll(); lock.unlock()
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.lock.lock(); self?.failed = true; self?.lock.unlock()
            }
        }
        c.start(queue: queue)
        readLoop()
        write(CNXN, 0x01000000, 4096, Array("host::\0".utf8))
        var authorizations = 0
        while authorizations < 6 {
            let packet = try receive()
            if packet.command == CNXN { maxPacket = max(1024, min(Int(packet.arg1), 262144)); return }
            if packet.command == AUTH && packet.arg0 == 1 {
                authorizations += 1
                if authorizations == 1 {
                    write(AUTH, 2, 0, try auth.signature(packet.bytes))
                } else {
                    write(AUTH, 3, 0, try auth.adbPublicKey())
                }
            }
        }
        throw TVError.protocolError
    }
    // ADB sync protocol: upload local file to the TV without an Android phone.
    private func syncWrite(_ id: UInt32, _ remote: UInt32, _ data: [UInt8]) throws {
        var offset = 0
        while offset < data.count {
            let count = min(maxPacket, data.count - offset)
            write(WRTE, id, remote, Array(data[offset..<(offset + count)]))
            let ack = try receive(30)
            guard ack.command == OKAY && ack.arg1 == id else { throw TVError.protocolError }
            offset += count
        }
    }
    private func syncFrame(_ name: String, _ payload: [UInt8]) -> [UInt8] {
        Array(name.utf8) + le(UInt32(payload.count)) + payload
    }
    func pushFile(_ url: URL, remotePath: String) throws -> Int64 {
        guard remotePath.hasPrefix("/data/local/tmp/"),
              remotePath.range(of: "^/data/local/tmp/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else {
            throw TVError.protocolError
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let id = nextID; nextID += 1
        write(OPEN, id, 0, Array("sync:\0".utf8))
        let start = try receive()
        guard start.command == OKAY && start.arg1 == id else { throw TVError.protocolError }
        let remote = start.arg0
        try syncWrite(id, remote, syncFrame("SEND", Array((remotePath + ",33206").utf8)))
        var total: Int64 = 0
        while true {
            let chunk = try file.read(upToCount: 32768) ?? Data()
            if chunk.isEmpty { break }
            try syncWrite(id, remote, syncFrame("DATA", Array(chunk)))
            total += Int64(chunk.count)
        }
        // DONE carries the modification timestamp, rather than a payload length.
        let done = Array("DONE".utf8) + le(UInt32(Date().timeIntervalSince1970))
        try syncWrite(id, remote, done)
        var response = [UInt8]()
        while response.count < 8 {
            let p = try receive(60)
            if p.command == WRTE && p.arg1 == id {
                response += p.bytes
                write(OKAY, id, p.arg0)
            } else if p.command == CLSE { throw TVError.protocolError }
        }
        let code = String(decoding: response.prefix(4), as: UTF8.self)
        if code != "OKAY" {
            throw NSError(domain: "ADB Sync", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Dosya aktarımı başarısız: " + String(decoding: response, as: UTF8.self)
            ])
        }
        write(CLSE, id, remote)
        return total
    }

    func shell(_ command: String) throws -> String {
        let id = nextID; nextID += 1
        write(OPEN, id, 0, Array("shell:\(command)\0".utf8))
        var result = [UInt8]()
        var remote: UInt32 = 0
        while true {
            let p = try receive(25)
            if p.arg1 != id { continue }
            if p.command == OKAY { remote = p.arg0 }
            if p.command == WRTE {
                result += p.bytes
                guard result.count < 4_000_000 else { throw TVError.protocolError }
                write(OKAY, id, p.arg0)
            }
            if p.command == CLSE {
                if remote != 0 { write(CLSE, id, p.arg0) }
                return String(decoding: result, as: UTF8.self)
            }
        }
    }
}
