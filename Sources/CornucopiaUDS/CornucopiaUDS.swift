//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public enum UDS {

    static var bundle: Bundle = .init(for: GenericSerialAdapter.self)

    static func localized(forKey key: String) -> String { NSLocalizedString(key, tableName: nil, bundle: Self.bundle, value: "", comment: "") }
}

internal extension String {

    var uds_localized: String { NSLocalizedString(self, bundle: Bundle.module, comment: "") }
}
