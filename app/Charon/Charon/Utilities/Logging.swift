// Utilities/Logging.swift
// Charon

import os

extension Logger {
    nonisolated private static let subsystem = "com.houwert.Charon"

    nonisolated static let scan = Logger(subsystem: subsystem, category: "Scan")
    nonisolated static let offload = Logger(subsystem: subsystem, category: "Offload")
    nonisolated static let volumes = Logger(subsystem: subsystem, category: "Volumes")
}
