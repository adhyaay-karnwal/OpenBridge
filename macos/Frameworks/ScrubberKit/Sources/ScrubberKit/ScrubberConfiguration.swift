//
//  ScrubberConfiguration.swift
//  ScrubberKit
//
//  Created by 秋星桥 on 2/22/25.
//

import Foundation
import WebKit

public enum ScrubberConfiguration {
    public static var disabledEngines: Set<ScrubEngine> = []

    public static let storageIdentifier: UUID = .init(uuidString: "A4FA9205-DE47-4667-AC27-A9E10E750DEC")!
    public static let desktopChromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"

    public static func setup() {
        ScrubWorker.compileAccessRules()
    }
}
