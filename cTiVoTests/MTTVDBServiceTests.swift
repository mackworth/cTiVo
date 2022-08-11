//
//  MTTVDBServiceTests.swift
//  cTiVoTests
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import XCTest

@testable import cTiVo


fileprivate func keyProvider() -> (key: String, pin: String?) {
    (key: "APIKEY", pin: nil)
}

let baseURL = "https://testing.com"

class MTTVDBAuthenticatorTests: XCTestCase {
    let url = "\(baseURL)/login"
    let validData = """
                    {
                      "data": {
                        "token": "bearerToken"
                      }
                    }
                    """
    
    var authenticator: MTTVDBAuthenticator!
        
    override func setUp() {
        super.setUp()
        authenticator = MTTVDBAuthenticator(
                baseURL: baseURL,
                duration: 30 * 24 * 60 * 60,
                keyProvider: keyProvider,
                session: createMockSession()
        )
        MTMockURLProtocol.reset()
    }
    
    func testValidResponse() async {
        let _ = setMockResponse(for: url, data: validData, statusCode: 200)
        let result = await authenticator.fetchToken()
        XCTAssertEqual(result, "bearerToken")
    }

    func testInvalidCredentials() async {
        let data = """
                   {
                     "data": {
                       "token": "bearerToken"
                     }
                   }
                   """
        let _ = setMockResponse(for: url, data: data, statusCode: 401)
        let result = await authenticator.fetchToken()
        XCTAssertNil(result)
    }

    func testDecodingError() async {
        let data = """
                   {
                     "data": {
                     }
                   }
                   """
        let _ = setMockResponse(for: url, data: data, statusCode: 200)
        let result = await authenticator.fetchToken()
        XCTAssertNil(result)
    }

    func testMissingDataKey() async {
        let data = """
                   {
                     "fred": {
                     }
                   }
                   """
        let _ = setMockResponse(for: url, data: data, statusCode: 200)
        let result = await authenticator.fetchToken()
        XCTAssertNil(result)
    }

    func testError() async {
        let _ = setMockResponse(for: url, data: validData, statusCode: 200, message: "Mock HTTP Error")
        let result = await authenticator.fetchToken()
        XCTAssertNil(result)
    }

    func testCache() async {
        let key = setMockResponse(for: url, data: validData, statusCode: 200)
        let _ = await authenticator.fetchToken()
        let result = await authenticator.fetchToken()
        XCTAssertEqual(result, "bearerToken")
        XCTAssertEqual(MTMockURLProtocol.counts[key], 1)
    }

    func testDiscardCurrentToken() async {
        let key = setMockResponse(for: url, data: validData, statusCode: 200)
        let _ = await authenticator.fetchToken()
        await authenticator.discardCurrentToken()
        let result = await authenticator.fetchToken()
        XCTAssertEqual(result, "bearerToken")
        XCTAssertEqual(MTMockURLProtocol.counts[key], 2)
    }

    func testDiscardThisToken() async {
        let key = setMockResponse(for: url, data: validData, statusCode: 200)
        if let token = await authenticator.fetchToken() {
            await authenticator.discardThisToken(token)
        } else {
            XCTFail("Failed to fetch initial token")
        }
        let result = await authenticator.fetchToken()
        XCTAssertEqual(result, "bearerToken")
        XCTAssertEqual(MTMockURLProtocol.counts[key], 2)
    }

    func testDiscardSomeOtherToken() async {
        let key = setMockResponse(for: url, data: validData, statusCode: 200)
        if await authenticator.fetchToken() != nil {
            await authenticator.discardThisToken("some other token")
        } else {
            XCTFail("Failed to fetch initial token")
        }
        let result = await authenticator.fetchToken()
        XCTAssertEqual(result, "bearerToken")
        XCTAssertEqual(MTMockURLProtocol.counts[key], 1)
    }

    func testExpirationDuration() async {
        var date = Date()
        let dateProvider: () -> Date = { date }
        await authenticator.setDateProvider(dateProvider)
        let key = setMockResponse(for: url, data: validData, statusCode: 200)
        let _ = await authenticator.fetchToken()
        date.addTimeInterval(30 * 24 * 60 * 60)
        let result = await authenticator.fetchToken()
        XCTAssertEqual(result, "bearerToken")
        XCTAssertEqual(MTMockURLProtocol.counts[key], 2)
    }
}

class MTTVDBServiceTests: XCTestCase {
    var service: MTTVDBService!

    let paramName = "Craig of the Creek"
    let paramSeriesID = "338736"
    let paramOriginalAirDate = "2021-02-06"
    let paramPageNumber = 1
    let paramSeason = 2

    let urlLogin = "https://api4.thetvdb.com/v4/login"
    let urlSeries = "https://api4.thetvdb.com/v4/search?query=Craig of the Creek&type=series"
    let urlEpisodes = "https://api4.thetvdb.com/v4/series/338736/episodes/default?page=1&airDate=2021-02-06"
    let urlSeriesArtwork = "https://api4.thetvdb.com/v4/series/338736"
    let urlSeasonArtwork = "https://api4.thetvdb.com/v4/series/338736/extended?short=true"

    let dataLogin = """
                    {
                      "data": {
                        "token": "bearerToken"
                      }
                    }
                    """
    let dataSeries = """
                     {
                       "status": "success",
                       "data": [
                         {
                           "tvdb_id": "338736",
                           "slug": "craig-of-the-creek",
                           "name": "Craig of the Creek",
                           "image_url": "seriesImage"
                         }
                       ]
                     }
                     """
    let dataEpisodes = """
                       {
                         "status": "success",
                         "data": {
                           "episodes": [
                             {
                               "id": 8162231,
                               "name": "Snow Place Like Home",
                               "seasonNumber": 3,
                               "number": 20,
                               "image": "episodeImage"
                             }
                           ]
                         },
                         "links": {
                           "next": "next page url"
                         }
                       }
                       """
    let dataSeriesArtwork = """
                      {
                        "status": "success",
                        "data": {
                          "image": "seriesImage"
                        }
                      }
                      """
    let dataSeasonArtwork = """
                      {
                        "status": "success",
                        "data": {
                          "image": "seriesImage",
                          "seasons": [
                            {
                              "number": 1,
                              "image": "seasonImage1"
                            },
                            {
                              "number": 2,
                              "image": "seasonImage2"
                            }
                          ]
                        }
                      }
                      """

    var keyLogin: URL?
    var keySeries: URL?
    var keyEpisodes: URL?
    var keySeriesArtwork: URL?
    var keySeasonArtwork: URL?

    override func setUp() {
        super.setUp()

        service = MTTVDBServiceV4(
                keyProvider: keyProvider,
                session: createMockSession()
        )

        MTMockURLProtocol.reset()

        keyLogin = setMockResponse(for: urlLogin, data: dataLogin, statusCode: 200)
        keySeries = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200)
        keyEpisodes = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200)
        keySeriesArtwork = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200)
        keySeasonArtwork = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200)
    }

    func testQuerySeriesValid() async {
        let result = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].id, "338736")
        XCTAssertEqual(result[0].slug, "craig-of-the-creek")
        XCTAssertEqual(result[0].name, "Craig of the Creek")
        XCTAssertEqual(result[0].image, "seriesImage")
    }

    func testQuerySeriesUnauthorized() async {
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 401)
        let r1 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r1.count, 0)
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200)
        let r2 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r2.count, 1)
        guard r2.count == 1 else { return }
        XCTAssertEqual(r2[0].id, "338736")
        XCTAssertEqual(r2[0].slug, "craig-of-the-creek")
        XCTAssertEqual(r2[0].name, "Craig of the Creek")
        XCTAssertEqual(r2[0].image, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 2)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeries], 2)
    }

    func testQuerySeriesOtherStatusCodeError() async {
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 418)
        let r1 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r1.count, 0)
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200)
        let r2 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r2.count, 1)
        guard r2.count == 1 else { return }
        XCTAssertEqual(r2[0].id, "338736")
        XCTAssertEqual(r2[0].slug, "craig-of-the-creek")
        XCTAssertEqual(r2[0].name, "Craig of the Creek")
        XCTAssertEqual(r2[0].image, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeries], 2)
    }

    func testQuerySeriesThrownError() async {
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200, message: "Mock HTTP Error")
        let r1 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r1.count, 0)
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200)
        let r2 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r2.count, 1)
        guard r2.count == 1 else { return }
        XCTAssertEqual(r2[0].id, "338736")
        XCTAssertEqual(r2[0].slug, "craig-of-the-creek")
        XCTAssertEqual(r2[0].name, "Craig of the Creek")
        XCTAssertEqual(r2[0].image, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeries], 2)
    }

    func testQuerySeriesStatusStringNotSuccess() async {
        let failSeries = """
                         {
                           "status": "not success",
                           "data": [
                             {
                               "tvdb_id": "338736",
                               "slug": "craig-of-the-creek",
                               "name": "Craig of the Creek",
                               "image_url": "seriesImage"
                             }
                           ]
                         }
                         """
        let _ = setMockResponse(for: urlSeries, data: failSeries, statusCode: 200)
        let r1 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r1.count, 0)
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200)
        let r2 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r2.count, 1)
        guard r2.count == 1 else { return }
        XCTAssertEqual(r2[0].id, "338736")
        XCTAssertEqual(r2[0].slug, "craig-of-the-creek")
        XCTAssertEqual(r2[0].name, "Craig of the Creek")
        XCTAssertEqual(r2[0].image, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeries], 2)
    }

    func testQuerySeriesDecodingError() async {
        let failSeries = """
                         {
                           "status": "success",
                           "data": [
                             {
                               "name": "Craig of the Creek",
                               "image_url": "seriesImage"
                             }
                           ]
                         }
                         """
        let _ = setMockResponse(for: urlSeries, data: failSeries, statusCode: 200)
        let r1 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r1.count, 0)
        let _ = setMockResponse(for: urlSeries, data: dataSeries, statusCode: 200)
        let r2 = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(r2.count, 1)
        guard r2.count == 1 else { return }
        XCTAssertEqual(r2[0].id, "338736")
        XCTAssertEqual(r2[0].slug, "craig-of-the-creek")
        XCTAssertEqual(r2[0].name, "Craig of the Creek")
        XCTAssertEqual(r2[0].image, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeries], 2)
    }

    func testQuerySeriesNoDataKey() async {
        let emptySeries = """
                          {
                            "status": "success"
                          }
                          """
        let _ = setMockResponse(for: urlSeries, data: emptySeries, statusCode: 200)
        let result = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(result.count, 0)
    }

    func testQuerySeriesMinimalProperties() async {
        let minimalSeries = """
                            {
                              "status": "success",
                              "data": [
                                {
                                  "tvdb_id": "338736",
                                  "slug": "craig-of-the-creek"
                                }
                              ]
                            }
                            """
        let _ = setMockResponse(for: urlSeries, data: minimalSeries, statusCode: 200)
        let result = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].id, "338736")
        XCTAssertEqual(result[0].slug, "craig-of-the-creek")
        XCTAssertNil(result[0].name)
        XCTAssertNil(result[0].image)
    }

    func testQueryEpisodesValid() async {
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let result = result else { XCTFail(); return }
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.episodes.count, 1)
        guard result.episodes.count == 1 else { return }
        XCTAssertEqual(result.episodes[0].id, 8162231)
        XCTAssertEqual(result.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(result.episodes[0].season, 3)
        XCTAssertEqual(result.episodes[0].number, 20)
        XCTAssertEqual(result.episodes[0].image, "episodeImage")
    }

    func testQueryEpisodesUnauthorized() async {
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 401)
        let r1 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200)
        let r2 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let r2 = r2 else { XCTFail(); return }
        XCTAssertTrue(r2.hasMore)
        XCTAssertEqual(r2.episodes.count, 1)
        guard r2.episodes.count == 1 else { return }
        XCTAssertEqual(r2.episodes[0].id, 8162231)
        XCTAssertEqual(r2.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(r2.episodes[0].season, 3)
        XCTAssertEqual(r2.episodes[0].number, 20)
        XCTAssertEqual(r2.episodes[0].image, "episodeImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 2)
        XCTAssertEqual(MTMockURLProtocol.counts[keyEpisodes], 2)
    }

    func testQueryEpisodesOtherStatusCodeError() async {
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 418)
        let r1 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200)
        let r2 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let r2 = r2 else { XCTFail(); return }
        XCTAssertTrue(r2.hasMore)
        XCTAssertEqual(r2.episodes.count, 1)
        guard r2.episodes.count == 1 else { return }
        XCTAssertEqual(r2.episodes[0].id, 8162231)
        XCTAssertEqual(r2.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(r2.episodes[0].season, 3)
        XCTAssertEqual(r2.episodes[0].number, 20)
        XCTAssertEqual(r2.episodes[0].image, "episodeImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keyEpisodes], 2)
    }

    func testQueryEpisodesThrownError() async {
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200, message: "Mock HTTP Error")
        let r1 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200)
        let r2 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let r2 = r2 else { XCTFail(); return }
        XCTAssertTrue(r2.hasMore)
        XCTAssertEqual(r2.episodes.count, 1)
        guard r2.episodes.count == 1 else { return }
        XCTAssertEqual(r2.episodes[0].id, 8162231)
        XCTAssertEqual(r2.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(r2.episodes[0].season, 3)
        XCTAssertEqual(r2.episodes[0].number, 20)
        XCTAssertEqual(r2.episodes[0].image, "episodeImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keyEpisodes], 2)
    }

    func testQueryEpisodesStatusStringNotSuccess() async {
        let failEpisodes = """
                           {
                             "status": "not success",
                             "data": {
                               "episodes": [
                                 {
                                   "id": 8162231,
                                   "name": "Snow Place Like Home",
                                   "seasonNumber": 3,
                                   "number": 20,
                                   "image": "episodeImage"
                                 }
                               ]
                             },
                             "links": {
                               "next": "next page url"
                             }
                           }
                           """
        let _ = setMockResponse(for: urlEpisodes, data: failEpisodes, statusCode: 200)
        let r1 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200)
        let r2 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let r2 = r2 else { XCTFail(); return }
        XCTAssertTrue(r2.hasMore)
        XCTAssertEqual(r2.episodes.count, 1)
        guard r2.episodes.count == 1 else { return }
        XCTAssertEqual(r2.episodes[0].id, 8162231)
        XCTAssertEqual(r2.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(r2.episodes[0].season, 3)
        XCTAssertEqual(r2.episodes[0].number, 20)
        XCTAssertEqual(r2.episodes[0].image, "episodeImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keyEpisodes], 2)
    }

    func testQueryEpisodesDecodingError() async {
        let failEpisodes = """
                           {
                             "status": "success",
                             "data": {
                               "episodes": [
                                 {
                                   "name": "Snow Place Like Home",
                                   "seasonNumber": 3,
                                   "number": 20,
                                   "image": "episodeImage"
                                 }
                               ]
                             },
                             "links": {
                               "next": "next page url"
                             }
                           }
                           """
        let _ = setMockResponse(for: urlEpisodes, data: failEpisodes, statusCode: 200)
        let r1 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlEpisodes, data: dataEpisodes, statusCode: 200)
        let r2 = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let r2 = r2 else { XCTFail(); return }
        XCTAssertTrue(r2.hasMore)
        XCTAssertEqual(r2.episodes.count, 1)
        guard r2.episodes.count == 1 else { return }
        XCTAssertEqual(r2.episodes[0].id, 8162231)
        XCTAssertEqual(r2.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(r2.episodes[0].season, 3)
        XCTAssertEqual(r2.episodes[0].number, 20)
        XCTAssertEqual(r2.episodes[0].image, "episodeImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keyEpisodes], 2)
    }

    func testQueryEpisodesNoDataKey() async {
        let emptyEpisodes = """
                            {
                              "status": "success",
                              "links": {
                                "next": "next page url"
                              }
                            }
                            """
        let _ = setMockResponse(for: urlEpisodes, data: emptyEpisodes, statusCode: 200)
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(result)
    }

    func testQueryEpisodesNoEpisodesKey() async {
        let minimalEpisodes = """
                              {
                                "status": "success",
                                "data": {
                                },
                                "links": {
                                  "next": "next page url"
                                }
                              }
                              """
        let _ = setMockResponse(for: urlEpisodes, data: minimalEpisodes, statusCode: 200)
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        XCTAssertNil(result)
    }

    func testQueryEpisodesMinimalProperties() async {
        let minimalEpisodes = """
                              {
                                "status": "success",
                                "data": {
                                  "episodes": [
                                    {
                                      "id": 8162231
                                    }
                                  ]
                                },
                                "links": {
                                  "next": "next page url"
                                }
                              }
                              """
        let _ = setMockResponse(for: urlEpisodes, data: minimalEpisodes, statusCode: 200)
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let result = result else { XCTFail(); return }
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.episodes.count, 1)
        guard result.episodes.count == 1 else { return }
        XCTAssertEqual(result.episodes[0].id, 8162231)
        XCTAssertNil(result.episodes[0].name)
        XCTAssertNil(result.episodes[0].season)
        XCTAssertNil(result.episodes[0].number)
        XCTAssertNil(result.episodes[0].image)
    }

    func testQueryEpisodesNoLinksKey() async {
        let minimalEpisodes = """
                              {
                                "status": "success",
                                "data": {
                                  "episodes": [
                                    {
                                      "id": 8162231,
                                      "name": "Snow Place Like Home",
                                      "seasonNumber": 3,
                                      "number": 20,
                                      "image": "episodeImage"
                                    }
                                  ]
                                }
                              }
                              """
        let _ = setMockResponse(for: urlEpisodes, data: minimalEpisodes, statusCode: 200)
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let result = result else { XCTFail(); return }
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(result.episodes.count, 1)
        guard result.episodes.count == 1 else { return }
        XCTAssertEqual(result.episodes[0].id, 8162231)
        XCTAssertEqual(result.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(result.episodes[0].season, 3)
        XCTAssertEqual(result.episodes[0].number, 20)
        XCTAssertEqual(result.episodes[0].image, "episodeImage")
    }

    func testQueryEpisodesNoNextKey() async {
        let minimalEpisodes = """
                              {
                                "status": "success",
                                "data": {
                                  "episodes": [
                                    {
                                      "id": 8162231,
                                      "name": "Snow Place Like Home",
                                      "seasonNumber": 3,
                                      "number": 20,
                                      "image": "episodeImage"
                                    }
                                  ]
                                },
                                "links": {
                                }
                              }
                              """
        let _ = setMockResponse(for: urlEpisodes, data: minimalEpisodes, statusCode: 200)
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06", pageNumber: 1)
        guard let result = result else { XCTFail(); return }
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(result.episodes.count, 1)
        guard result.episodes.count == 1 else { return }
        XCTAssertEqual(result.episodes[0].id, 8162231)
        XCTAssertEqual(result.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(result.episodes[0].season, 3)
        XCTAssertEqual(result.episodes[0].number, 20)
        XCTAssertEqual(result.episodes[0].image, "episodeImage")
    }

    func testQueryEpisodesNoOriginalAirDateParameter() async {
        let _ = setMockResponse(for: urlEpisodes, data: "", statusCode: 500) // Remove response for original test URL
        let shortUrlEpisodes = "https://api4.thetvdb.com/v4/series/338736/episodes/default?page=0"
        let _ = setMockResponse(for: shortUrlEpisodes, data: dataEpisodes, statusCode: 200)
        let result = await service.queryEpisodes(seriesID: "338736")
        guard let result = result else { XCTFail(); return }
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.episodes.count, 1)
        guard result.episodes.count == 1 else { return }
        XCTAssertEqual(result.episodes[0].id, 8162231)
        XCTAssertEqual(result.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(result.episodes[0].season, 3)
        XCTAssertEqual(result.episodes[0].number, 20)
        XCTAssertEqual(result.episodes[0].image, "episodeImage")
    }

    func testQuerySeriesArtworkValid() async {
        let result = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(result, "seriesImage")
    }

    func testQuerySeriesArtworkUnauthorized() async {
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 401)
        let r1 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200)
        let r2 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(r2, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 2)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeriesArtwork], 2)
    }

    func testQuerySeriesArtworkOtherStatusCodeError() async {
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 418)
        let r1 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200)
        let r2 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(r2, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeriesArtwork], 2)
    }

    func testQuerySeriesArtworkThrownError() async {
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200, message: "Mock HTTP Error")
        let r1 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200)
        let r2 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(r2, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeriesArtwork], 2)
    }

    func testQuerySeriesArtworkStatusStringNotSuccess() async {
        let failSeriesArtwork = """
                                {
                                  "status": "not success",
                                  "data": {
                                    "image": "seriesImage"
                                  }
                                }
                                """
        let _ = setMockResponse(for: urlSeriesArtwork, data: failSeriesArtwork, statusCode: 200)
        let r1 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200)
        let r2 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(r2, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeriesArtwork], 2)
    }

    func testQuerySeriesArtworkDecodingError() async {
        let failSeriesArtwork = """
                                [
                                  {
                                    "image": "seriesImage"
                                  }
                                ]
                                """
        let _ = setMockResponse(for: urlSeriesArtwork, data: failSeriesArtwork, statusCode: 200)
        let r1 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeriesArtwork, data: dataSeriesArtwork, statusCode: 200)
        let r2 = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(r2, "seriesImage")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeriesArtwork], 2)
    }

    func testQuerySeriesArtworkNoDataKey() async {
        let emptySeriesArtwork = """
                                 {
                                   "status": "success"
                                 }
                                 """
        let _ = setMockResponse(for: urlSeriesArtwork, data: emptySeriesArtwork, statusCode: 200)
        let result = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(result)
    }

    func testQuerySeriesArtworkMinimalProperties() async {
        let minimalSeriesArtwork = """
                                   {
                                     "status": "success",
                                     "data": {
                                     }
                                   }
                                   """
        let _ = setMockResponse(for: urlSeriesArtwork, data: minimalSeriesArtwork, statusCode: 200)
        let result = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertNil(result)
    }

    func testQuerySeasonArtworkValid() async {
        let result = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(result, "seasonImage2")
    }

    func testQuerySeasonArtworkUnauthorized() async {
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 401)
        let r1 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200)
        let r2 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(r2, "seasonImage2")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 2)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeasonArtwork], 2)
    }

    func testQuerySeasonArtworkOtherStatusCodeError() async {
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 418)
        let r1 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200)
        let r2 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(r2, "seasonImage2")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeasonArtwork], 2)
    }

    func testQuerySeasonArtworkThrownError() async {
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200, message: "Mock HTTP Error")
        let r1 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200)
        let r2 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(r2, "seasonImage2")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeasonArtwork], 2)
    }

    func testQuerySeasonArtworkStatusStringNotSuccess() async {
        let failSeasonArtwork = """
                                {
                                  "status": "not success",
                                  "data": {
                                    "image": "seriesImage",
                                    "seasons": [
                                      {
                                        "number": 1,
                                        "image": "seasonImage1"
                                      },
                                      {
                                        "number": 2,
                                        "image": "seasonImage2"
                                      }
                                    ]
                                  }
                                }
                                """
        let _ = setMockResponse(for: urlSeasonArtwork, data: failSeasonArtwork, statusCode: 200)
        let r1 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200)
        let r2 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(r2, "seasonImage2")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeasonArtwork], 2)
    }

    func testQuerySeasonArtworkDecodingError() async {
        let failSeasonArtwork = """
                                [
                                  {
                                    "image": "seriesImage",
                                    "seasons": [
                                      {
                                        "number": 1,
                                        "image": "seasonImage1"
                                      },
                                      {
                                        "number": 2,
                                        "image": "seasonImage2"
                                      }
                                    ]
                                  }
                                ]
                                """
        let _ = setMockResponse(for: urlSeasonArtwork, data: failSeasonArtwork, statusCode: 200)
        let r1 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(r1)
        let _ = setMockResponse(for: urlSeasonArtwork, data: dataSeasonArtwork, statusCode: 200)
        let r2 = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(r2, "seasonImage2")
        XCTAssertEqual(MTMockURLProtocol.counts[keyLogin], 1)
        XCTAssertEqual(MTMockURLProtocol.counts[keySeasonArtwork], 2)
    }

    func testQuerySeasonArtworkNoDataKey() async {
        let emptySeasonArtwork = """
                                {
                                  "status": "success"
                                }
                                """
        let _ = setMockResponse(for: urlSeasonArtwork, data: emptySeasonArtwork, statusCode: 200)
        let result = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(result)
    }

    func testQuerySeasonNoSeasonsKey() async {
        let minimalSeasonArtwork = """
                                   {
                                     "status": "success",
                                     "data": {
                                       "image": "seriesImage"
                                     }
                                   }
                                   """
        let _ = setMockResponse(for: urlSeasonArtwork, data: minimalSeasonArtwork, statusCode: 200)
        let result = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(result)
    }

    func testQuerySeasonArtworkMinimalProperties() async {
        let minimalSeasonArtwork = """
                                   {
                                     "status": "success",
                                     "data": {
                                       "image": "seriesImage",
                                       "seasons": [
                                         {
                                         }
                                       ]
                                     }
                                   }
                                   """
        let _ = setMockResponse(for: urlSeasonArtwork, data: minimalSeasonArtwork, statusCode: 200)
        let result = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(result)
    }

    func testQuerySeasonArtworkNoMatchingSeason() async {
        let noMatchingSeasonArtwork = """
                                      {
                                        "status": "success",
                                        "data": {
                                          "image": "seriesImage",
                                          "seasons": [
                                            {
                                              "number": 1,
                                              "image": "seasonImage1"
                                            }
                                          ]
                                        }
                                      }
                                      """
        let _ = setMockResponse(for: urlSeasonArtwork, data: noMatchingSeasonArtwork, statusCode: 200)
        let result = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertNil(result)
    }
}

//
// These tests exercise each of the endpoints in a live connection to
// fetch known -- and hopefully stable -- values to validate whether
// the API is still returning the expected responses.  Any failures
// here should indicate either that the API is down or that someone
// has updated the underlying data in the server or that the API has
// changed unexpectedly.  Any failures here that result from logic
// errors in the MTTVDBService implementation should have a
// corresponding test case above.  These tests are usually not
// enabled in the project and are meant to be turned on only when
// diagnosing suspected changes in the live API.
//
class MTTVDBServiceTestsWithLiveConnection: XCTestCase {

    var service: MTTVDBService!

    override func setUp() {
        super.setUp()
        service = MTTVDBServiceV4()
    }

    func testQuerySeries() async {
        let result = await service.querySeries(name: "Craig of the Creek")
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].id, "338736")
        XCTAssertEqual(result[0].slug, "craig-of-the-creek")
        XCTAssertEqual(result[0].name, "Craig of the Creek")
        XCTAssertEqual(result[0].image, "https://artworks.thetvdb.com/banners/posters/5ccf96520ca8e.jpg")
    }

    func testQueryEpisodes() async {
        let result = await service.queryEpisodes(seriesID: "338736", originalAirDate: "2021-02-06")
        guard let result = result else { XCTFail(); return }
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(result.episodes.count, 1)
        guard result.episodes.count == 1 else { return }
        XCTAssertEqual(result.episodes[0].id, 8162231)
        XCTAssertEqual(result.episodes[0].name, "Snow Place Like Home")
        XCTAssertEqual(result.episodes[0].season, 3)
        XCTAssertEqual(result.episodes[0].number, 20)
        XCTAssertEqual(result.episodes[0].image, "https://artworks.thetvdb.com/banners/series/338736/episodes/60216ae6e0a6e.jpg")
    }

    func testQuerySeriesArtwork() async {
        let result = await service.querySeriesArtwork(seriesID: "338736")
        XCTAssertEqual(result, "https://artworks.thetvdb.com/banners/posters/5ccf96520ca8e.jpg")
    }

    func testQuerySeasonArtwork() async {
        let result = await service.querySeasonArtwork(seriesID: "338736", season: 2)
        XCTAssertEqual(result, "https://artworks.thetvdb.com/banners/series/338736/seasons/815632/posters/5ef38e94a413c.jpg")
    }
}
