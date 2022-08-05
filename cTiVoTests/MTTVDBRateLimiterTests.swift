//
//  MTTVDBRateLimiterTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo

class MTTVDBRateLimiterTests: XCTestCase {

    var rateLimiter: MTTVDBRateLimiter!
        
    override func setUp() {
        super.setUp()
        rateLimiter = MTTVDBRateLimiter(limit: 38, limitInterval: 11)
    }

    // This test is disabled since it is both a long-running test and
    // the class isn't currently in use.
    func testTwoPlusIntervals() async {
        let start = Date()
        for _ in 1...100 {
            await rateLimiter.wait("test")
        }
        // Should take a bit over 22 seconds
        XCTAssertEqual(start.timeIntervalSinceNow, -22, accuracy: 3)
    }
}
