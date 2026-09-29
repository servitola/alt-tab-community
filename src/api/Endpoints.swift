import Foundation

enum Endpoints {
    // Upstream's Domain/ApiDomain point at alt-tab.app, its commercial site and feedback backend; this fork's
    // home, support and feedback are its GitHub repository.
    static let website = "https://github.com/servitola/alt-tab-community"
    // Served from this repository, so users are only offered builds this fork ships and signs with its own
    // EdDSA key (SUPublicEDKey), never upstream (lwouis/alt-tab-macos) releases published on alt-tab.app.
    static let appcastUrl = "https://raw.githubusercontent.com/servitola/alt-tab-community/master/appcast.xml"
    static let supportUrl = website
    static let newIssueUrl = "\(website)/issues/new"
}
