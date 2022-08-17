//
//  MTTVDBLogger.swift
//  cTiVo
//
//  Created by Steve Schmadeke on 8/15/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import Foundation
import CocoaLumberjack

@objc(MTTVDB4)
public class MTTVDBLogger: NSObject {
    public static var logLevel = DDLogLevel.verbose;

    @objc public static var ddLogLevel: DDLogLevel {
        get { logLevel }
        @objc(ddSetLogLevel:) set { logLevel = newValue }
    }
    static func DDLogReport(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogError(msg, level: Self.logLevel, context: 1, file: file, function: function, line: line)
    }
    static func DDLogMajor(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogWarn(msg, level: Self.logLevel, context: 1, file: file, function: function, line: line)
    }
    static func DDLogDetail(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        DDLogInfo(msg, level: Self.logLevel, context: 1, file: file, function: function, line: line)
    }
    static func DDLogVerbose(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) {
        CocoaLumberjack.DDLogDebug(msg, level: Self.logLevel, context: 1, file: file, function: function, line: line)
    }
}
