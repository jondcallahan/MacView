import Foundation

/// Picks a symbol for a Mac from its model identifier, such as "Macmini9,1", which Macs
/// publish over Bonjour.
enum MacModel {
    enum Kind {
        case laptop, mini, studio, pro, iMac
    }

    static func symbolName(for identifier: String?) -> String {
        switch identifier.flatMap(kind) {
        case .laptop: "laptopcomputer"
        case .mini: "macmini"
        case .studio: "macstudio"
        case .pro: "macpro.gen3"
        case .iMac, nil: "desktopcomputer"
        }
    }

    static func kind(of identifier: String) -> Kind? {
        // Until 2022, the identifier named the product.
        let named: [(String, Kind)] = [("MacBook", .laptop), ("Macmini", .mini), ("MacPro", .pro), ("iMac", .iMac)]
        if let match = named.first(where: { identifier.hasPrefix($0.0) }) { return match.1 }
        // Since then, every Mac is "MacNN,N", so newer models need looking up.
        return numbered[identifier]
    }

    private static let numbered: [String: Kind] = [
        "Mac13,1": .studio, "Mac13,2": .studio,
        "Mac14,2": .laptop, "Mac14,3": .mini, "Mac14,5": .laptop, "Mac14,6": .laptop, "Mac14,7": .laptop,
        "Mac14,8": .pro, "Mac14,9": .laptop, "Mac14,10": .laptop, "Mac14,12": .mini, "Mac14,13": .studio,
        "Mac14,14": .studio, "Mac14,15": .laptop,
        "Mac15,3": .laptop, "Mac15,4": .iMac, "Mac15,5": .iMac, "Mac15,6": .laptop, "Mac15,7": .laptop,
        "Mac15,8": .laptop, "Mac15,9": .laptop, "Mac15,10": .laptop, "Mac15,11": .laptop, "Mac15,12": .laptop,
        "Mac15,13": .laptop, "Mac15,14": .studio,
        "Mac16,1": .laptop, "Mac16,2": .iMac, "Mac16,3": .iMac, "Mac16,5": .laptop, "Mac16,6": .laptop,
        "Mac16,7": .laptop, "Mac16,8": .laptop, "Mac16,9": .studio, "Mac16,10": .mini, "Mac16,11": .mini,
        "Mac16,12": .laptop, "Mac16,13": .laptop,
    ]
}
