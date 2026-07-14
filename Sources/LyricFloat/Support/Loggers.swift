import OSLog

enum AppLog {
    static let playback = Logger(subsystem: "com.trivia.LyricFloat", category: "Playback")
    static let lyrics = Logger(subsystem: "com.trivia.LyricFloat", category: "Lyrics")
    static let storage = Logger(subsystem: "com.trivia.LyricFloat", category: "Storage")
    static let windowing = Logger(subsystem: "com.trivia.LyricFloat", category: "Windowing")
    static let menuBar = Logger(subsystem: "com.trivia.LyricFloat", category: "MenuBar")
}
