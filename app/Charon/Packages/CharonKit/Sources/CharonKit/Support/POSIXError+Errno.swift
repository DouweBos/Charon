// Support/POSIXError+Errno.swift
// CharonKit

import Foundation

extension POSIXError {
    /// Wraps the current `errno`.
    static var current: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

/// Throws `POSIXError.current` when a libc call returns -1.
@discardableResult
func posixCheck(_ result: Int32) throws -> Int32 {
    if result == -1 { throw POSIXError.current }
    return result
}
