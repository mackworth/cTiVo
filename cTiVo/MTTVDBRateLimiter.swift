//
// Created by Steve Schmadeke on 7/31/22.
// Copyright (c) 2022 cTiVo. All rights reserved.
//

import Foundation

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
        MTTVDBLogger.DDLogDetail("TheMovieDB \(calls), Entering \(show) at \(end)")
        let delayInterval = end.timeIntervalSinceNow
        if delayInterval < 0 {
            // Past the end of the limit interval without triggering the
            // call limit, reset the count and the end of the interval.
            calls = 1
            end = Date(timeIntervalSinceNow: limitInterval)
        } else if calls > limit {
            MTTVDBLogger.DDLogDetail("For Show: \(show), theMovieDB sleeping \(delayInterval)")
            let delay = UInt64(delayInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            MTTVDBLogger.DDLogDetail("For Show: \(show), theMovieDB awaking")
            calls = 1
            end = Date(timeIntervalSinceNow: limitInterval)
        }
        MTTVDBLogger.DDLogDetail("TheMovieDB \(calls), Exiting \(show) at \(end)")
    }
}
