//
//  TabularDataPackageAtomicStore.swift
//  Quotemarks
//
//  Created by Christopher Hale on 16/6/25.
//  Copyright © 2016 Christopher Hale. All rights reserved.
//

import CoreData
import DialectalCSV
import DataPackage
import TableSchema

/**
 An atomic store for CoreData that supports [Tabular Data Package](http://frictionlessdata.io/guides/tabular-data-package/) containing CSV-formatted data.
 */
public final class TabularPackageAtomicStore: NSAtomicStore {

    // This value is expected to take the form of "Module.Type". If this lives in an app instead it'll "AppName.Type"
    // Otherwise CoreData will throw NSPersistentStoreInvalidTypeError
    public static let storeType = String(reflecting: TabularPackageAtomicStore.self)
    public static let storeIdentifier = UUID().uuidString

    fileprivate static let identifierKey = "_id"

    public enum StoreError: Error {
        case misconfigured(String)
        case malformed(String)
        case unsupported(String)
        case `internal`
    }

    fileprivate var referenceObjectsByID = [NSManagedObjectID: String]()

    fileprivate let dateFormatter = ISO8601DateFormatter()

    // MARK: - NSAtomicStore

    override init(persistentStoreCoordinator coordinator: NSPersistentStoreCoordinator?, configurationName: String?, at url: URL, options: [AnyHashable: Any]? = nil) {
        super.init(persistentStoreCoordinator: coordinator, configurationName: configurationName, at: url, options: options)

        self.identifier = TabularPackageAtomicStore.storeIdentifier
        self.metadata = [NSStoreTypeKey: TabularPackageAtomicStore.storeType, NSStoreUUIDKey: self.identifier as Any]

        FileManager.default.createFile(atPath: url.absoluteString, contents: nil, attributes: nil)
    }

    public override func load() throws {
        guard let url = self.url else {
            throw StoreError.misconfigured("Missing URL for data package.")
        }

        guard let package = try self.loadPackage(from: url) else {
            return
        }

        var nodes = Set<NSAtomicStoreCacheNode>()
        var nodesByReferenceObject = [String: (String, NSAtomicStoreCacheNode)]()
        var schemaByName = [String: Schema]()

        // Build nodes
        for resource in package.resources {
            let name = resource.name

            guard let entityDescription = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[name] else {
                continue
            }

            guard let tabularResource = resource as? TabularResource else {
                throw StoreError.unsupported("Unsupported package profile for resource '\(name)'.")
            }

            guard let mediaType = resource.mediatype, mediaType == "text/csv" else {
                throw StoreError.unsupported("Unsupported resource media type for resource '\(name)'.")
            }

            guard let format = resource.format, format == "csv" else {
                throw StoreError.unsupported("Unsupported resource format for resource '\(name)'.")
            }

            guard let schema = tabularResource.schema else {
                throw StoreError.malformed("Missing schema for resource '\(name)'.")
            }

            schemaByName[name] = schema

            for resourceURL in tabularResource.paths {
                // Note: Earlier versions didn't include a CSVDialect, or used empty values when null was meant
                guard let dialect = Dialect(tabularResource.dialect ?? CSVDialect.storeDialect()) else {
                    throw StoreError.malformed("Unsupported CSV dialect for resource '\(name)'.")
                }

                let provider: CSVAtomicTableProvider
                do {
                    provider = try CSVAtomicTableProvider(name: name, dialect: dialect, url: resourceURL, relativeTo: url)
                } catch CSVAtomicTableProvider.TableError.malformed(let message) {
                    throw StoreError.malformed(message)
                }
                
                let table = Table(provider: AnyTableProvider(provider), schema: schema)

                // Build entities
                for (lineNumber, lineValues) in table.enumerated() {
                    var properties = [String: Any]()

                    // Grab properties by relying upon the schema not headers
                    guard schema.fields.count == lineValues.count else {
                        throw StoreError.malformed("Mismatching field counts for resource '\(name)' at line `\(lineNumber + 1)'.")
                    }
                    for (fieldIndex, field) in schema.fields.enumerated() {
                        // Note: Keeps placeholder values for foreign keys to be resolved later
                        properties[field.name] = lineValues[fieldIndex]
                    }

                    let referenceObject = properties[TabularPackageAtomicStore.identifierKey] as? String ?? UUID().uuidString
                    let managedObjectID = self.objectID(for: entityDescription, withReferenceObject: referenceObject)
                    self.referenceObjectsByID[managedObjectID] = referenceObject
                    let node = NSAtomicStoreCacheNode(objectID: managedObjectID)
                    node.propertyCache = NSMutableDictionary(dictionary: properties)
                    nodesByReferenceObject[referenceObject] = (name, node)
                    nodes.insert(node)
                }
            }
        }

        // Resolve foreign keys
        for (_, (name, node)) in nodesByReferenceObject {
            guard let schema = schemaByName[name] else {
                throw StoreError.internal
            }

            var foreignKeyFields = Set<TableSchema.Field>()

            schema.foreignKeys.forEach { (foreignKey) in
                foreignKey.fields.forEach { (field) in
                    foreignKeyFields.insert(field)
                }
            }

            for field in schema.fields {
                guard foreignKeyFields.contains(field) else {
                    continue
                }
                if field.type == .string, field.format == .uuid {
                    // To-one relationship
                    guard let identifier = node.propertyCache?.value(forKey: field.name) as? String else {
                        throw StoreError.internal
                    }
                    guard let (_, destinationNode) = nodesByReferenceObject[identifier] else {
                        throw StoreError.internal
                    }
                    node.propertyCache?.setValue(destinationNode, forKey: field.name)
                } else if field.type == .array {
                    // To-many relationship
                    guard let array = node.propertyCache?.value(forKey: field.name) as? [String] else {
                        throw StoreError.internal
                    }
                    var destinationNodes = [NSAtomicStoreCacheNode]()
                    for identifier in array {
                        guard let (_, destinationNode) = nodesByReferenceObject[identifier] else {
                            throw StoreError.internal
                        }
                        destinationNodes.append(destinationNode)
                    }
                    node.propertyCache?.setValue(destinationNodes, forKey: field.name)
                } else {
                    throw StoreError.internal
                }
            }
        }

        self.addCacheNodes(nodes)
    }

    public override func save() throws {
        guard let url = self.url else {
            throw StoreError.misconfigured("Missing URL for data package.")
        }
        
//        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)

        // Build package
        let package = TabularPackage()
        package.resources = try self.saveResources()
        try self.save(package: package, to: url)
    }

    public override func newCacheNode(for managedObject: NSManagedObject) -> NSAtomicStoreCacheNode {
        let node = NSAtomicStoreCacheNode(objectID: managedObject.objectID)

        for property in managedObject.objectID.entity.propertiesByName {
            node.setValue(managedObject.value(forKey: property.key), forKey: property.key)
        }

        self.addCacheNodes([node])

        return node
    }

    public override func newReferenceObject(for managedObject: NSManagedObject) -> Any {
        if let referenceObject = self.referenceObjectsByID[managedObject.objectID] {
            return referenceObject
        }

        let referenceObject = UUID().uuidString
        self.referenceObjectsByID[managedObject.objectID] = referenceObject

        return referenceObject
    }

    public override func updateCacheNode(_ node: NSAtomicStoreCacheNode, from managedObject: NSManagedObject) {
        for property in managedObject.objectID.entity.propertiesByName {
            node.setValue(managedObject.value(forKey: property.key), forKey: property.key)
        }
    }

    // MARK: - Private
    
    fileprivate func loadPackage(from url: URL) throws -> Package? {
        // Create DataPackage placeholder file if one does not exist at this location
        var descriptorPath = url.path
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: descriptorPath, isDirectory: &isDirectory) {
            try FileManager.default.createDirectory(atPath: descriptorPath, withIntermediateDirectories: true, attributes: nil)
            isDirectory = true
        }
        if isDirectory.boolValue {
            descriptorPath = url.appendingPathComponent("datapackage.json").path
        }

        // Note: We may be "loading" a new file
        if !FileManager.default.fileExists(atPath: descriptorPath) {
            let initialData = try? JSONSerialization.data(withJSONObject: [String: Any](), options: [])
            if !FileManager.default.createFile(atPath: descriptorPath, contents: initialData, attributes: nil) {
                throw StoreError.malformed("Failed to create placeholder package.")
            } else {
                // Don't try loading an empty descriptor; we'll populate it correctly when we save
                return nil
            }
        }

        // Load DataPackage
        let registry = Registry(default: Package.self)
        registry.add(profile: TabularPackage.self)

        var log = Log()
        guard let package = Package.package(url: url, registry: registry, log: &log) else {
            var message = "Failed to load package."
            if let reason = log.pruning().first {
                message.append(" \(reason)")
            }
            throw StoreError.malformed(message)
        }

        guard package is TabularPackage else {
            throw StoreError.unsupported("Unsupported package profile.")
        }

        log = Log()
        guard package.verify(log: &log) else {
            var message = "Failed to verify package integrity."
            if let reason = log.pruning().first {
                message.append(" \(reason)")
            }
            throw StoreError.malformed(message)
        }
        
        return package
    }
    
    fileprivate func saveResources() throws -> [TabularResource] {
        // Group nodes by entity
        var nodesByEntities = [NSEntityDescription: Set<NSAtomicStoreCacheNode>]()
        for node in self.cacheNodes() {
            let entity = node.objectID.entity
            
            var nodes = nodesByEntities.removeValue(forKey: entity) ?? Set<NSAtomicStoreCacheNode>()
            nodes.insert(node)
            nodesByEntities[entity] = nodes
        }

        // Build resources
        var resources = [TabularResource]()
        
        guard let persistentStoreCoordinator = self.persistentStoreCoordinator else {
            throw StoreError.misconfigured("Missing persistent store coordinator.")
        }

        for (entityName, entity) in persistentStoreCoordinator.managedObjectModel.entitiesByName {
            let resource = TabularResource(entityName)
            resources.append(resource)

            resource.format = "csv"
            resource.mediatype = "text/csv"

            let fileName = entityName.lowercased() + ".csv"
            if let url = URL(string: fileName) {
                resource.paths = [url]
            }

            // Build schema
            let schema = Schema()
            resource.schema = schema

            // Build singular primary key
            let primaryField = TableSchema.Field(TabularPackageAtomicStore.identifierKey)
            primaryField.constraints.unique = true
            primaryField.constraints.required = true
            primaryField.format = .uuid
            schema.fields.append(primaryField)
            schema.primaryKeys = [primaryField]

            // Build schema fields
            for (name, attribute) in entity.attributesByName {
                let field = TableSchema.Field(name)
                switch attribute.attributeType {
                case .stringAttributeType:
                    field.type = .string
                case .dateAttributeType:
                    field.type = .dateTime
                case .booleanAttributeType:
                    field.type = .boolean
                    field.trueValues = ["true"]
                    field.falseValues = ["false"]
                case .integer16AttributeType:
                    fallthrough
                case .integer32AttributeType:
                    fallthrough
                case .integer64AttributeType:
                    field.type = .integer
                default:
                    throw StoreError.unsupported("Unsupported type for attribute '\(name)'.")
                }
                schema.fields.append(field)
            }

            // Build foreign key relationships
            for (name, relationship) in entity.relationshipsByName {
                guard let destinationEntityName = relationship.destinationEntity?.name else {
                    continue
                }

                // Set up foreign key destination
                let relationshipField = TableSchema.Field(name)
                if relationship.isToMany {
                    relationshipField.type = .array
                } else {
                    relationshipField.format = .uuid
                }
                schema.fields.append(relationshipField)

                let reference = TableSchema.ForeignKey.Reference(resource: destinationEntityName)
                reference.fields = [primaryField]
                let foreignKey = TableSchema.ForeignKey(fields: [relationshipField], reference: reference)
                schema.foreignKeys.append(foreignKey)
            }

            let dialect = DialectalCSV.Dialect.storeDialect()
            try self.saveDocument(named: fileName, schema: schema, nodes: nodesByEntities[entity] ?? Set<NSAtomicStoreCacheNode>(), using: dialect)
            resource.dialect = DataPackage.CSVDialect(dialect)
        }
        
        return resources
    }

    fileprivate func saveDocument(named fileName: String, schema: Schema, nodes: Set<NSAtomicStoreCacheNode>, using dialect: DialectalCSV.Dialect) throws {
        guard let url = self.url else {
            throw StoreError.misconfigured("Missing URL for data package.")
        }

        var foreignKeyFields = Set<TableSchema.Field>()
        schema.foreignKeys.forEach { (foreignKey) in
            foreignKey.fields.forEach { (field) in
                foreignKeyFields.insert(field)
            }
        }
        
        let nullSequence = dialect.nullSequence ?? ""

        // Build records
        var lines: [DialectalCSV.Record] = []
        for node in nodes {
            let record: Row = try schema.fields.map { (field) in
                let value = try self.value(for: field, on: node, using: foreignKeyFields)
                return schema.reverseCast(value, by: field) ?? nullSequence
            }
            lines.append(record)
        }

        let headerFields = schema.fields.map { (field) in field.name }
        let document = DialectalCSV.Document(header: headerFields, records: lines, dialect: dialect)
        guard let resourceData = try? document.export() else {
            throw StoreError.malformed("Failed to generate CSV document '\(fileName)'.")
        }
        let resourcePath = url.appendingPathComponent(fileName).path

        if !FileManager.default.createFile(atPath: resourcePath, contents: resourceData, attributes: nil) {
            throw StoreError.malformed("Failed to save CSV document '\(fileName)'.")
        }
    }
    
    fileprivate func value(for field: TableSchema.Field, on node: NSAtomicStoreCacheNode, using foreignKeyFields: Set<TableSchema.Field>) throws -> Any? {
        var value: Any?
        // Handle conversions of special types before casting
        if field.name == TabularPackageAtomicStore.identifierKey {
            guard let referenceObject = self.referenceObject(for: node.objectID) as? String else {
                throw StoreError.internal
            }
            guard let uuidString = UUID(uuidString: referenceObject) else {
                throw StoreError.internal
            }
            value = uuidString
        } else if foreignKeyFields.contains(field) {
            if field.type == .array {
                // To-many relationship
                var cachedValue: [NSObject]?
                if let set = node.propertyCache?.value(forKey: field.name) as? Set<NSObject> {
                    cachedValue = Array(set)
                } else if let orderedSet = node.propertyCache?.value(forKey: field.name) as? NSOrderedSet, let array = orderedSet.array as? [NSObject] {
                    cachedValue = array
                } else if let array = node.propertyCache?.value(forKey: field.name) as? [NSObject] {
                    cachedValue = array
                }
                guard let sequence = cachedValue else {
                    throw StoreError.internal
                }
                var referenceObjects = [String]()
                for object in sequence {
                    var referenceObject: String?
                    if let managedObject = object as? NSManagedObject {
                        referenceObject = self.referenceObject(for: managedObject.objectID) as? String
                    } else if let cacheNode = object as? NSAtomicStoreCacheNode {
                        referenceObject = self.referenceObject(for: cacheNode.objectID) as? String
                    }
                    guard let reference = referenceObject else {
                        throw StoreError.internal
                    }
                    referenceObjects.append(reference)
                }
                value = referenceObjects
            } else if field.type == .string, field.format == .uuid {
                // To-one relationship
                var referenceObject: String?
                if let managedObject = node.propertyCache?.value(forKey: field.name) as? NSManagedObject {
                    referenceObject = self.referenceObject(for: managedObject.objectID) as? String
                } else if let cacheNode = node.propertyCache?.value(forKey: field.name) as? NSAtomicStoreCacheNode {
                    referenceObject = self.referenceObject(for: cacheNode.objectID) as? String
                }
                guard let reference = referenceObject, let uuidString = UUID(uuidString: reference) else {
                    throw StoreError.internal
                }
                value = uuidString
            } else {
                throw StoreError.internal
            }
        } else if let cacheValue = node.propertyCache?.value(forKey: field.name) {
            value = cacheValue
        }
        return value
    }
    
    fileprivate func save(package: Package, to url: URL) throws {
        var log = Log()
        guard package.verify(log: &log) else {
            var message = "Failed to verify package integrity."
            if let reason = log.pruning().first {
                message.append(" \(reason)")
            }
            throw StoreError.malformed(message)
        }

        guard package.save(to: url) else {
            throw StoreError.malformed("Failed to save data package.")
        }
    }
    
}
