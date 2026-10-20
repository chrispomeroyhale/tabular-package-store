//
//  CSVAtomicTableProvider.swift
//  Quotemarks
//
//  Created by Christopher Hale on 18/1/28.
//  Copyright © 2018 Christopher Hale. All rights reserved.
//

import Foundation
import TableSchema
import DialectalCSV

class CSVAtomicTableProvider: TableProvider {

    let document: DialectalCSV.Document

    enum TableError: Error {
        case malformed(String)
    }

    init(name: String, dialect: DialectalCSV.Dialect, url resourceURL: URL, relativeTo packageURL: URL) throws {
        let entityData: Data
        let directoryURL = URL(fileURLWithPath: packageURL.path, isDirectory: true)
        if let data = FileManager.default.contents(atPath: resourceURL.path) {
            entityData = data
        } else if let adjustedURL = URL(string: resourceURL.path, relativeTo: directoryURL), let data = try? Data(contentsOf: adjustedURL) {
            entityData = data
        } else {
            throw TableError.malformed("Unable to open path '\(resourceURL.path)' for resource '\(name)'.")
        }

        guard let document = try? Document(data: entityData, dialect: dialect) else {
            throw TableError.malformed("Failed to parse CSV for resource '\(name)'.")
        }

        self.document = document
    }

    // MARK: - TableProvider

    var header: [String]? {
        return self.document.header
    }

    // MARK: - Sequence

    func makeIterator() -> AnyIterator<[String?]> {
        var currentRecord = 0
        return AnyIterator {
            guard currentRecord < self.document.records.count else {
                return nil
            }
            defer {
                currentRecord += 1
            }
            return self.document.records[currentRecord]
        }
    }

}
