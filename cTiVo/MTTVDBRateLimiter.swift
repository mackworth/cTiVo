//
// Created by Steve Schmadeke on 7/31/22.
// Copyright (c) 2022 cTiVo. All rights reserved.
//

import Foundation

// TODO:- replace with real logging interface
func DDLogReport(_ args: Any...) {
//    print(args)
}
func DDLogMajor(_ args: Any...) {
//    print(args)
}
func DDLogDetail(_ args: Any...) {
//    print(args)
}
func DDLogAlways(_ args: Any...) {
//    print(args)
}
func DDLogVerbose(_ args: Any...) {
//    print(args)
}

public actor MTTVDBRateLimiter {
    let limit: Int
    let limitInterval: TimeInterval

    private var calls = 0
    private var end = Date()

    init(limit: Int = 38, limitInterval: TimeInterval = 11) {
        self.limit = limit
        self.limitInterval = limitInterval
    }

    func wait(_ show: String = "") async -> Void {
        calls += 1
        DDLogDetail("TheMovieDB \(calls), Entering \(show) at \(end)")
        let delayInterval = end.timeIntervalSinceNow
        if delayInterval < 0 {
            // Past the end of the limit interval without triggering the
            // call limit, reset the count and the end of the interval.
            calls = 1
            end = Date(timeIntervalSinceNow: limitInterval)
        } else if calls > limit {
            DDLogDetail("For Show: \(show), theMovieDB sleeping \(delayInterval)")
            let delay = UInt64(delayInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            DDLogDetail("For Show: \(show), theMovieDB awaking")
            calls = 1
            end = Date(timeIntervalSinceNow: limitInterval)
        }
        DDLogDetail("TheMovieDB \(calls), Exiting \(show) at \(end)")
    }
}
