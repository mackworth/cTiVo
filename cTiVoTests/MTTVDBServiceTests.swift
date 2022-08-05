//
//  MTTVDBServiceTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo

class MTTVDBServiceTests: XCTestCase {
    
    var service: MTTVDBService!
        
    override func setUp() {
        super.setUp()
        service = MTTVDBServiceV4()
    }
    
    func testStartup() async {
        let result0 = await service.querySeries(name: "Craig")
        print(result0 as Any)
        let result1 = await service.querySeries(name: "Craig of the Creek")
        print(result1 as Any)
        let result2 = await service.queryEpisodes(seriesID: "338736")
        print(result2 as Any)
        let result3 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06")
        print(result3 as Any)
        let result4 = await service.queryEpisodes(seriesID: "338736", pageNumber: 0)
        print(result4 as Any)
        let result5 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 0)
        print(result5 as Any)
        let result6 = await service.querySeriesArtwork(seriesID: "338736")
        print(result6 as Any)
        let result7 = await service.querySeriesArtwork(seriesID: "81388")
        print(result7 as Any)
        let result8 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        print(result8 as Any)
        let result9 = await service.querySeasonArtwork(seriesID: "100981", season: 13)
        print(result9 as Any)
//        let showTitle = "24: The Lost Weekend"
//        let seriesTitle = showTitle.components(separatedBy: ":")[0]
//        let result8 = await service.querySeries(name: showTitle)
//        print(result8 as Any)
//        let result9 = await service.querySeries(name: seriesTitle)
//        print(result9 as Any)
    }
}
