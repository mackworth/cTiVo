//
//  MTTVDB.swift
//  cTiVo
//
//  Created by Hugh Mackworth on 6/8/22.
//  Copyright © 2022 cTiVo. All rights reserved.
//

import Foundation
import CocoaLumberjack

@objc(MTTVDB4)
class MTTVDB4 : MTTVDB {

static let _singletonInstance = MTTVDB4()
private override init() {
    //This prevents others from using the default '()' initializer for this class.
}
public static var logLevel = DDLogLevel.verbose;
  
@objc public static var ddLogLevel : DDLogLevel { 
  get {return logLevel}
  @objc(ddSetLogLevel:) set {logLevel = newValue}
}

  func DDLogReport(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line ) {
    DDLogError( msg, level: Self.logLevel, context: 1, file: file, function: function, line:line) 
  }
  func DDLogMajor(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line ) {
    DDLogWarn( msg, level: Self.logLevel, context: 1, file: file, function: function, line:line) 
  }
  func DDLogDetail(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line ) {
    DDLogInfo( msg, level: Self.logLevel, context: 1, file: file, function: function, line:line) 
  }
  func DDLogVerbose(_ msg: String, file: StaticString = #file, function: StaticString = #function, line: UInt = #line ) {
    CocoaLumberjack.DDLogVerbose( msg, level: Self.logLevel, context: 1, file: file, function: function, line:line)  
  }

override class func sharedManager() -> MTTVDB4 {
    return MTTVDB4._singletonInstance
}

override func getTheTVDBDetails(_ show: MTTiVoShow) {
    if let title = show.showTitle {
      DDLogReport( "Swift TVDB for \(title)")
    }
}

override func getTheMovieDBDetails(_ show: MTTiVoShow) {
    if let title = show.showTitle {
      DDLogVerbose("Swift MOVIEDB for \(title)")
    }
}

override func cacheArtWork(_ newArtwork: String, forKey key: String, for show: MTTiVoShow) -> [AnyHashable : Any] {
    if let title = show.showTitle {
        print ("Swift TVDB calling cacheArtWork for \(title)")
    }
    return [
        kTVDBSeriesKey        : "139911",    //what TVDB SeriesID does this belong to?
        kTVDBEpisodeArtworkKey: "episodes/139911/9160870.jpg<",    //URL for artwork at TVDB
        kTVDBSeasonArtworkKey : "v4/season/1941956/posters/6158398f6ab76.jpg",    //URL for artwork at TVDB
        kTVDBSeriesArtworkKey : "fanart/original/81388-2.jpg",    //URL for artwork at TVDB
        kTVDBEpisodeKey       : "127",    //string with episode number
        kTVDBSeasonKey        : "2022",    //string with season number
        "date"                : Date(),
        kTVDBURLsKey          : "http://thetvdb.com/?tab=seasonall&amp;id=139911&amp;lid=7",    //URLs for reporting to user
]
}
    
override func resetTVDBInfo(_ show: MTTiVoShow) {
    if let title = show.showTitle {
        print ("Swift TVDB calling resetTVDBInfo for \(title)")
    }
}

override func addSeasonArtwork(_ show: MTTiVoShow) {
    if let title = show.showTitle {
        print ("Swift TVDB calling addSeasonArtwork for \(title)")
    }
}

override func addSeriesArtwork(_ show: MTTiVoShow) {
    if let title = show.showTitle {
        print ("Swift TVDB calling addSeriesArtwork for \(title)")
    }
}

override func resetAll() {
    print ("Swift TVDB calling resetAll")
}

override func saveDefaults() {
    print ("Swift TVDB calling saveDefaults")
}

override func stats() -> String {
    print ("Swift TVDB calling stats")
    return "Swifty stats here"
}

override func isActive() -> Bool {
    print ("Swift TVDB calling isActive")
    return true
}

override func seriesIDs(for show: MTTiVoShow) -> [String] {
    if let title = show.showTitle {
        print ("Swift TVDB calling seriesIDs for \(title)")
    }
    return ["ID1"]
}

}


