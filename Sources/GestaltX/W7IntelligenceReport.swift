// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A narrow, on-device summary of user-selected Apple Intelligence Report JSON.
/// This is not signature verification and does not retain prompts or other fields.
struct W7IntelligenceReport: Equatable, Sendable {
    let privateCloudComputeRequests: Int?
    let modelRequests: Int?

    enum Failure: Error, Equatable {
        case unreadable
        case tooLarge
        case malformedJSON
        case unrecognized
        case invalidRequestList
    }

    static let maximumBytes = 4 * 1_024 * 1_024

    static func read(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var buffer = Data()
            while buffer.count <= maximumBytes {
                let count = min(65_536, maximumBytes + 1 - buffer.count)
                guard let next = try handle.read(upToCount: count), !next.isEmpty else {
                    return try decode(buffer)
                }
                buffer.append(next)
            }
            throw Failure.tooLarge
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unreadable
        }
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Failure.malformedJSON
        }
        guard let root = object as? [String: Any] else { throw Failure.unrecognized }
        let pcc = try requestCount("privateCloudComputeRequests", in: root)
        let models = try requestCount("modelRequests", in: root)
        guard pcc != nil || models != nil else { throw Failure.unrecognized }
        return Self(privateCloudComputeRequests: pcc, modelRequests: models)
    }

    private static func requestCount(_ key: String, in root: [String: Any]) throws -> Int? {
        guard let value = root[key] else { return nil }
        guard let requests = value as? [[String: Any]] else { throw Failure.invalidRequestList }
        return requests.count
    }
}
