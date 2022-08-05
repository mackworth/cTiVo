//
//  MTTVDBMovieServiceTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo

class MTTVDBMovieServiceTests: XCTestCase {

    var service: MTTVDBMovieService!

    override func setUp() {
        super.setUp()
        service = MTTVDBMovieServiceV3()
    }

    func testStartup() async {
        let result0 = await service.queryMovie(name: "Craig")
        print(result0 as Any)
    }
}
