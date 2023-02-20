//
//  MTTVDBService.swift
//  cTiVo
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import Foundation

public protocol MTTVDBSeries {
    var id: String { get }
    var slug: String { get }
    var name: String? { get }
    var image: String? { get }
}

public protocol MTTVDBEpisode {
    var id: Int { get }
    var name: String? { get }
    var season: Int? { get }
    var number: Int? { get }
    var image: String? { get }
}

public protocol MTTVDBService {
    func querySeries(name: String) async -> [MTTVDBSeries]
    func queryEpisodes(seriesID: String, originalAirDate: String?, pageNumber: Int) async -> (episodes: [MTTVDBEpisode], hasMore: Bool)?
    func querySeriesArtwork(seriesID: String) async -> String?
    func querySeasonArtwork(seriesID: String, season: Int) async -> String?
    func saveToken() async -> Void
    func loadToken() async -> Void
}

public extension MTTVDBService {
    func titleURL(_ seriesTitle: String) -> String {
        // https://thetvdb.com/search?query=craig%20ferguson
        "https://thetvdb.com/search?query=\(seriesTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    }
    func idURL(_ id: String) -> String {
        // https://thetvdb.com/search?query=338736
        "https://thetvdb.com/search?query=\(id)"
    }
    func slugURL(_ slug: String) -> String {
        // https://thetvdb.com/series/craig-of-the-creek
        "https://thetvdb.com/series/\(slug)"
    }
    func seriesURL(_ series: MTTVDBSeries) -> String {
        slugURL(series.slug)
    }
    func seriesURLs(_ series: [MTTVDBSeries]) -> String {
        series.map({seriesURL($0)}).joined(separator: " OR ")
    }
    func queryEpisodes(seriesID: String, originalAirDate: String) async -> (episodes: [MTTVDBEpisode], hasMore: Bool)? {
        await queryEpisodes(seriesID: seriesID, originalAirDate: originalAirDate, pageNumber: 0)
    }
    func queryEpisodes(seriesID: String, pageNumber: Int) async -> (episodes: [MTTVDBEpisode], hasMore: Bool)? {
        await queryEpisodes(seriesID: seriesID, originalAirDate: nil, pageNumber: pageNumber)
    }
    func queryEpisodes(seriesID: String) async -> (episodes: [MTTVDBEpisode], hasMore: Bool)? {
        await queryEpisodes(seriesID: seriesID, originalAirDate: nil, pageNumber: 0)
    }
}

public typealias MTTVDBKeyProvider = () -> (key: String, pin: String?)

//
// Implementation of MTTVDBService
//

fileprivate func makeJSONRequest(url: String, token: String? = nil, data: Data? = nil) -> URLRequest? {
    guard let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        MTTVDBLogger.DDLogReport("Failed to encode \(url)")
        return nil
    }
    guard let requestURL = URL(string: encodedURL) else {
        MTTVDBLogger.DDLogReport("Failed to construct \(url)")
        return nil
    }
    var request = URLRequest(url: requestURL)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let data = data {
        request.httpMethod = "POST"
        request.httpBody = data
    }
    return request
}

//
// Next two functions only used with #available fallback prior to macOS 12.0
//

fileprivate func fetchTVDBDataResponse(with request: URLRequest, using session: URLSession, completionHandler: @escaping (Data?, URLResponse?) -> Void) {
    session.dataTask(with: request) { data, response, error in
                if let error = error {
                    MTTVDBLogger.DDLogReport("TVDB HTTP Request Error \(error): for \(String(describing: request.url))")
                    completionHandler(nil, nil)
                }
                completionHandler(data, response)
            }.resume()
}

fileprivate func fetchTVDBDataResponse(with request: URLRequest, using session: URLSession) async -> (Data?, URLResponse?) {
    await withCheckedContinuation { continuation in
        fetchTVDBDataResponse(with: request, using: session) { data, response in
            continuation.resume(returning: (data, response))
        }
    }
}

fileprivate func queryTVDBDataResponse(for request: URLRequest, using session: URLSession) async -> (Data?, URLResponse?) {
    let data: Data?, response: URLResponse?
    do {
        if #available(macOS 12.0, *) {
            (data, response) = try await session.data(for: request)
        } else {
            // Fallback on earlier versions
            (data, response) = await fetchTVDBDataResponse(with: request, using: session)
        }
    } catch {
        MTTVDBLogger.DDLogReport("TVDB HTTP Request Error \(error): for \(String(describing: request.url))")
        (data, response) = (nil, nil)
    }
    return (data, response)
}

fileprivate func decode<T: Decodable>(_ data: Data, url: String) -> T? {
    let decodedData: T
    do {
        decodedData = try JSONDecoder().decode(T.self, from: data)
    } catch {
        MTTVDBLogger.DDLogReport("TVDB JSON Decoding Error \(error): parsing JSON data (\(String(data: data, encoding: String.Encoding.utf8) ?? "")) for \(url)")
        return nil
    }
    MTTVDBLogger.DDLogVerbose("TVDB successfully parsed JSON data (\(String(data: data, encoding: String.Encoding.utf8) ?? "")) for \(url)")
    return decodedData
}

fileprivate protocol MTTVDBResponseV4: Decodable {
    var status: String? { get }
}

struct MTTVDBServiceV4: MTTVDBService {
    
    let apiBaseURLV4 = "https://api4.thetvdb.com/v4"

    let session: URLSession

    // Placeholder used by TVDB for missing artwork.
    private let missingArtwork = "https://artworks.thetvdb.com/banners/images/missing/series.jpg"

    // Replace missing artwork placeholder with empty string so that
    // downstream code can fall back to other options.  If other
    // placeholders are identified, modify this function
    private func filterMissingArtwork(_ artwork: String?) -> String? {
        missingArtwork == artwork ? "" : artwork
    }

    // The maximum number of series to be returned from the TVDB API
    let maxSeries = 10

    func querySeries(name: String) async -> [MTTVDBSeries] {
        let url = "\(apiBaseURLV4)/search?query=\(name)&type=series"
        let json: SearchResponseJSON? = await queryTVDBService(url: url)
        let series = json?.data ?? []
        return Array(series.map({
            SearchResponseJSON.SeriesJSON.init(
                    id: $0.id,
                    slug: $0.slug,
                    name: $0.name,
                    image: filterMissingArtwork($0.image)
            )
        }).prefix(maxSeries))
    }
    
    func queryEpisodes(seriesID: String, originalAirDate: String?, pageNumber: Int) async -> (episodes: [MTTVDBEpisode], hasMore: Bool)? {
        let airDateParam: String
        if let originalAirDate = originalAirDate {
            airDateParam = "&airDate=\(originalAirDate)"
        } else {
            airDateParam = ""
        }
        let url = "\(apiBaseURLV4)/series/\(seriesID)/episodes/default?page=\(pageNumber)\(airDateParam)"
        let json: EpisodeResponseJSON? = await queryTVDBService(url: url)
        guard let episodes = json?.data?.episodes else {
            return nil
        }
        let filteredEpisodes = episodes.map {
            EpisodeResponseJSON.DataJSON.EpisodeJSON.init(
                    id: $0.id,
                    name: $0.name,
                    season: $0.season,
                    number: $0.number,
                    image: filterMissingArtwork($0.image)
            )
        }
        // If next is not null, assume there are more available
        return (episodes: filteredEpisodes, hasMore: json?.links?.next != nil)
    }
    
    func querySeriesArtwork(seriesID: String) async -> String? {
        let url = "\(apiBaseURLV4)/series/\(seriesID)"
        let json: SeriesResponseJSON? = await queryTVDBService(url: url)
        return filterMissingArtwork(json?.data?.image)
    }
    
    func querySeasonArtwork(seriesID: String, season: Int) async -> String? {
        let url = "\(apiBaseURLV4)/series/\(seriesID)/extended?short=true"
        let json: SeriesResponseJSON? = await queryTVDBService(url: url)
        guard let seasons = json?.data?.seasons else {
            return nil
        }
        for seasonJSON in seasons {
            if (seasonJSON.number == season) {
                return filterMissingArtwork(seasonJSON.image)
            }
        }
        return nil
    }
    
    func saveToken() async {
        await authenticator.saveToken()
    }
    
    func loadToken() async {
        await authenticator.loadToken()
    }
    
    init(keyProvider: @escaping MTTVDBKeyProvider = keyProvider, session: URLSession = URLSession.shared) {
        self.session = session
        authenticator = MTTVDBAuthenticator(
                baseURL: apiBaseURLV4,
                duration: 30 * 24 * 60 * 60,
                keyProvider: keyProvider,
                session: session)
    }
    
    let authenticator: MTTVDBAuthenticator

    fileprivate func queryTVDBService<T: MTTVDBResponseV4>(url: String) async -> T? {
        guard let token = await authenticator.fetchToken() else {
            return nil
        }

        guard let request = makeJSONRequest(url: url, token: token) else {
            return nil
        }

        let (data, response) = await queryTVDBDataResponse(for: request, using: session)

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        if statusCode == 401 {
            MTTVDBLogger.DDLogReport("TVDB Discarding Unauthorized Token \(token): for \(request.url?.absoluteString ?? "")")
            await authenticator.discardThisToken(token)
            return nil
        } else if statusCode != 200 {
            MTTVDBLogger.DDLogReport("TVDB HTTP Response Status Code Error \(statusCode ?? 0): for \(request.url?.absoluteString ?? "")")
            return nil
        }

        guard let data = data else {
            return nil
        }

        let result: T? = decode(data, url: request.url?.absoluteString ?? "")

        guard result?.status == "success" else {
            // The response failed to explicitly indicate success, log it and discard response
            MTTVDBLogger.DDLogVerbose("TVDB Did Not Return Status Success (\(String(describing: response))): for \(request.url?.absoluteString ?? "")")
            MTTVDBLogger.DDLogReport("TVDB Did Not Return Status Success: for \(request.url?.absoluteString ?? "")")
            return nil
        }

        return result
    }
    
    struct SearchResponseJSON: Decodable, MTTVDBResponseV4 {
        struct SeriesJSON: Decodable, MTTVDBSeries {
            enum CodingKeys: String, CodingKey {
                case id = "tvdb_id"
                case slug
                case name
                case image = "image_url"
            }
            let id: String
            let slug: String
            let name: String?
            let image: String?
        }
        let status: String?
        let data: [SeriesJSON]?
    }
    
    struct EpisodeResponseJSON: Decodable, MTTVDBResponseV4 {
        struct DataJSON: Decodable {
            struct EpisodeJSON: Decodable, MTTVDBEpisode {
                enum CodingKeys: String, CodingKey {
                    case id
                    case name
                    case season = "seasonNumber"
                    case number
                    case image
                }
                let id: Int
                let name: String?
                let season: Int?
                let number: Int?
                let image: String?
            }
            let episodes: [EpisodeJSON]?
        }
        struct Links: Decodable {
            let next: String?
        }
        let status: String?
        let data: DataJSON?
        let links: Links?
    }
    
    struct SeriesResponseJSON: Decodable, MTTVDBResponseV4 {
        struct DataJSON: Decodable {
            struct SeasonJSON: Decodable {
                let number: Int?
                let image: String?
            }
            let image: String?
            let seasons: [SeasonJSON]?
        }
        let status: String?
        let data: DataJSON?
    }
    
    // Inject replacement date provider when testing expiration times
    func setDateProvider(_ dateProvider: @escaping () -> Date) async {
        await authenticator.setDateProvider(dateProvider)
    }
}

fileprivate protocol MTVDBTokenJSON {
    func fetchToken() -> String?
}

actor MTTVDBAuthenticator {
    let session: URLSession

    init(baseURL: String, duration: TimeInterval, keyProvider: @escaping MTTVDBKeyProvider, session: URLSession = URLSession.shared) {
        self.duration = duration
        self.keyProvider = keyProvider
        self.session = session
        tokenUrl = "\(baseURL)/login"
    }

    func fetchToken() async -> String? {
        if let token = token, let expiration = expiration, expiration > dateProvider() {
                // Current token is good
            MTTVDBLogger.DDLogVerbose("Using existing TVDB token")
                return token
        }

        MTTVDBLogger.DDLogVerbose("Fetching new TVDB token")
        
        let (key, pin) = keyProvider()
        
        let requestData: Data
        if pin == nil {
            requestData = try! JSONEncoder().encode(["apikey": key])
        } else {
            requestData = try! JSONEncoder().encode(["apikey": key, "pin": pin])
        }
        
        guard let request = makeJSONRequest(url: tokenUrl, data: requestData) else {
            return nil
        }
        
        let (data, response) = await queryTVDBDataResponse(for: request, using: session)

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        if statusCode != 200 {
            MTTVDBLogger.DDLogReport("TVDB Invalid Authentication Credentials \(statusCode ?? 0): for \(request.url?.absoluteString ?? "")")
            return nil
        }
        guard let data = data else { return  nil }

        let json: TokenJSONV4? = decode(data, url: "authentication request to \(tokenUrl)")

        token = json?.fetchToken()
        expiration = dateProvider().addingTimeInterval(duration)
        return token
    }

    struct TokenJSONV4: Decodable, MTVDBTokenJSON {
        struct DataJSON: Decodable {
            let token: String
        }
        let data: DataJSON?
        func fetchToken() -> String? {
            data?.token
        }
    }

    func discardThisToken(_ token: String) -> Void {
        if token == self.token {
            discardCurrentToken()
        }
    }

    func discardCurrentToken() -> Void {
        token = nil
        expiration = nil
    }
    
    // Key when persisting token and expiration date to UserDefaults
    // Specifically does not match kMTTVDBToken and kMTTVDBTokenExpire
    // keys previously removed from MTConstants.h to allow moving
    // back and forth between V3 and V4-enabled versions of cTiVo.
    static let userDefaultsTokenKey = "TVDBTokenV4"
    static let userDefaultsTokenExpireKey = "TVDBTokenV4Expire"

    func saveToken() {
        UserDefaults.standard.set(token, forKey: MTTVDBAuthenticator.userDefaultsTokenKey)
        UserDefaults.standard.set(expiration, forKey: MTTVDBAuthenticator.userDefaultsTokenExpireKey)

    }

    func loadToken() {
        token = UserDefaults.standard.object(forKey: MTTVDBAuthenticator.userDefaultsTokenKey) as? String
        expiration = UserDefaults.standard.object(forKey: MTTVDBAuthenticator.userDefaultsTokenExpireKey) as? Date
    }

    private let duration: TimeInterval
    private let keyProvider: MTTVDBKeyProvider
    private let tokenUrl: String
    private var expiration: Date?
    private var token: String?
    
    // Inject replacement date provider when testing expiration times
    private var dateProvider: () -> Date = Date.init
    func setDateProvider(_ dateProvider: @escaping () -> Date) {
        self.dateProvider = dateProvider
    }
}

fileprivate func keyProvider() -> (key: String, pin: String?) {
    let base = "37de-4890f99a2-64fc-44d3-ba49-2c06ad29ddbc7-ad27"
    return (key: String(base.suffix(42).prefix(36)), pin: nil)
}
