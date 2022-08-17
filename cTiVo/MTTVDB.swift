//
//  MTTVDB.swift
//  cTiVo
//
//  Created by Hugh Mackworth on 6/8/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import Foundation

@objc
public protocol MTTiVoShowReadOnly {
    var episodeID: String { get }
    var seriesTitle: String  { get }
    var isEpisodicShow: Bool  { get }
    var episodeTitle: String  { get }
    var manualSeasonInfo: Bool { get }
    var season: Int { get }
    var episode: Int { get }
    var originalAirDateNoTime: String  { get }
    var movieYear: String { get }
    var tvdbData: NSDictionary?  { get }
}

enum MTTVDBStatisticsCountKey: String {
    case all
    case movie
    case movieFound
    case movieFoundCached
    case nonEpisodicSeriesFound
    case nonEpisodicSeriesFoundCached
    case seriesEpisodeFound
    case seriesEpisodeFoundCached
}

enum MTTVDBStatisticsListKey: String {
    case movieNotFound
    case movieNotFoundCached
    case episodeNotFound
    case episodeNotFoundCached
    case episodicSeriesNotFound
    case episodicSeriesNotFoundCached
    case nonEpisodicSeriesNotFound
    case nonEpisodicSeriesNotFoundCached
}

actor MTTVDBStatistics {
    private var counts: [MTTVDBStatisticsCountKey: Int] = [:]
    private var lists: [MTTVDBStatisticsListKey: [String:String]] = [:]
    private var listCounts: [MTTVDBStatisticsListKey: Int] = [:]
    func increment(_ key: MTTVDBStatisticsCountKey) {
        counts[key] = (counts[key] ?? 0) + 1
    }
    func set(_ value: String, forKey key: MTTVDBStatisticsListKey, forShow: String) {
        listCounts[key] = (listCounts[key] ?? 0) + 1
        var statistic = lists[key] ?? [:]
        statistic[forShow] = value
        lists[key] = statistic
    }
    func val(_ keys: MTTVDBStatisticsCountKey...) -> Int {
        keys.reduce(0) { $0 + (counts[$1] ?? 0)}
    }
    func val(_ keys: MTTVDBStatisticsListKey...) -> Int {
        keys.reduce(0) { $0 + (listCounts[$1] ?? 0)}
    }
    func percent(_ cached: Int, _ notCached: Int) -> String {
        cached + notCached > 0 ? String(format: "%0.0f%%", 100.0 * Double(cached) / (Double(cached) + Double(notCached))) : "0%"
    }
    func percent(_ cached: MTTVDBStatisticsCountKey, _ notCached: MTTVDBStatisticsCountKey) -> String {
        percent(val(cached), val(notCached))
    }
    func percent(_ cached: MTTVDBStatisticsListKey, _ notCached: MTTVDBStatisticsListKey) -> String {
        percent(val(cached), val(notCached))
    }
    func list(_ key: MTTVDBStatisticsListKey, purgeKey: MTTVDBStatisticsListKey? = nil) -> String {
        if var list = lists[key] {
            if let purgeKey = purgeKey {
                if let purgeList = lists[purgeKey] {
                    purgeList.keys.forEach { list[$0] = nil }
                }
            }
            if !list.isEmpty {
                return String(describing: list as NSDictionary)
            }
        }
        return "None"
    }
    func report() -> String {
        let valEpisodic =
                val(.seriesEpisodeFound, .seriesEpisodeFoundCached) +
                        val(.episodicSeriesNotFound, .episodicSeriesNotFoundCached) +
                        val(.episodeNotFound, .episodeNotFoundCached)
        let valNonEpisodic =
                val(.nonEpisodicSeriesFound, .nonEpisodicSeriesFoundCached) +
                        val(.nonEpisodicSeriesNotFound, .nonEpisodicSeriesNotFoundCached)
        return """

               \(kcTiVoName) looks up the TiVo's shows on theTVDB and the movies on theMovieDB.
               You can click on the individual URLs to see what information is available for shows that could not be found.

               Total number of shows is \(val(.all))
               \(val(.movie)) shows are marked as Movies
               \(valEpisodic) shows are marked as Episodic
               \(valNonEpisodic) shows are marked as Non-Episodic (e.g. news/sports events)

               \(kcTiVoName) caches information as possible; successful lookups for 30 days; unsuccessful for 1 day

               In the last group we looked up, we had the following results:
               Movies:
                  \(val(.movieFound, .movieFoundCached)) movies found (cached: \(percent(.movieFoundCached, .movieFound)))
                  \(val(.movieNotFound, .movieNotFoundCached)) movies not found (cached: \(percent(.movieNotFoundCached, .movieNotFound)))

               Episodic:
                  \(val(.seriesEpisodeFound, .seriesEpisodeFoundCached)) shows found (cached: \(percent(.seriesEpisodeFoundCached, .seriesEpisodeFound)))
                  \(val(.episodeNotFound, .episodeNotFoundCached)) series found, but episodes not found (cached: \(percent(.episodeNotFoundCached, .episodeNotFound)))
                  \(val(.episodicSeriesNotFound, .episodicSeriesNotFoundCached)) series not found (cached: \(percent(.episodicSeriesNotFoundCached, .episodicSeriesNotFound)))

               Non-Episodic:
                  \(val(.nonEpisodicSeriesFound, .nonEpisodicSeriesFoundCached)) shows found (cached: \(percent(.nonEpisodicSeriesFoundCached, .nonEpisodicSeriesFound)))
                  \(val(.nonEpisodicSeriesNotFound, .nonEpisodicSeriesNotFoundCached)) series not found (cached: \(percent(.nonEpisodicSeriesNotFoundCached, .nonEpisodicSeriesNotFound)))

               Here are the shows that had issues:
               Movies not Found at theMovieDB
               \(list(.movieNotFound))

               Movies not Found (Cached)
               \(list(.movieNotFoundCached, purgeKey: .movieNotFound))

               Episodic Series not Found at TVDB
               \(list(.episodicSeriesNotFound))

               Episodic Series not Found (Cached)
               \(list(.episodicSeriesNotFoundCached, purgeKey: .episodicSeriesNotFound))

               Episodic Series Found, but episodes not found at TVDB
               \(list(.episodeNotFound))

               Episodic Series Found, but episodes not found (Cached)
               \(list(.episodeNotFoundCached, purgeKey: .episodeNotFound))

               Non-Episodic Series not Found at TVDB
               \(list(.nonEpisodicSeriesNotFound))

               Non-Episodic Series not Found (Cached)
               \(list(.nonEpisodicSeriesNotFoundCached, purgeKey: .nonEpisodicSeriesNotFound))

               """
    }
    func reset() -> Void {
        counts = [:]
        lists = [:]
        listCounts = [:]
    }
}

actor MTTVDBSimpleCache<K: Hashable, V> {
    private var cache: [K: V] = [:]
    func get(_ key: K) -> V? {
        cache[key]
    }
    func set(_ value: V?, forKey key: K) -> Void {
        cache[key] = value
    }
    func reset() -> Void {
        cache = [:]
    }
}

public class MTTVDB : NSObject {
    // Support injection for unit testing
    var tvdbService: MTTVDBService = MTTVDBServiceV4()
    var tvdbMovieService: MTTVDBMovieService = MTTVDBMovieServiceV3()

    // Accumulated TVDB data for each show (using episodeID as the key)
    private let tvdbCache = MTTVDBCache()

    // Map of series title -> list of TVDB series IDs
    private let seriesCache: MTTVDBSimpleCache<String, [MTTVDBSeries]> = MTTVDBSimpleCache()

    // Accumulated statistics for TVDB processing
    private let tvdbStatistics = MTTVDBStatistics()

    override init() {
        super.init()
        loadDefaults()
    }

    private func tvdbPossibleIdsURLs(_ possibleIds: [String]) -> String {
        possibleIds.map({tvdbService.idURL($0)}).joined(separator: " OR ")
    }

    private func tvdbPossibleSlugsURLs(_ possibleSlugs: [String]) -> String {
        possibleSlugs.map({tvdbService.slugURL($0)}).joined(separator: " OR ")
    }

    private func tvdbPossibleURLs(possibleSlugs: [String], possibleIds: [String]) -> String {
        // Use slugs unless more series IDs are available (which will
        // only happen when migrating older cached shows who don't have
        // slug information available)
        possibleSlugs.count >= possibleIds.count ? tvdbPossibleSlugsURLs(possibleSlugs) : tvdbPossibleIdsURLs(possibleIds)
    }

    @objc public func getTheTVDBDetails(_ show: MTTiVoShowReadOnly, reset: Bool = false) async -> NSDictionary {

        if reset {
            MTTVDBLogger.DDLogDetail("Resetting information for \(show.seriesTitle) (\(show.episodeID))")
            _ = await [
                tvdbCache.reset(show.episodeID),
                seriesCache.set(nil, forKey: show.seriesTitle)
            ]
        } else if let tvdbData = show.tvdbData {
            // The show has already been processed at least once since the
            // application was started up.  Nothing further needs to be done.
            return tvdbData
        }
        await tvdbStatistics.increment(.all)

        // Check for cached information from a previous run.
        let status = await tvdbCache.getStatus(show.episodeID)

        switch status {
        case .found:
            if show.isEpisodicShow {
                await tvdbStatistics.increment(.seriesEpisodeFoundCached)
            } else {
                await tvdbStatistics.increment(.nonEpisodicSeriesFoundCached)
            }

            if await seriesCache.get(show.seriesTitle) == nil {
                // This was the first time the series has been encountered
                // since the TVDB data cache was reloaded at startup.  Add
                // the series ID to the series cache.
                if let seriesID = await tvdbCache.getSeries(show.episodeID),
                   let slug = await tvdbCache.getSlug(show.episodeID)
                {
                    // Note: it should never be possible for the status
                    // to be found for a show without the series ID, but
                    // it is possible that the slug wasn't restored from a
                    // older version of user defaults.
                    struct RestoredSeries: MTTVDBSeries {
                        let id: String
                        let slug: String
                        let name: String?
                        let image: String?
                        init (id: String, slug: String, name: String? = nil, image: String? = nil) {
                            self.id = id
                            self.slug = slug
                            self.name = name
                            self.image = image
                        }
                    }
                    let image = await tvdbCache.getSeriesArtwork(show.episodeID)
                    await seriesCache.set([RestoredSeries(id: seriesID, slug: slug, name: show.seriesTitle, image: image)], forKey: show.seriesTitle)
                }
            }
        case .notFound:
            if let possibleSlugs = await tvdbCache.getPossibleSlugs(show.episodeID) {
                // Must be an episodic show that failed to find an episode
                await tvdbStatistics.set(
                        "Date: \(show.originalAirDateNoTime), URLs: \(tvdbPossibleSlugsURLs(possibleSlugs))",
                        forKey: .episodeNotFoundCached,
                        forShow: show.seriesTitle)
            } else if let possibleIDs = await tvdbCache.getPossibleIds(show.episodeID) {
                // Can only happen in the transition time before all of the
                // older shows without slug information expire in the cache
                await tvdbStatistics.set(
                        "Date: \(show.originalAirDateNoTime), URLs: \(tvdbPossibleIdsURLs(possibleIDs))",
                        forKey: .episodeNotFoundCached,
                        forShow: show.seriesTitle)
            } else {
                // Could be either non-episodic show or episodic show that had no matching candidate series
                await tvdbStatistics.set(tvdbService.titleURL(show.seriesTitle),
                        forKey: show.isEpisodicShow ? .episodicSeriesNotFoundCached : .nonEpisodicSeriesNotFoundCached,
                        forShow: show.seriesTitle)
            }
        default:
            await getTVDBData(show)
        }

        return await (tvdbCache.getDictionary(show.episodeID) ?? [:]) as NSDictionary
    }

    /// Fetch the  series, episode and artwork information for the TiVo show
    /// from TVDB and place it into the cache.
    ///
    /// At the time this function is called, either
    ///
    ///    1) show has never been searched for previously, or
    ///    2) previously-cached show information has been expired from cache, or
    ///    3) search had been started for show, but was still in progress at previous shutdown.
    ///
    /// The function will start by marking the show initially as being
    /// in progress and then will proceed to fetch the data as needed
    /// from TVDB.   At the completion of this function, all of the data
    /// will be in the cache (and timestamped for expiration) and the
    /// status of the show will be marked as either found or not found.
    /// The stats and the series cache also get updated as necessary.
    private func getTVDBData(_ show: MTTiVoShowReadOnly) async -> Void {
        MTTVDBLogger.DDLogDetail("Need to get \(show.seriesTitle) (\(show.episodeID))")
        await tvdbCache.setStatus(show.episodeID, status: .inProgress)

        let series = await getSeries(show.seriesTitle, bestMatches: show.isEpisodicShow ? matchesSeriesName : nil)

        if let firstSeries = series.first {
            if show.isEpisodicShow {
                if let (series, episode) = await getEpisode(
                        name: show.episodeTitle,
                        season: show.manualSeasonInfo ? show.season : 0,
                        number: show.manualSeasonInfo ? show.episode : 0,
                        series: series,
                        onAirDate: show.originalAirDateNoTime
                ) {
                    if let image = episode.image {
                        MTTVDBLogger.DDLogDetail("TVDB Episode Artwork for \(show.seriesTitle) (\(show.episodeID)) at \(image)")
                    }
                    if let image = series.image {
                        MTTVDBLogger.DDLogDetail("TVDB Series Artwork for \(show.seriesTitle) (\(show.episodeID)) at \(image)")
                    }
                    if episode.image == "" {
                        MTTVDBLogger.DDLogDetail("Discarded placeholder for missing TVDB Episode Artwork for \(show.seriesTitle) (\(show.episodeID))")
                    }
                    if series.image == "" {
                        MTTVDBLogger.DDLogDetail("Discarded placeholder for missing TVDB Series Artwork for \(show.seriesTitle) (\(show.episodeID))")
                    }
                    MTTVDBLogger.DDLogVerbose("Got TVDB episodeInfo for \(show.seriesTitle) (\(show.episodeID))")
                    await tvdbStatistics.increment(.seriesEpisodeFound)
                    // Remember the one that worked, forget all of the others
                    await seriesCache.set([series], forKey: show.seriesTitle)
                    await tvdbCache.setAll(
                            show.episodeID,
                            series: series.id,
                            slug: series.slug,
                            episodeArtwork: episode.image ?? "",
                            seriesArtwork: series.image,
                            episode: episode.number,
                            season: episode.season,
                            status: .found)
                } else {
                    let urls = tvdbService.seriesURLs(series)
                    MTTVDBLogger.DDLogDetail("TVDB does not have episodeInfo for \(show.seriesTitle) (\(show.episodeID)) on \(show.originalAirDateNoTime) (\(urls)")
                    await tvdbStatistics.set("Date: \(show.originalAirDateNoTime), URLs: \(urls)",
                            forKey: .episodeNotFound,
                            forShow: show.seriesTitle)
                    await tvdbCache.setAll(
                            show.episodeID,
                            possibleIds: series.map({$0.id}),
                            possibleSlugs: series.map({$0.slug}),
                            status: .notFound)
                }
            } else {
                await tvdbStatistics.increment(.nonEpisodicSeriesFound)
                if (firstSeries.image == nil) {
                    MTTVDBLogger.DDLogDetail("No artwork for \(show.seriesTitle) (\(show.episodeID)) Series ID: \(firstSeries.id)")
                } else if firstSeries.image == "" {
                    MTTVDBLogger.DDLogDetail("Discarded placeholder for missing TVDB Series Artwork for \(show.seriesTitle) (\(show.episodeID))")
                }
                await tvdbCache.setAll(
                        show.episodeID,
                        series: firstSeries.id,
                        slug: firstSeries.slug,
                        seriesArtwork: firstSeries.image ?? "",
                        status: .found)
            }
        } else if show.isEpisodicShow {
            MTTVDBLogger.DDLogDetail("No series found for \(show.seriesTitle) (\(show.episodeID))")
            await tvdbStatistics.set(tvdbService.titleURL(show.seriesTitle),
                    forKey: .episodicSeriesNotFound,
                    forShow: show.seriesTitle)
            await tvdbCache.setAll(
                    show.episodeID,
                    episodeArtwork: "",
                    seasonArtwork: "",
                    seriesArtwork: "",
                    status: .notFound
            )
        } else {
            MTTVDBLogger.DDLogDetail("No series found for \(show.seriesTitle) (\(show.episodeID))")
            await tvdbStatistics.set(tvdbService.titleURL(show.seriesTitle),
                    forKey: .nonEpisodicSeriesNotFound,
                    forShow: show.seriesTitle)
            await tvdbCache.setAll(
                    show.episodeID,
                    seriesArtwork: "",
                    status: .notFound
            )
        }
    }

    /// Used to identify the best matching candidates in a list of series
    typealias BestSeriesMatcher = (_ seriesTitle: String, _ name: String?) -> Bool

    /// Return whether the TiVo series title matches the TVDB series name.
    ///
    /// The series names returned by the TVDB service may include a
    /// parenthetical year (e.g. "(2022)") at the end to distinguish
    /// between multiple series.  A series is considered to match if the
    /// TiVo series title matches the TVDB series name exactly or if the
    /// TVDB series name starts with the TiVo series title followed by " (".
    /// This is somewhat looser than matching against the full regular
    /// expression of " \\([0-9]+\\)$", but is more efficient and is
    /// still very unlikely to produce a false positive match.
    private func matchesSeriesName(_ seriesTitle: String, _ name: String?) -> Bool {
        guard let name = name else {
            return false
        }
        return seriesTitle == name || name.hasPrefix(seriesTitle + " (")
    }

    /// Find the list of series matching the series title for the TiVo show,
    /// either picking the list up from the cache or going to the TVDB
    /// service to find candidates (and placing those candidates into
    /// the cache).
    ///
    /// If a matcher is provided to identify the best matching series,
    /// the best matches will appear in the front of the returned list of
    /// candidates.  Otherwise, all candidates will be returned in the
    /// same order as provided by the TVDB service (which also does
    /// its best to put the best matches first in the list).
    ///
    /// The additional matcher is currently used only for episodic shows.
    private func getSeries(_ seriesTitle: String, bestMatches: BestSeriesMatcher? = nil) async -> [MTTVDBSeries] {
        if let cachedSeries = await seriesCache.get(seriesTitle) {
            return cachedSeries
        }

        let candidates = await tvdbService.querySeries(name: seriesTitle)

        var bestMatchingCandidates: [MTTVDBSeries] = []
        var otherCandidates: [MTTVDBSeries] = []

        candidates.forEach {
            if let matches = bestMatches {
                if matches(seriesTitle, $0.name) {
                    bestMatchingCandidates.append($0)
                } else {
                    otherCandidates.append($0)
                }
            } else {
                otherCandidates.append($0)
            }
        }

        let series = bestMatchingCandidates + otherCandidates

        // Cache the resulting list of series.
        await seriesCache.set(series, forKey: seriesTitle)
        return series
    }

    /// Go to the TVDB service to find a matching episode.
    ///
    /// When the TiVo records a dual episode, the episode title will
    /// contain the name of both episodes, separated by a semicolon.
    /// When attempting to match that TiVo show against the TVDB
    /// database, this function will use just the portion of the
    /// episode title before the semicolon.
    ///
    /// Any of these are considered a match:
    ///   1) TVDB episode name matches TiVo episode title
    ///   2) TVDB episode name matches portion of TiVo episode
    ///     title preceding semicolon
    ///   3) TVDB season and episode numbers match manual TiVo show values
    ///
    /// The function first searches for all episodes that aired on the TiVo
    /// original air date, iterating across all the pages of results and
    /// across all the possible series, if necessary, and returning the first
    /// episode that matches (along with the corresponding series).  If no
    /// episode matches, but at least one candidate episode did air on
    /// the original date, the function will return it.
    ///
    /// If no candidate episode aired on the TiVo original air date, the
    /// search will expand to all of the episodes for all of the possible
    /// series.
    ///
    /// If still no match is found, the function will return nil.
    private func getEpisode(name: String, season: Int, number: Int, series: [MTTVDBSeries], onAirDate: String?) async -> (series: MTTVDBSeries, episode: MTTVDBEpisode)? {

        func matches(name: String, season: Int, number: Int, episode: MTTVDBEpisode) -> Bool {
            let match: Bool
            if name == episode.name || season == episode.season && number == episode.number {
                match = true
            } else {
                match = name.components(separatedBy: ";")[0] == episode.name
            }
            return match
        }

        if let airDate = onAirDate {
            var candidate: (series: MTTVDBSeries, episode: MTTVDBEpisode)? = nil
            for series in series {
                var pageNumber = 0
                var morePages = false
                repeat {
                    guard let (episodes, hasMore) = await tvdbService.queryEpisodes(seriesID: series.id, originalAirDate: airDate, pageNumber: pageNumber) else {
                        continue
                    }
                    for episode in episodes {
                        if candidate == nil {
                            // First episode airing on TiVo original air date
                            candidate = (series: series, episode: episode)
                        }
                        if matches(name: name, season: season, number: number, episode: episode) {
                            return (series: series, episode: episode)
                        }
                    }
                    morePages = hasMore
                    pageNumber += 1
                } while morePages
            }
            if let candidate = candidate {
                return candidate
            }
        }

        for series in series {
            var pageNumber = 0
            var morePages = false

            repeat {
                guard let (episodes, hasMore) = await tvdbService.queryEpisodes(seriesID: series.id, pageNumber: pageNumber) else {
                    continue
                }

                for episode in episodes {
                    if matches(name: name, season: season, number: number, episode: episode) {
                        return (series: series, episode: episode)
                    }
                }
                morePages = hasMore
                pageNumber += 1
            } while morePages
        }

        return nil
    }

    @objc public func getTheMovieDBDetails(_ show: MTTiVoShowReadOnly, reset: Bool = false) async -> NSDictionary {

        if reset {
            _ = await [
                tvdbCache.reset(show.episodeID),
                seriesCache.set(nil, forKey: show.seriesTitle)]
        } else if let tvdbData = show.tvdbData {
            // The show has already been processed at least once since the
            // application was started up.  Nothing further needs to be done.
            return tvdbData
        }

        func matches(movie: MTTVDBMovie, show: MTTiVoShowReadOnly, exact: Bool = false) -> Bool {
            guard let posterPath = movie.posterPath else { return false }
            let titlesMatch = show.seriesTitle.caseInsensitiveCompare(movie.title ?? "") == .orderedSame
            let releaseYear = movie.releaseDate?.prefix(4)
            let releaseMatch = releaseYear == nil || show.movieYear == releaseYear ?? "No Match"
            return posterPath.count > 0 && ((exact && titlesMatch && releaseMatch) || (!exact && (titlesMatch || releaseMatch)))
        }

        await tvdbStatistics.increment(.all)
        await tvdbStatistics.increment(.movie)

        switch await tvdbCache.getStatus(show.episodeID) {
        case .found:
            await tvdbStatistics.increment(.movieFoundCached)
        case .notFound:
            await tvdbStatistics.set(tvdbMovieService.lookupURL(name: show.seriesTitle), forKey: .movieNotFoundCached, forShow: show.seriesTitle)
        default:
            await tvdbCache.setStatus(show.episodeID, status: .inProgress)

            MTTVDBLogger.DDLogDetail("Getting movie Data for \(show.seriesTitle) (\(show.episodeID)) using \(tvdbMovieService.reportURL(name: show.seriesTitle))")
            let movies = await tvdbMovieService.queryMovie(name: show.seriesTitle)

            let exactMatches = movies.filter { matches(movie: $0, show: show, exact: true) }
            let inexactMatches = movies.filter { matches(movie: $0, show: show) }

            if let posterPath = (exactMatches + inexactMatches).first?.posterPath {
                MTTVDBLogger.DDLogDetail("For movie \(show.seriesTitle) (\(show.episodeID)), theMovieDB had image \(posterPath)")
                await tvdbStatistics.increment(.movieFound)
                await tvdbCache.setAll(show.episodeID, seriesArtwork: posterPath, status: .found)
            } else {
                MTTVDBLogger.DDLogMajor("theMovieDB does not have any images for \(show.seriesTitle) (\(show.episodeID))")
                await tvdbStatistics.set(tvdbMovieService.lookupURL(name: show.seriesTitle), forKey: .movieNotFound, forShow: show.seriesTitle)
                await tvdbCache.setAll(show.episodeID, seriesArtwork: "", status: .notFound)
            }
        }

        return await (tvdbCache.getDictionary(show.episodeID) ?? [:]) as NSDictionary
    }

    @objc public func addSeriesArtwork(_ show: MTTiVoShowReadOnly) async -> NSDictionary {
        let status = await tvdbCache.getStatus(show.episodeID)
        if status == .found || status == .notFound {
            if await tvdbCache.getSeriesArtwork(show.episodeID) == nil {
                if let seriesID = await tvdbCache.getSeries(show.episodeID) {
                    if let seriesArtwork = await tvdbService.querySeriesArtwork(seriesID: seriesID) {
                        if seriesArtwork == "" {
                            MTTVDBLogger.DDLogDetail("Discarding placeholder for missing TVDB series artwork for \(show.seriesTitle) (\(show.episodeID))")
                        } else {
                            MTTVDBLogger.DDLogDetail("Found series artwork for \(show.seriesTitle) (\(show.episodeID)): \(seriesArtwork)")
                        }
                        await tvdbCache.setSeriesArtwork(show.episodeID, seriesArtwork: seriesArtwork)
                    } else {
                        MTTVDBLogger.DDLogDetail("No series artwork for \(show.seriesTitle) (\(show.episodeID))")
                        await tvdbCache.setSeriesArtwork(show.episodeID, seriesArtwork: "")
                    }
                } else {
                    MTTVDBLogger.DDLogDetail("No series ID when adding series artwork for \(show.seriesTitle) (\(show.episodeID))")
                    await tvdbCache.setSeriesArtwork(show.episodeID, seriesArtwork: "")
                }
            }
        }
        return await (tvdbCache.getDictionary(show.episodeID) ?? [:]) as NSDictionary
    }

    @objc public func addSeasonArtwork(_ show: MTTiVoShowReadOnly) async -> NSDictionary {
        let status = await tvdbCache.getStatus(show.episodeID)
        if status == .found || status == .notFound {
            if await tvdbCache.getSeasonArtwork(show.episodeID) == nil {
                if let seriesID = await tvdbCache.getSeries(show.episodeID) {
                    if let seasonArtwork = await tvdbService.querySeasonArtwork(seriesID: seriesID, season: show.season) {
                        if seasonArtwork == "" {
                            MTTVDBLogger.DDLogDetail("Discarding placeholder for missing TVDB season artwork for \(show.seriesTitle) (\(show.episodeID))")
                        } else {
                            MTTVDBLogger.DDLogDetail("Found season artwork for \(show.seriesTitle) (\(show.episodeID)): \(seasonArtwork)")
                        }
                        await tvdbCache.setSeasonArtwork(show.episodeID, seasonArtwork: seasonArtwork)
                    } else {
                        MTTVDBLogger.DDLogDetail("No season artwork for \(show.seriesTitle) (\(show.episodeID))")
                        await tvdbCache.setSeasonArtwork(show.episodeID, seasonArtwork: "")
                    }
                } else {
                    MTTVDBLogger.DDLogDetail("No series ID when adding season artwork for \(show.seriesTitle) (\(show.episodeID))")
                    await tvdbCache.setSeasonArtwork(show.episodeID, seasonArtwork: "")
                }
            }
        }
        return await (tvdbCache.getDictionary(show.episodeID) ?? [:]) as NSDictionary
    }

    @objc public func invalidateArtwork(_ show: MTTiVoShowReadOnly, forKey: String) async -> NSDictionary {
        if let key = MTTVDBCache.Key(rawValue: forKey) {
            switch key {
            case .episodeArtwork:
                await tvdbCache.setEpisodeArtwork(show.episodeID, episodeArtwork: "")
            case .seasonArtwork:
                await tvdbCache.setSeasonArtwork(show.episodeID, seasonArtwork: "")
            case .seriesArtwork:
                await tvdbCache.setSeriesArtwork(show.episodeID, seriesArtwork: "")
            default:
                MTTVDBLogger.DDLogMajor("Improper artwork key (\(forKey)) when rejecting artwork for \(show.seriesTitle) (\(show.episodeID))")
            }
        } else {
            MTTVDBLogger.DDLogMajor("Unknown artwork key (\(forKey)) when rejecting artwork for \(show.seriesTitle) (\(show.episodeID))")
        }
        return await (tvdbCache.getDictionary(show.episodeID) ?? [:]) as NSDictionary
    }

    func loadDefaults() -> Void {
        Task {
            _ = await [tvdbCache.loadCache(), tvdbService.loadToken()]
            await tvdbCache.cleanCache()
        }
    }

    @objc public func saveDefaults() -> Void {
        Task {
            _ = await [tvdbCache.saveCache(), tvdbService.saveToken()]
        }
    }

    func resetAll() async -> Void {
        _ = await [
            tvdbCache.reset(),
            seriesCache.reset(),
            tvdbStatistics.reset()
        ]
        await tvdbCache.saveCache()
    }

    @objc public func resetAll() -> Void {
        Task {
            await resetAll()
        }
    }

    @objc public func stats() async -> String {
        await tvdbStatistics.report()
    }

    @objc public func getReportingURL(id: String?, slug: String?) -> String {
        if let slug = slug {
            return tvdbService.slugURL(slug)
        } else if let id = id {
            return tvdbService.idURL(id)
        } else {
            return ""
        }
    }

    // Convenience functions intended for testing use only
    func val(_ key: MTTVDBStatisticsCountKey) async -> Int {
        await tvdbStatistics.val(key)
    }
    func val(_ key: MTTVDBStatisticsListKey) async -> Int {
        await tvdbStatistics.val(key)
    }
    func list(_ key: MTTVDBStatisticsListKey) async -> String {
        await tvdbStatistics.list(key)
    }
}
