import Foundation

enum Endpoints {
    static let domain = Bundle.main.object(forInfoDictionaryKey: "Domain") as! String
    static let apiDomain = Bundle.main.object(forInfoDictionaryKey: "ApiDomain") as! String
    static let website = "https://\(domain)"
    // Served from this repository, so users are only offered builds this fork ships and signs with its own
    // EdDSA key (SUPublicEDKey), never upstream (lwouis/alt-tab-macos) releases published on alt-tab.app.
    static let appcastUrl = "https://raw.githubusercontent.com/servitola/alt-tab-community/master/appcast.xml"
    static let supportUrl = "\(website)/support"
    static let feedbackUrl = "https://\(apiDomain)/v1/feedback"
}
