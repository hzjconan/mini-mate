import Foundation
import zlib

public enum GzipError: Error, Sendable, Equatable {
    case invalidData
    case sizeLimitExceeded(Int)
    case zlibFailed(Int32)
}

/// RFC 1952 GZIP compression/decompression backed by Apple system `zlib` (zero third-party dependencies).
public enum GzipCodec {
    public static let defaultMaxOutputBytes = 16 * 1024 * 1024

    public static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16, // RFC 1952 GZIP header + trailer
            MAX_MEM_LEVEL,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GzipError.zlibFailed(initStatus)
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16_384
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        let status: Int32 = data.withUnsafeBytes { rawInput in
            if let base = rawInput.bindMemory(to: Bytef.self).baseAddress {
                stream.next_in = UnsafeMutablePointer(mutating: base)
            }
            stream.avail_in = uInt(data.count)

            var deflateStatus: Int32 = Z_OK
            repeat {
                deflateStatus = buffer.withUnsafeMutableBytes { rawOut in
                    stream.next_out = rawOut.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return deflate(&stream, Z_FINISH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
            } while deflateStatus == Z_OK
            return deflateStatus
        }

        guard status == Z_STREAM_END else {
            throw GzipError.zlibFailed(status)
        }
        return output
    }

    public static func decompress(
        _ data: Data,
        maxOutputBytes: Int = defaultMaxOutputBytes
    ) throws -> Data {
        guard !data.isEmpty else {
            throw GzipError.invalidData
        }
        guard maxOutputBytes >= 0 else {
            throw GzipError.sizeLimitExceeded(maxOutputBytes)
        }

        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            MAX_WBITS + 32, // Auto-detect RFC 1952 GZIP or zlib header
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw GzipError.zlibFailed(initStatus)
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16_384
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var exceededLimit = false

        let status: Int32 = data.withUnsafeBytes { rawInput in
            if let base = rawInput.bindMemory(to: Bytef.self).baseAddress {
                stream.next_in = UnsafeMutablePointer(mutating: base)
            }
            stream.avail_in = uInt(data.count)

            var inflateStatus: Int32 = Z_OK
            repeat {
                inflateStatus = buffer.withUnsafeMutableBytes { rawOut in
                    stream.next_out = rawOut.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    if output.count + produced > maxOutputBytes {
                        exceededLimit = true
                        return Z_BUF_ERROR
                    }
                    output.append(buffer, count: produced)
                }
            } while inflateStatus == Z_OK
            return inflateStatus
        }

        if exceededLimit {
            throw GzipError.sizeLimitExceeded(maxOutputBytes)
        }
        guard status == Z_STREAM_END else {
            if status == Z_DATA_ERROR {
                throw GzipError.invalidData
            }
            throw GzipError.zlibFailed(status)
        }
        return output
    }
}
