#!/usr/bin/env swift
import Foundation

// Graceful shutdown on SIGTERM/SIGINT
signal(SIGTERM) { _ in exit(0) }
signal(SIGINT)  { _ in exit(0) }

let center = DistributedNotificationCenter.default()

center.addObserver(
    forName: NSNotification.Name("com.apple.Music.playerInfo"),
    object: nil,
    queue: nil
) { notification in
    let info   = notification.userInfo ?? [:]
    let state  = (info["Player State"] as? String ?? "").lowercased()
    let title  = info["Name"]   as? String ?? ""
    let artist = info["Artist"] as? String ?? ""
    let album  = info["Album"]  as? String ?? ""

    let payload: [String: String] = [
        "status": state,
        "title":  title,
        "artist": artist,
        "album":  album,
    ]

    if let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
       ),
       let line = String(data: data, encoding: .utf8)
    {
        print(line)
        fflush(stdout)
    }
}

RunLoop.main.run()
