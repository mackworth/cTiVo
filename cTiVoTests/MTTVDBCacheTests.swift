//
//  MTTVDBCacheTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo

class MTTVDBCacheTests: XCTestCase {

    var tvdbCache: MTTVDBCache!

    override func setUp() {
        super.setUp()
        tvdbCache = MTTVDBCache()
    }

    func testTVDBCache() async {
        // Inject date provider that always returns known date
        let date = Date()
        let dateProvider: () -> Date = { date }
        await tvdbCache.setDateProvider(dateProvider)

        // Set the series for an episode
        await tvdbCache.setSeries("EP1", series: "338736")

        // Verify the result
        let r1 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e1 = "\(["EP1": ["series": "338736", "date": date]] as NSDictionary)"
        XCTAssertEqual(r1, e1)

        // Update the series ID
        await tvdbCache.setSeries("EP1", series: "100981")

        // Verify the result
        let r2 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e2 = "\(["EP1": ["series": "100981", "date": date]] as NSDictionary)"
        XCTAssertEqual(r2, e2)

        // Set the season
        await tvdbCache.setSeason("EP1", season: 4)

        // Verify the result
        let r3 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e3 = "\(["EP1": ["series": "100981", "season": 4, "date": date]] as NSDictionary)"
        XCTAssertEqual(r3, e3)

        // Get the tuple containing all of the properties
        let r4 = await "\(tvdbCache.getAll("EP1"))"
        let e4 = "(series: Optional(\"100981\"), slug: nil, episodeArtwork: nil, seasonArtwork: nil, seriesArtwork: nil, episode: nil, season: Optional(4), possibleIds: nil, possibleSlugs: nil, status: nil)"
        XCTAssertEqual(r4, e4)

        // Get the dictionary that would be used to populate the
        // MTTiVoShow.tvdbData property
        let r5 = await "\((tvdbCache.getDictionary("EP1") ?? [:]) as NSDictionary)"
        let e5 = "\(["series": "100981", "season": 4] as NSDictionary)"
        XCTAssertEqual(r5, e5)

        // Get the episode IDs for all episodes populated in the cache
        let r6 = await "\(tvdbCache.episodeIDs)"
        let e6 = "[\"EP1\"]"
        XCTAssertEqual(r6, e6)

        // Clear the season
        await tvdbCache.setSeason("EP1", season: nil)

        // Verify the result
        let r7 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e7 = "\(["EP1": ["series": "100981", "date": date]] as NSDictionary)"
        XCTAssertEqual(r7, e7)

        // Clear the series
        await tvdbCache.setSeries("EP1", series: nil)

        // Verify the result
        let r8 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e8 = "\(["EP1":["date": date]] as NSDictionary)"
        XCTAssertEqual(r8, e8)

        // Get the dictionary that would be used to populate the
        // MTTiVoShow.tvdbData property
        let r9 = await "\((tvdbCache.getDictionary("EP1") ?? [:]) as NSDictionary)"
        let e9 = "\([:] as NSDictionary)"
        XCTAssertEqual(r9, e9)

        // Set multiple properties at once for episode
        await tvdbCache.setAll("EP1", series: "81388", episodeArtwork: "ea", seasonArtwork: "sna", seriesArtwork: "ssa", episode: 13, season: 6, possibleIds: ["pi1", "pi2"])

        // Verify the result
        let r10 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e10 = "\(["EP1": ["series": "81388", "episodeArtwork": "ea", "seasonArtwork": "sna", "seriesArtwork": "ssa", "season": 6, "episode": 13, "possibleIds": ["pi1", "pi2"], "date": date]] as NSDictionary)"
        XCTAssertEqual(r10, e10)

        // Update multiple properties at once for episode, which removes any
        // existing properties that did not have updated values provided
        await tvdbCache.setAll("EP1", series: "81388", episode: 16)

        // Verify the result
        let r11 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e11 = "\(["EP1": ["series": "81388", "episode": 16, "date": date]] as NSDictionary)"
        XCTAssertEqual(r11, e11)

        // Reset episode
        await tvdbCache.reset("EP1")

        // Verify the result
        let r12 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e12 = "\([:] as NSDictionary)"
        XCTAssertEqual(r12, e12)
    }

    func testTVDBCacheCleanup() async {
        // Inject date provider that always returns known dates
        var date = Date()
        let initialDate = date
        let dateProvider: () -> Date = { date }
        await tvdbCache.setDateProvider(dateProvider)

        // Set just series ID for EP1 and just series artwork for EP2
        await tvdbCache.setSeries("EP1", series: "338736")
        await tvdbCache.setSeriesArtwork("EP2", seriesArtwork: "artwork")

        // Both should exist
        let r1 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e1 = "\(["EP1": ["series": "338736", "date": initialDate], "EP2":["seriesArtwork": "artwork", "date": initialDate]] as NSDictionary)"
        XCTAssertEqual(r1, e1)

        // Clean cache
        await tvdbCache.cleanCache()

        // Both should exist
        let r2 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e2 = "\(["EP1": ["series": "338736", "date": initialDate], "EP2":["seriesArtwork": "artwork", "date": initialDate]] as NSDictionary)"
        XCTAssertEqual(r2, e2)

        // Jump forward two days and clean cache
        date.addTimeInterval(2 * 24 * 60 * 60)
        await tvdbCache.cleanCache()

        // One should exist
        let r3 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e3 = "\(["EP1": ["series": "338736", "date": initialDate]] as NSDictionary)"
        XCTAssertEqual(r3, e3)

        // Jump forward another 30 days and clean cache
        date.addTimeInterval(30 * 24 * 60 * 60)
        await tvdbCache.cleanCache()

        // None should be left
        let r4 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e4 = "\([:] as NSDictionary)"
        XCTAssertEqual(r4, e4)
    }


    func testTVDBCacheDefault() async {
        // Populate defaults with known state.
        let initialState = ["EP1": ["series": "338736", "date": Date()], "EP2":["seriesArtwork": "artwork", "status": "notFound", "date": Date()]] as NSDictionary
        UserDefaults.standard.set(initialState, forKey: MTTVDBCache.userDefaultsKey)

        // Load the defaults
        await tvdbCache.loadCache()

        // Cache should match initial state of defaults
        let r1 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e1 = "\(initialState)"
        XCTAssertEqual(r1, e1)

        // Remove an episode and save cache to defaults
        await tvdbCache.reset("EP2")
        await tvdbCache.saveCache()

        // Defaults should be updated properly
        let r2 = "\(UserDefaults.standard.object(forKey: MTTVDBCache.userDefaultsKey) as? NSDictionary ?? [:])"
        let e2 = "\(["EP1": ["series": "338736", "date": Date()]] as NSDictionary)"
        XCTAssertEqual(r2, e2)
    }

    func testTVDBCacheReset() async {
        // Inject date provider that always returns known date
        let date = Date()
        let dateProvider: () -> Date = { date }
        await tvdbCache.setDateProvider(dateProvider)

        // Set multiple properties at once for episode
        await tvdbCache.setAll("EP1", series: "81388", episodeArtwork: "ea", seasonArtwork: "sna", seriesArtwork: "ssa", episode: 13, season: 6, possibleIds: ["pi1", "pi2"])

        // Verify the result
        let r1 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e1 = "\(["EP1": ["series": "81388", "episodeArtwork": "ea", "seasonArtwork": "sna", "seriesArtwork": "ssa", "season": 6, "episode": 13, "possibleIds": ["pi1", "pi2"], "date": date]] as NSDictionary)"
        XCTAssertEqual(r1, e1)

        // Reset episode
        await tvdbCache.reset()

        // Verify the result
        let r2 = await "\(tvdbCache.getDictionary() as NSDictionary)"
        let e2 = "\([:] as NSDictionary)"
        XCTAssertEqual(r2, e2)
    }
}
