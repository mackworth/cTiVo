//
//  MTTVDBCache.swift
//  cTiVo
//
//  Created by Steve Schmadeke on 7/31/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import Foundation

actor MTTVDBCache {

    private var series: [String: String] = [:]
    private var slug: [String: String] = [:]
    private var episodeArtwork: [String: String] = [:]
    private var seasonArtwork: [String: String] = [:]
    private var seriesArtwork: [String: String] = [:]
    private var episode: [String: Int] = [:]
    private var season: [String: Int] = [:]
    private var possibleIds: [String: [String]] = [:]
    private var possibleSlugs: [String: [String]] = [:]
    private var status: [String: Status] = [:]
    private var date: [String: Date] = [:]

    // Required until Swift supports async property accessors
    func getSeries(_ episodeID: String) -> String? { series[episodeID] }
    func setSeries(_ episodeID: String, series: String?) { self.series[episodeID] = series }
    func getSlug(_ episodeID: String) -> String? { slug[episodeID] }
    func setSlug(_ episodeID: String, slug: String?) { self.slug[episodeID] = slug }
    func getEpisodeArtwork(_ episodeID: String) -> String? { episodeArtwork[episodeID] }
    func setEpisodeArtwork(_ episodeID: String, episodeArtwork: String?) { self.episodeArtwork[episodeID] = episodeArtwork }
    func getSeasonArtwork(_ episodeID: String) -> String? { seasonArtwork[episodeID] }
    func setSeasonArtwork(_ episodeID: String, seasonArtwork: String?) { self.seasonArtwork[episodeID] = seasonArtwork }
    func getSeriesArtwork(_ episodeID: String) -> String? { seriesArtwork[episodeID] }
    func setSeriesArtwork(_ episodeID: String, seriesArtwork: String?) { self.seriesArtwork[episodeID] = seriesArtwork }
    func getEpisode(_ episodeID: String) -> Int? { episode[episodeID] }
    func setEpisode(_ episodeID: String, episode: Int?) { self.episode[episodeID] = episode }
    func getSeason(_ episodeID: String) -> Int? { season[episodeID] }
    func setSeason(_ episodeID: String, season: Int?) { self.season[episodeID] = season }
    func getPossibleIds(_ episodeID: String) -> [String]? { possibleIds[episodeID] }
    func setPossibleIds(_ episodeID: String, possibleIds: [String]?) { self.possibleIds[episodeID] = possibleIds }
    func getPossibleSlugs(_ episodeID: String) -> [String]? { possibleSlugs[episodeID] }
    func setPossibleSlugs(_ episodeID: String, possibleSlugs: [String]?) { self.possibleSlugs[episodeID] = possibleSlugs }
    func getStatus(_ episodeID: String) -> Status? { status[episodeID] }
    func setStatus(_ episodeID: String, status: Status?) { self.status[episodeID] = status }

    func getAll(_ episodeID: String) -> (
            series: String?,
            slug: String?,
            episodeArtwork: String?,
            seasonArtwork: String?,
            seriesArtwork: String?,
            episode: Int?,
            season: Int?,
            possibleIds: [String]?,
            possibleSlugs: [String]?,
            status: Status?
    ) {
        (
                series[episodeID],
                slug[episodeID],
                episodeArtwork[episodeID],
                seasonArtwork[episodeID],
                seriesArtwork[episodeID],
                episode[episodeID],
                season[episodeID],
                possibleIds[episodeID],
                possibleSlugs[episodeID],
                status[episodeID]
        )
    }

    // Set all of the properties for an episode at the same time, discarding
    // any existing property values and also timestamping the episode for
    // cache expiration management.
    func setAll(
            _ episodeID: String,
            series: String? = nil,
            slug: String? = nil,
            episodeArtwork: String? = nil,
            seasonArtwork: String? = nil,
            seriesArtwork: String? = nil,
            episode: Int? = nil,
            season: Int? = nil,
            possibleIds: [String]? = nil,
            possibleSlugs: [String]? = nil,
            status: Status? = nil
    ) {
        self.series[episodeID] = series
        self.slug[episodeID] = slug
        self.episodeArtwork[episodeID] = episodeArtwork
        self.seasonArtwork[episodeID] = seasonArtwork
        self.seriesArtwork[episodeID] = seriesArtwork
        self.episode[episodeID] = episode
        self.season[episodeID] = season
        self.possibleIds[episodeID] = possibleIds
        self.possibleSlugs[episodeID] = possibleSlugs
        self.status[episodeID] = status
        date[episodeID] = dateProvider()
    }

    // All episode IDs with populated values in cache
    var episodeIDs: [String] {
        Array(Set(date.keys)
                .union(series.keys)
                .union(slug.keys)
                .union(episodeArtwork.keys)
                .union(seasonArtwork.keys)
                .union(seriesArtwork.keys)
                .union(episode.keys)
                .union(season.keys)
                .union(possibleIds.keys)
                .union(possibleSlugs.keys)
                .union(status.keys))
    }

    // Safe because the dictionaries are value objects
    func getDictionary(_ episodeID: String, forPersisting: Bool = false) -> [String:AnyObject]? {
        var tvdbData: [String:AnyObject] = [:]
        if let series = series[episodeID] {
            tvdbData[Key.series.rawValue] = series as AnyObject
        }
        if let slug = slug[episodeID] {
            tvdbData[Key.slug.rawValue] = slug as AnyObject
        }
        if let episodeArtwork = episodeArtwork[episodeID] {
            tvdbData[Key.episodeArtwork.rawValue] = episodeArtwork as AnyObject
        }
        if let seasonArtwork = seasonArtwork[episodeID] {
            tvdbData[Key.seasonArtwork.rawValue] = seasonArtwork as AnyObject
        }
        if let seriesArtwork = seriesArtwork[episodeID] {
            tvdbData[Key.seriesArtwork.rawValue] = seriesArtwork as AnyObject
        }
        if let episode = episode[episodeID] {
            tvdbData[Key.episode.rawValue] = String(episode) as AnyObject
        }
        if let season = season[episodeID] {
            tvdbData[Key.season.rawValue] = String(season) as AnyObject
        }
        if let possibleIds = possibleIds[episodeID] {
            tvdbData[Key.possibleIds.rawValue] = possibleIds as AnyObject
        }
        if let possibleSlugs = possibleSlugs[episodeID] {
            tvdbData[Key.possibleSlugs.rawValue] = possibleSlugs as AnyObject
        }
        if forPersisting {
            // Encode all of the cached information for the episode,
            // not just the values intended for external use outside
            // of the MTTVDBOriginal class.

            if let status = status[episodeID] {
                tvdbData[Key.status.rawValue] = status.rawValue as AnyObject
            }

            // Populate a date property if none already exists
            date[episodeID] = date[episodeID] ?? dateProvider()
            tvdbData[Key.date.rawValue] = date[episodeID] as? AnyObject
        }
        return tvdbData.count > 0 ? tvdbData : nil
    }

    func getDictionary() -> [String:[String:AnyObject]] {
        let keys = episodeIDs
        let values = keys.map { getDictionary($0, forPersisting: true) ?? [:] }
        return Dictionary(uniqueKeysWithValues: zip(keys, values))
    }

    func reset(_ episodeID: String) {
        setAll(episodeID)
        date[episodeID] = nil
    }

    func reset() {
        series = [:]
        slug = [:]
        episodeArtwork = [:]
        seasonArtwork = [:]
        seriesArtwork = [:]
        episode = [:]
        season = [:]
        possibleIds = [:]
        possibleSlugs = [:]
        status = [:]
        date = [:]
    }

    // Remove all episodes that were last updated over 30 days ago and
    // all episodes without a series IO that were last updated over a
    // day ago.  (The latter category will get purged earlier, even if
    // they aren't specifically marked with Status.notFound).
    func cleanCache() {
        episodeIDs.forEach { episodeID in
            let lastUpdate = date[episodeID] ?? Date.distantPast
            let expirationDays = series[episodeID] != nil ? 30 : 1 as TimeInterval
            if lastUpdate.addingTimeInterval(expirationDays * 24 * 60 * 60) < dateProvider() {
                reset(episodeID)
            }
        }
    }

    // Key when persisting cached data to UserDefaults
    // Matches kMTTheTVDBCache in MTConstants.h
    static let userDefaultsKey = "TVDBLocalCache"

    func saveCache() {
        UserDefaults.standard.set(getDictionary() as NSDictionary, forKey: MTTVDBCache.userDefaultsKey)
    }

    func loadCache() {
        let defaults = UserDefaults.standard.object(forKey: MTTVDBCache.userDefaultsKey) as? [String:[String:AnyObject]] ?? [:]
        defaults.forEach { episodeID, value in
            series[episodeID] = value[Key.series.rawValue] as? String ?? nil
            slug[episodeID] = value[Key.slug.rawValue] as? String ?? nil
            episodeArtwork[episodeID] = value[Key.episodeArtwork.rawValue] as? String ?? nil
            seasonArtwork[episodeID] = value[Key.seasonArtwork.rawValue] as? String ?? nil
            seriesArtwork[episodeID] = value[Key.seriesArtwork.rawValue] as? String ?? nil
            if let episode = value[Key.episode.rawValue] as? String {
                self.episode[episodeID] = Int(episode)
            }
            if let season = value[Key.season.rawValue] as? String {
                self.season[episodeID] = Int(season)
            }
            possibleIds[episodeID] = value[Key.possibleIds.rawValue] as? [String] ?? nil
            possibleSlugs[episodeID] = value[Key.possibleSlugs.rawValue] as? [String] ?? nil
            if let status = value[Key.status.rawValue] as? String {
                self.status[episodeID] = Status(rawValue: status)
            }
            date[episodeID] = value[Key.date.rawValue] as? Date ?? dateProvider()
        }
    }

    // Inject replacement date provider when testing expiration times
    private var dateProvider: () -> Date = Date.init
    func setDateProvider(_ dateProvider: @escaping () -> Date) {
        self.dateProvider = dateProvider
    }

    enum Status: String {
        case inProgress    // Started search
        case notFound      // Completed search, but no matches found
        case found         // Completed search, found match
    }

    enum Key: String {
        // Keys exposed to external code in MTConstants.h
        //
        // These keys are used by external code to retrieve properties from
        // the MTTiVoShow.tvdbData dictionary populated by the MTTVDB class.
        // The raw values of this enumeration must match the corresponding
        // #define macros found in MTConstants.h.
        //
        case series            // TVDB Series ID <String>
        case slug              // Path segment of TVDB URL for series <String>
        case episodeArtwork    // URL for episode artwork at TVDB <String>
        case seasonArtwork     // URL for season artwork at TVDB <String>
        case seriesArtwork     // URL for series artwork at TVDB <String>
        case episode           // Episode number <String>
        case season            // Season number <String>
        case possibleIds       // IDs that we checked to find series <[String]>
        case possibleSlugs     // Slugs for series we checked to find episode <[String]>

        // Internal key limited to scope of MTTVDB class.
        case status            // Status of search for episode <Status>

        // Internal key not intended for use outside of cache
        case date              // Time of last update <Date>
    }
}