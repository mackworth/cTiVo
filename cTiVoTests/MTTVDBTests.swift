//
//  MTTVDBTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo

class MTTiVoShowStub: MTTiVoShowReadOnly {
    var episodeID = "episodeID"
    var showTitle = "showTitle"
    var seriesTitle = "seriesTitle"
    var isEpisodicShow = true
    var episodeTitle = "episodeTitle"
    var manualSeasonInfo = false
    var season: Int = 9
    var episode: Int = 99
    var originalAirDateNoTime = "originalAirDateNoTime"
    var movieYear = "movieYear"
    var tvdbData: NSDictionary? = nil
}

class MTTVDBServiceMock: MTTVDBService {

    struct Series: MTTVDBSeries {
        var id = "seriesID"
        var slug = "seriesSlug"
        var name: String? = "seriesTitle"
        var image: String? = "seriesImage"
    }

    struct Episode: MTTVDBEpisode {
        var id = 0
        var name: String? = "episodeTitle"
        var season: Int? = 9
        var number: Int? = 99
        var image: String? = "episodeImage"
    }

    struct EpisodeRequest: Hashable {
        let seriesID: String
        let pageNumber: Int
        let originalAirDate: String?
    }

    struct SeasonRequest: Hashable {
        let seriesID: String
        let season: Int
    }

    class ResponderMock<Request: Hashable, Response> {
        var responses: [Request: Response] = [:]
        var counts: [Request: Int] = [:]
    }

    var seriesResponders: ResponderMock<String, [MTTVDBSeries]> = ResponderMock()
    var episodeResponders: ResponderMock<EpisodeRequest, (episodes: [MTTVDBEpisode], hasMore: Bool)> = ResponderMock()
    var seriesArtworkResponders: ResponderMock<String, String> = ResponderMock()
    var seasonArtworkResponders: ResponderMock<SeasonRequest, String> = ResponderMock()

    func querySeries(name: String) async -> [MTTVDBSeries] {
        seriesResponders.counts[name] = (seriesResponders.counts[name] ?? 0) + 1
        return seriesResponders.responses[name] ?? []
    }

    func queryEpisodes(seriesID: String, originalAirDate: String?, pageNumber: Int) async -> (episodes: [MTTVDBEpisode], hasMore: Bool)? {
        let request = EpisodeRequest(seriesID: seriesID, pageNumber: pageNumber, originalAirDate: originalAirDate)
        episodeResponders.counts[request] = (episodeResponders.counts[request] ?? 0) + 1
        return episodeResponders.responses[request]
    }

    func querySeriesArtwork(seriesID: String) async -> String? {
        seriesArtworkResponders.counts[seriesID] = (seriesArtworkResponders.counts[seriesID] ?? 0) + 1
        return seriesArtworkResponders.responses[seriesID]
    }

    func querySeasonArtwork(seriesID: String, season: Int) async -> String? {
        let request = SeasonRequest(seriesID: seriesID, season: season)
        seasonArtworkResponders.counts[request] = (seasonArtworkResponders.counts[request] ?? 0) + 1
        return seasonArtworkResponders.responses[request]
    }
    func saveToken() async {}
    func loadToken() async {}
}

class MTTVDBMovieServiceMock: MTTVDBMovieService {

    struct Movie: MTTVDBMovie {
        var title: String? = "seriesTitle"
        var releaseDate: String? = "releaseDate"
        var posterPath: String? = "posterPath"
    }

    struct ResponderMock<Request: Hashable, Response> {
        var responses: [Request: Response] = [:]
        var counts: [Request: Int] = [:]
    }

    var movieResponders: ResponderMock<String, [MTTVDBMovie]> = ResponderMock()

    func queryMovie(name: String) async -> [MTTVDBMovie] {
        movieResponders.counts[name] = (movieResponders.counts[name] ?? 0) + 1
        return movieResponders.responses[name] ?? []
    }
}

//
// These test cases are mostly black-box tests, though they do skip some
// combinations of matching and non-matching attributes based on knowledge
// of the internal matching logic or search order.  The test cases do
// generally limit the configuration of the mock HTTP service to only
// explicitly specify the minimum non-empty responses for the needs of the
// test case, so there may be more calls to the HTTP service than is apparent
// from the code of the test case itself, but only the test cases with names
// ending in "Cached" explicitly verify that there were no additional calls
// made to the HTTP service layer.
//

public class MTTVDBTests: XCTestCase {

    let tvdb = MTTVDB()
    let tvdbService = MTTVDBServiceMock()
    let tvdbMovieService = MTTVDBMovieServiceMock()

    public override func setUp() {
        tvdb.tvdbService = tvdbService
        tvdb.tvdbMovieService = tvdbMovieService
    }

    func testTVDBShowAlreadyProcessed() async {
        let show = MTTiVoShowStub()
        show.tvdbData = [:] as NSDictionary
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertIdentical(result, show.tvdbData)
    }

    func testTMDBMovieAlreadyProcessed() async {
        let show = MTTiVoShowStub()
        show.tvdbData = [:] as NSDictionary
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertIdentical(result, show.tvdbData)
    }

    //
    // Testing Episodic shows for TVDB
    //

    func testEpisodicShowFoundMatchFullName() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let r1 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[r1] = (episodes:[], hasMore: false)
        let r2 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[r2] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundCached() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
        let seriesEpisodeFoundCached = await tvdb.val(.seriesEpisodeFoundCached)
        XCTAssertEqual(seriesEpisodeFoundCached, 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
        XCTAssertEqual(tvdbService.episodeResponders.counts[request], 1)
        XCTAssertEqual(tvdbService.episodeResponders.counts.count, 2)
    }


    func testEpisodicShowFoundSeriesCached() async {
        let show1 = MTTiVoShowStub()
        show1.episodeID = "episodeID1"
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let _ = await tvdb.getTheTVDBDetails(show1)
        let show2 = MTTiVoShowStub()
        show2.episodeID = "episodeID2"
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show2)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
        let episodeNotFound = await tvdb.val(.episodeNotFound)
        XCTAssertEqual(episodeNotFound, 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
        XCTAssertEqual(tvdbService.episodeResponders.counts[request], 2)
        XCTAssertEqual(tvdbService.episodeResponders.counts.count, 2)
    }

    func testEpisodicShowFoundMatchPartialName() async {
        let show = MTTiVoShowStub()
        show.episodeTitle = "episodeTitle; Some other episode title"
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundMatchSeasonInfo() async {
        let show = MTTiVoShowStub()
        show.manualSeasonInfo = true
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundAirDateWithMatchingName() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundAirDateWithoutOtherMatchingInfo() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        var episode = MTTVDBServiceMock.Episode()
        episode.name = "no match"
        episode.number = 44
        episode.season = 4
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "44")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "4")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundMatchSecondSeries() async {
        let show = MTTiVoShowStub()
        var s1 = MTTVDBServiceMock.Series()
        s1.id = "seriesID1"
        s1.slug = "seriesSlug1"
        var s2 = MTTVDBServiceMock.Series()
        s2.id = "seriesID2"
        s2.slug = "seriesSlug2"
        tvdbService.seriesResponders.responses["seriesTitle"] = [s1, s2]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID2", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID2")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug2")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundMatchSecondSeriesAirDate() async {
        let show = MTTiVoShowStub()
        var s1 = MTTVDBServiceMock.Series()
        s1.id = "seriesID1"
        s1.slug = "seriesSlug1"
        var s2 = MTTVDBServiceMock.Series()
        s2.id = "seriesID2"
        s2.slug = "seriesSlug2"
        tvdbService.seriesResponders.responses["seriesTitle"] = [s1, s2]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID2", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID2")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug2")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundMatchSecondPage() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let r1 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[r1] = (episodes:[], hasMore: true)
        let r2 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 1, originalAirDate: nil)
        tvdbService.episodeResponders.responses[r2] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundMatchSecondPageAirDate() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let r1 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[r1] = (episodes:[], hasMore: true)
        let r2 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 1, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[r2] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowFoundMatchNoImages() async {
        let show = MTTiVoShowStub()
        var series = MTTVDBServiceMock.Series()
        series.image = nil
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        var episode = MTTVDBServiceMock.Episode()
        episode.image = nil
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 5)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 1)
    }

    func testEpisodicShowNotFoundNoSeriesCandidates() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.count, 0)
        let episodicSeriesNotFound = await tvdb.val(.episodicSeriesNotFound)
        XCTAssertEqual(episodicSeriesNotFound, 1)
    }

    func testEpisodicShowNotFoundCached() async {
        let show = MTTiVoShowStub()
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.count, 0)
        let episodicSeriesNotFound = await tvdb.val(.episodicSeriesNotFound)
        XCTAssertEqual(episodicSeriesNotFound, 1)
        let episodicSeriesNotFoundCached = await tvdb.val(.episodicSeriesNotFoundCached)
        XCTAssertEqual(episodicSeriesNotFoundCached, 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
    }

    func testEpisodicShowNotFoundNoSeriesCandidatesCached() async {
        let show1 = MTTiVoShowStub()
        show1.episodeID = "episodeID1"
        let show2 = MTTiVoShowStub()
        show2.episodeID = "episodeID2"
        let _ = await tvdb.getTheTVDBDetails(show1)
        let result = await tvdb.getTheTVDBDetails(show2)
        XCTAssertEqual(result.count, 0)
        let episodicSeriesNotFound = await tvdb.val(.episodicSeriesNotFound)
        XCTAssertEqual(episodicSeriesNotFound, 2)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
    }

    func testEpisodicShowNotFoundNoEpisodeCandidates() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleIds.rawValue) as? [String], ["seriesID"])
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleSlugs.rawValue) as? [String], ["seriesSlug"])
        XCTAssertEqual(result.count, 2)
        let episodeNotFound = await tvdb.val(.episodeNotFound)
        XCTAssertEqual(episodeNotFound, 1)
    }

    func testEpisodicShowNotFoundNoEpisodeCandidatesCached() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleIds.rawValue) as? [String], ["seriesID"])
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleSlugs.rawValue) as? [String], ["seriesSlug"])
        XCTAssertEqual(result.count, 2)
        let episodeNotFound = await tvdb.val(.episodeNotFound)
        XCTAssertEqual(episodeNotFound, 1)
        let episodeNotFoundCached = await tvdb.val(.episodeNotFoundCached)
        XCTAssertEqual(episodeNotFoundCached, 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
        let r1 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        let r2 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        XCTAssertEqual(tvdbService.episodeResponders.counts[r1], 1)
        XCTAssertEqual(tvdbService.episodeResponders.counts[r2], 1)
        XCTAssertEqual(tvdbService.episodeResponders.counts.count, 2)
    }

    func testEpisodicShowNotFoundNoMatchingEpisodes() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        var episode = MTTVDBServiceMock.Episode()
        episode.name = "no match"
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleIds.rawValue) as? [String], ["seriesID"])
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleSlugs.rawValue) as? [String], ["seriesSlug"])
        XCTAssertEqual(result.count, 2)
        let episodeNotFound = await tvdb.val(.episodeNotFound)
        XCTAssertEqual(episodeNotFound, 1)
    }

    func testEpisodicShowNotFoundMultipleSeriesCandidates() async {
        let show = MTTiVoShowStub()
        var s1 = MTTVDBServiceMock.Series()
        s1.id = "seriesID1"
        s1.slug = "seriesSlug1"
        var s2 = MTTVDBServiceMock.Series()
        s2.id = "seriesID2"
        s2.slug = "seriesSlug2"
        tvdbService.seriesResponders.responses["seriesTitle"] = [s1, s2]
        var episode = MTTVDBServiceMock.Episode()
        episode.name = "no match"
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleIds.rawValue) as? [String], ["seriesID1", "seriesID2"])
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.possibleSlugs.rawValue) as? [String], ["seriesSlug1", "seriesSlug2"])
        XCTAssertEqual(result.count, 2)
        let episodeNotFound = await tvdb.val(.episodeNotFound)
        XCTAssertEqual(episodeNotFound, 1)
    }

    //
    // Testing Non-episodic shows for TVDB
    //

    func testNonEpisodicShowFoundMatchFullName() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.count, 3)
        let nonEpisodicSeriesFound = await tvdb.val(.nonEpisodicSeriesFound)
        XCTAssertEqual(nonEpisodicSeriesFound, 1)
    }

    func testNonEpisodicShowFoundMatchNameWithYear() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        var series = MTTVDBServiceMock.Series()
        series.name = "seriesTitle (2022)"
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.count, 3)
        let nonEpisodicSeriesFound = await tvdb.val(.nonEpisodicSeriesFound)
        XCTAssertEqual(nonEpisodicSeriesFound, 1)
    }

    func testNonEpisodicShowFoundCached() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.count, 3)
        let nonEpisodicSeriesFound = await tvdb.val(.nonEpisodicSeriesFound)
        XCTAssertEqual(nonEpisodicSeriesFound, 1)
        let nonEpisodicSeriesFoundCached = await tvdb.val(.nonEpisodicSeriesFoundCached)
        XCTAssertEqual(nonEpisodicSeriesFoundCached, 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
    }

    func testNonEpisodicShowFoundFirstMatch() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        var s1 = MTTVDBServiceMock.Series()
        s1.id = "seriesID1"
        s1.slug = "seriesSlug1"
        var s2 = MTTVDBServiceMock.Series()
        s2.id = "seriesID2"
        s2.slug = "seriesSlug2"
        tvdbService.seriesResponders.responses["seriesTitle"] = [s1, s2]
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID1")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug1")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.count, 3)
        let nonEpisodicSeriesFound = await tvdb.val(.nonEpisodicSeriesFound)
        XCTAssertEqual(nonEpisodicSeriesFound, 1)
    }

    func testNonEpisodicShowFoundNoImage() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        var series = MTTVDBServiceMock.Series()
        series.image = nil
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(result.count, 3)
        let nonEpisodicSeriesFound = await tvdb.val(.nonEpisodicSeriesFound)
        XCTAssertEqual(nonEpisodicSeriesFound, 1)
    }

    func testNonEpisodicShowNotFoundNoCandidates() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.count, 0)
        let nonEpisodicSeriesNotFound = await tvdb.val(.nonEpisodicSeriesNotFound)
        XCTAssertEqual(nonEpisodicSeriesNotFound, 1)
    }

    func testNonEpisodicShowNotFoundCached() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.getTheTVDBDetails(show)
        XCTAssertEqual(result.count, 0)
        let nonEpisodicSeriesNotFound = await tvdb.val(.nonEpisodicSeriesNotFound)
        XCTAssertEqual(nonEpisodicSeriesNotFound, 1)
        let nonEpisodicSeriesNotFoundCached = await tvdb.val(.nonEpisodicSeriesNotFoundCached)
        XCTAssertEqual(nonEpisodicSeriesNotFoundCached, 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
    }

    //
    // Testing movies for TMDB
    //

    func testMovieFoundTitleMatchOnly() async {
        let show = MTTiVoShowStub()
        let movie = MTTVDBMovieServiceMock.Movie()
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [movie]
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "posterPath")
        XCTAssertEqual(result.count, 1)
        let movieFound = await tvdb.val(.movieFound)
        XCTAssertEqual(movieFound, 1)
    }

    func testMovieFoundReleaseMatchOnly() async {
        let show = MTTiVoShowStub()
        show.movieYear = "2022"
        var movie = MTTVDBMovieServiceMock.Movie()
        movie.title = "no match"
        movie.releaseDate = "2022-07-04"
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [movie]
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "posterPath")
        XCTAssertEqual(result.count, 1)
        let movieFound = await tvdb.val(.movieFound)
        XCTAssertEqual(movieFound, 1)
    }

    func testMovieFoundExactMatchPreferred() async {
        let show = MTTiVoShowStub()
        show.movieYear = "2022"
        let m1 = MTTVDBMovieServiceMock.Movie()
        var m2 = MTTVDBMovieServiceMock.Movie()
        m2.title = "no match"
        m2.releaseDate = "2022-07-04"
        var m3 = MTTVDBMovieServiceMock.Movie()
        m3.releaseDate = "2022-07-04"
        m3.posterPath = "m3.posterPath"
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [m1, m2, m3]
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "m3.posterPath")
        XCTAssertEqual(result.count, 1)
        let movieFound = await tvdb.val(.movieFound)
        XCTAssertEqual(movieFound, 1)
    }

    func testMovieFoundCached() async {
        let show = MTTiVoShowStub()
        let movie = MTTVDBMovieServiceMock.Movie()
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [movie]
        let _ = await tvdb.getTheMovieDBDetails(show)
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "posterPath")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(tvdbMovieService.movieResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbMovieService.movieResponders.counts.count, 1)
        let movieFound = await tvdb.val(.movieFound)
        XCTAssertEqual(movieFound, 1)
        let movieFoundCached = await tvdb.val(.movieFoundCached)
        XCTAssertEqual(movieFoundCached, 1)
    }

    func testMovieNotFoundNoCandidates() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(result.count, 1)
        let movieNotFound = await tvdb.val(.movieNotFound)
        XCTAssertEqual(movieNotFound, 1)
    }

    func testMovieNotFoundCached() async {
        let show = MTTiVoShowStub()
        let _ = await tvdb.getTheMovieDBDetails(show)
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(result.count, 1)
        let movieNotFound = await tvdb.val(.movieNotFound)
        XCTAssertEqual(movieNotFound, 1)
        let movieNotFoundCached = await tvdb.val(.movieNotFoundCached)
        XCTAssertEqual(movieNotFoundCached, 1)
        XCTAssertEqual(tvdbMovieService.movieResponders.counts["seriesTitle"], 1)
        XCTAssertEqual(tvdbMovieService.movieResponders.counts.count, 1)
    }

    func testMovieNotFoundNeitherTitleNorReleaseDateMatched() async {
        let show = MTTiVoShowStub()
        var movie = MTTVDBMovieServiceMock.Movie()
        movie.title = "no match"
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [movie]
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(result.count, 1)
        let movieNotFound = await tvdb.val(.movieNotFound)
        XCTAssertEqual(movieNotFound, 1)
    }

    func testMovieNotFoundNilPosterPath() async {
        let show = MTTiVoShowStub()
        var movie = MTTVDBMovieServiceMock.Movie()
        movie.posterPath = nil
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [movie]
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(result.count, 1)
        let movieNotFound = await tvdb.val(.movieNotFound)
        XCTAssertEqual(movieNotFound, 1)
    }

    func testMovieFoundInexactMatchPreferredOverExactMatchWithEmptyPosterPath() async {
        let show = MTTiVoShowStub()
        show.movieYear = "2022"
        var exactMatch = MTTVDBMovieServiceMock.Movie()
        exactMatch.releaseDate = "2022-07-04"
        exactMatch.posterPath = ""
        var inexactMatch = MTTVDBMovieServiceMock.Movie()
        inexactMatch.posterPath = "inexactMatch.posterPath"
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [exactMatch, inexactMatch]
        let result = await tvdb.getTheMovieDBDetails(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "inexactMatch.posterPath")
        XCTAssertEqual(result.count, 1)
        let movieFound = await tvdb.val(.movieFound)
        XCTAssertEqual(movieFound, 1)
    }

    //
    // Testing artwork
    //

    func testSeriesArtworkFoundShowCachedWithSeriesArtwork() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 0)
    }

    func testSeriesArtworkFoundFromTVDBService() async {
        let show = MTTiVoShowStub()
        var series = MTTVDBServiceMock.Series()
        series.image = nil
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        tvdbService.seriesArtworkResponders.responses["seriesID"] = "seriesImage"
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts["seriesID"], 1)
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 1)
    }

    func testSeriesArtworkFoundFromTVDBServiceCached() async {
        let show = MTTiVoShowStub()
        var series = MTTVDBServiceMock.Series()
        series.image = nil
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        tvdbService.seriesArtworkResponders.responses["seriesID"] = "seriesImage"
        let _ = await tvdb.getTheTVDBDetails(show)
        let _ = await tvdb.addSeriesArtwork(show)
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts["seriesID"], 1)
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 1)
    }

    func testSeriesArtworkNotFoundShowNeverProcessed() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertNil(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue))
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 0)
    }

    func testSeriesArtworkNotFoundNoSeriesID() async {
        let show = MTTiVoShowStub()
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 0)
    }

    func testSeriesArtworkNotFoundFromTVDBService() async {
        let show = MTTiVoShowStub()
        var series = MTTVDBServiceMock.Series()
        series.image = nil
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts["seriesID"], 1)
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 1)
    }

    func testSeriesArtworkNotFoundFromTVDBServiceCached() async {
        let show = MTTiVoShowStub()
        var series = MTTVDBServiceMock.Series()
        series.image = nil
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let request = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[request] = (episodes:[episode], hasMore: false)
        let _ = await tvdb.getTheTVDBDetails(show)
        let _ = await tvdb.addSeriesArtwork(show)
        let result = await tvdb.addSeriesArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts["seriesID"], 1)
        XCTAssertEqual(tvdbService.seriesArtworkResponders.counts.count, 1)
    }

    func testSeasonArtworkFoundFromTVDBService() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let request = MTTVDBServiceMock.SeasonRequest(seriesID: series.id, season: show.season)
        tvdbService.seasonArtworkResponders.responses[request] = "seasonImage"
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeasonArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue) as? String, "seasonImage")
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts[request], 1)
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts.count, 1)
    }

    func testSeasonArtworkFoundFromTVDBServiceCached() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let request = MTTVDBServiceMock.SeasonRequest(seriesID: series.id, season: show.season)
        tvdbService.seasonArtworkResponders.responses[request] = "seasonImage"
        let _ = await tvdb.getTheTVDBDetails(show)
        let _ = await tvdb.addSeasonArtwork(show)
        let result = await tvdb.addSeasonArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue) as? String, "seasonImage")
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts[request], 1)
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts.count, 1)
    }

    func testSeasonArtworkNotFoundShowNeverProcessed() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.addSeasonArtwork(show)
        XCTAssertNil(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue))
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts.count, 0)
    }

    func testSeasonArtworkNotFoundNoSeriesID() async {
        let show = MTTiVoShowStub()
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeasonArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue) as? String, "")
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts.count, 0)
    }

    func testSeasonArtworkNotFoundFromTVDBService() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let request = MTTVDBServiceMock.SeasonRequest(seriesID: series.id, season: show.season)
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.addSeasonArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue) as? String, "")
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts[request], 1)
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts.count, 1)
    }

    func testSeasonArtworkNotFoundFromTVDBServiceCached() async {
        let show = MTTiVoShowStub()
        show.isEpisodicShow = false
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let request = MTTVDBServiceMock.SeasonRequest(seriesID: series.id, season: show.season)
        let _ = await tvdb.getTheTVDBDetails(show)
        let _ = await tvdb.addSeasonArtwork(show)
        let result = await tvdb.addSeasonArtwork(show)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue) as? String, "")
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts[request], 1)
        XCTAssertEqual(tvdbService.seasonArtworkResponders.counts.count, 1)
    }

    func testInvalidateEpisodeArtwork() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.invalidateArtwork(show, forKey: MTTVDBCache.Key.episodeArtwork.rawValue)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "")
    }

    func testInvalidateSeasonArtwork() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.invalidateArtwork(show, forKey: MTTVDBCache.Key.seasonArtwork.rawValue)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seasonArtwork.rawValue) as? String, "")
    }

    func testInvalidateSeriesArtwork() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.invalidateArtwork(show, forKey: MTTVDBCache.Key.seriesArtwork.rawValue)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "")
    }

    func testInvalidateArtworkUnknownKey() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.invalidateArtwork(show, forKey: "unknown")
        XCTAssertEqual(result.count, 0)
    }

    func testInvalidateArtworkImproperKey() async {
        let show = MTTiVoShowStub()
        let result = await tvdb.invalidateArtwork(show, forKey: MTTVDBCache.Key.status.rawValue)
        XCTAssertEqual(result.count, 0)
    }

    func testResetTVDBInfoEpisode() async {
        let show = MTTiVoShowStub()
        let series = MTTVDBServiceMock.Series()
        tvdbService.seriesResponders.responses["seriesTitle"] = [series]
        let episode = MTTVDBServiceMock.Episode()
        let r1 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: "originalAirDateNoTime")
        tvdbService.episodeResponders.responses[r1] = (episodes:[], hasMore: false)
        let r2 = MTTVDBServiceMock.EpisodeRequest(seriesID: "seriesID", pageNumber: 0, originalAirDate: nil)
        tvdbService.episodeResponders.responses[r2] = (episodes:[episode], hasMore: false)
        let _ = await tvdb.getTheTVDBDetails(show)
        let result = await tvdb.getTheTVDBDetails(show, reset: true)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.series.rawValue) as? String, "seriesID")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.slug.rawValue) as? String, "seriesSlug")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "seriesImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episodeArtwork.rawValue) as? String, "episodeImage")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.episode.rawValue) as? String, "99")
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.season.rawValue) as? String, "9")
        XCTAssertEqual(result.count, 6)
        // Verify that everything in remote service was hit twice
        XCTAssertEqual(tvdbService.seriesResponders.counts["seriesTitle"], 2)
        XCTAssertEqual(tvdbService.seriesResponders.counts.count, 1)
        XCTAssertEqual(tvdbService.episodeResponders.counts[r1], 2)
        XCTAssertEqual(tvdbService.episodeResponders.counts[r2], 2)
        XCTAssertEqual(tvdbService.episodeResponders.counts.count, 2)
        let seriesEpisodeFound = await tvdb.val(.seriesEpisodeFound)
        XCTAssertEqual(seriesEpisodeFound, 2)
    }

    func testResetTVDBInfoMovie() async {
        let show = MTTiVoShowStub()
        let movie = MTTVDBMovieServiceMock.Movie()
        tvdbMovieService.movieResponders.responses["seriesTitle"] = [movie]
        let _ = await tvdb.getTheMovieDBDetails(show)
        let result = await tvdb.getTheMovieDBDetails(show, reset: true)
        XCTAssertEqual(result.value(forKey: MTTVDBCache.Key.seriesArtwork.rawValue) as? String, "posterPath")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(tvdbMovieService.movieResponders.counts["seriesTitle"], 2)
        XCTAssertEqual(tvdbMovieService.movieResponders.counts.count, 1)
        let movieFound = await tvdb.val(.movieFound)
        XCTAssertEqual(movieFound, 2)
    }
}

