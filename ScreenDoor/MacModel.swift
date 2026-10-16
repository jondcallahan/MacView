import Foundation

/// Picks a symbol for a Mac from its model identifier, such as "Macmini9,1", which Macs
/// publish over Bonjour. SF Symbols draws several generations of each Mac, so this picks the
/// one that looks like the actual machine.
enum MacModel {
    private static let miniOld = "macmini.gen2"      // the wide aluminium design, 2010 to 2023
    private static let miniNew = "macmini.gen3"      // the small M4 design, 2024 on
    private static let laptopOld = "macbook.gen1"    // no camera notch
    private static let laptopNotch = "macbook.gen2"
    private static let studio = "macstudio"
    private static let iMac = "desktopcomputer"

    static func symbolName(for identifier: String?) -> String {
        guard let identifier else { return iMac }
        return named(identifier) ?? numbered[identifier] ?? iMac
    }

    /// Until 2022, the identifier named the product, followed by a generation number.
    private static func named(_ identifier: String) -> String? {
        func major(after prefix: String) -> Int? {
            Int(identifier.dropFirst(prefix.count).prefix { $0.isNumber })
        }
        if identifier.hasPrefix("MacBookPro") {
            // The 14- and 16-inch models of 2021 (MacBookPro18) brought the notch.
            return (major(after: "MacBookPro") ?? 0) >= 18 ? laptopNotch : laptopOld
        }
        if identifier.hasPrefix("MacBook") { return laptopOld }   // MacBook and MacBookAir, up to the M1
        if identifier.hasPrefix("Macmini") { return miniOld }
        if identifier.hasPrefix("MacPro") {
            switch major(after: "MacPro") ?? 0 {
            case 7...: return "macpro.gen3"   // 2019 tower
            case 6: return "macpro.gen2"      // 2013 cylinder
            default: return "macpro.gen1"
            }
        }
        if identifier.hasPrefix("iMac") { return iMac }
        return nil
    }

    /// Since 2022, every Mac is "MacNN,N", so newer models need looking up. Unknown ones get the
    /// generic Mac until they're added here.
    private static let numbered: [String: String] = [
        "Mac13,1": studio, "Mac13,2": studio,
        "Mac14,2": laptopNotch, "Mac14,3": miniOld, "Mac14,5": laptopNotch, "Mac14,6": laptopNotch,
        "Mac14,7": laptopOld, "Mac14,8": "macpro.gen3", "Mac14,9": laptopNotch, "Mac14,10": laptopNotch,
        "Mac14,12": miniOld, "Mac14,13": studio, "Mac14,14": studio, "Mac14,15": laptopNotch,
        "Mac15,3": laptopNotch, "Mac15,4": iMac, "Mac15,5": iMac, "Mac15,6": laptopNotch,
        "Mac15,7": laptopNotch, "Mac15,8": laptopNotch, "Mac15,9": laptopNotch, "Mac15,10": laptopNotch,
        "Mac15,11": laptopNotch, "Mac15,12": laptopNotch, "Mac15,13": laptopNotch, "Mac15,14": studio,
        "Mac16,1": laptopNotch, "Mac16,2": iMac, "Mac16,3": iMac, "Mac16,5": laptopNotch,
        "Mac16,6": laptopNotch, "Mac16,7": laptopNotch, "Mac16,8": laptopNotch, "Mac16,9": studio,
        "Mac16,10": miniNew, "Mac16,11": miniNew, "Mac16,12": laptopNotch, "Mac16,13": laptopNotch,
    ]
}
