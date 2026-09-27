// Utilities/Logging.swift
// Charon

import os

extension Logger {
    private static let subsystem = "com.houwert.Charon"

    static let scan = Logger(subsystem: subsystem, category: "Scan")
    static let ferry = Logger(subsystem: subsystem, category: "Ferry")
    static let volumes = Logger(subsystem: subsystem, category: "Volumes")
}
