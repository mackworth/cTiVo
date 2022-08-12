//
//  MTTMDBServiceTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo

class MTTVDBMovieServiceTests: XCTestCase {
    let url = "https://api.themoviedb.org/3/search/movie?query=Cool Hand Luke&api_key=APIKEY"
    let data = """
               {
                 "results": [
                   {
                     "title": "Cool Hand Luke",
                     "release_date": "1967-06-22",
                     "poster_path": "/4ykzTiHKLamh3eZJ8orVICtU2Jp.jpg"
                   }
                 ]
               }
               """

    var service: MTTVDBMovieService!

    override func setUp() {
        super.setUp()
        service = MTTVDBMovieServiceV3(keyProvider: { "APIKEY" }, session: createMockSession())
        MTMockURLProtocol.reset()
        let _ = setMockResponse(for: url, data: data, statusCode: 200)
    }

    func testFullyPopulated() async {
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].title, "Cool Hand Luke")
        XCTAssertEqual(result[0].releaseDate, "1967-06-22")
        XCTAssertEqual(result[0].posterPath, "/4ykzTiHKLamh3eZJ8orVICtU2Jp.jpg")
    }

    func testDecodingError() async {
        let badData = """
                   [
                     {
                       "title": "Cool Hand Luke",
                       "release": "1967-06-22",
                       "posterPath": "/4ykzTiHKLamh3eZJ8orVICtU2Jp.jpg"
                     }
                   ]
                   """
        let _ = setMockResponse(for: url, data: badData, statusCode: 200)
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 0)
    }

    func testNoOptionalResultsKey() async {
        let minimalData = """
                   {
                   }
                   """
        let _ = setMockResponse(for: url, data: minimalData, statusCode: 200)
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 0)
    }

    func testNoOptionalMovieKeys() async {
        let minimalData = """
                   {
                     "results": [
                       {
                       }
                     ]
                   }
                   """
        let _ = setMockResponse(for: url, data: minimalData, statusCode: 200)
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertNil(result[0].title)
        XCTAssertNil(result[0].releaseDate)
        XCTAssertNil(result[0].posterPath)
    }

    func testStatusCodeUnauthorized() async {
        let _ = setMockResponse(for: url, data: data, statusCode: 401)
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 0)
    }

    func testStatusCodeNotFound() async {
        let _ = setMockResponse(for: url, data: data, statusCode: 404)
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 0)
    }

    func testError() async {
        let _ = setMockResponse(for: url, data: data, statusCode: 200, message: "Mock HTTP Error")
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 0)
    }
}

//
// This test exercises the API endpoint in a live connection to
// fetch known -- and hopefully stable -- values to validate whether
// the API is still returning the expected responses.  Any failures
// here should indicate either that the API is down or that someone
// has updated the underlying data in the server or that the API has
// changed unexpectedly.  Any failures here that result from logic
// errors in the MTTVDBMovieService implementation should have a
// corresponding test case above.  This test is usually not
// enabled in the project and is meant to be turned on only when
// diagnosing suspected changes in the live API.
//
class MTTVDBMovieServiceTestsWithLiveConnection: XCTestCase {

    var service: MTTVDBMovieService!

    override func setUp() {
        super.setUp()
        service = MTTVDBMovieServiceV3()
    }

    func testQueryMovie() async {
        let result = await service.queryMovie(name: "Cool Hand Luke")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Cool Hand Luke")
        XCTAssertEqual(result[0].releaseDate, "1967-06-22")
        XCTAssertEqual(result[0].posterPath, "/4ykzTiHKLamh3eZJ8orVICtU2Jp.jpg")
    }
}