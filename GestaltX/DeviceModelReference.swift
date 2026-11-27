// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

enum DeviceModelReference {
    static let identifier: String = {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var info = utsname()
        guard uname(&info) == 0 else { return "" }
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
    }()

    static let name: String? = {
        guard let url = Bundle.main.url(forResource: "DeviceModels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return names[identifier]
    }()
}
