//
//  CSVDialect.swift
//  Quotemarks
//
//  Created by Christopher Hale on 18/1/28.
//  Copyright © 2018 Christopher Hale. All rights reserved.
//

import Foundation
import DataPackage
import DialectalCSV

public extension DialectalCSV.Dialect {

    /// Converts dialect model from DataPackage's representation to DialectalCSV's representation in a permissive manner
    init?(_ dialect: DataPackage.CSVDialect) {
        self.init()
        self.delimiter = dialect.delimiter
        self.lineTerminator = dialect.lineTerminator
        if let quoteCharacter = (dialect.quoteCharacter ?? "").isEmpty ? nil : dialect.quoteCharacter {
            self.quoteCharacter = Character(quoteCharacter)
        }
        self.doubleQuote = dialect.doubleQuote
        if let escapeCharacter = (dialect.escapeCharacter ?? "").isEmpty ? nil : dialect.escapeCharacter {
            self.escapeCharacter = Character(escapeCharacter)
        }
        self.nullSequence = (dialect.nullSequence ?? "").isEmpty ? nil : dialect.nullSequence
        self.skipInitialSpace = dialect.skipInitialSpace
        self.header = dialect.header
    }
    
    static func storeDialect() -> Dialect {
        return Dialect()
    }

}

public extension DataPackage.CSVDialect {

    /// Converts dialect model from DialectalCSV's representation to DataPackage's representation in a permissive manner
    convenience init(_ dialect: DialectalCSV.Dialect) {
        self.init()
        self.delimiter = dialect.delimiter
        self.lineTerminator = dialect.lineTerminator
        var quoteString: String?
        if let quoteCharacter = dialect.quoteCharacter {
            quoteString = String(quoteCharacter)
        }
        self.quoteCharacter = quoteString
        self.doubleQuote = dialect.doubleQuote
        var escapeString: String?
        if let escapeCharacter = dialect.escapeCharacter {
            escapeString = String(escapeCharacter)
        }
        self.escapeCharacter = escapeString
        self.nullSequence = (dialect.nullSequence ?? "").isEmpty ? nil : dialect.nullSequence
        self.skipInitialSpace = false
        self.header = dialect.header
        self.caseSensitiveHeader = true
    }
    
    static func storeDialect() -> CSVDialect {
        let dialect = CSVDialect()
        dialect.caseSensitiveHeader = true
        return dialect
    }

}
