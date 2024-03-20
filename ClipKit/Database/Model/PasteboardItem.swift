//
//  PasteboardItem.swift
//  Clip
//
//  Created by Riley Testut on 6/11/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import MobileCoreServices
import CoreLocation

private extension PasteboardItemRepresentation.RepresentationType
{
    var priority: Int {
        switch self
        {
        case .attributedText: return 0
        case .text: return 1
        case .url: return 2
        case .image: return 3
        }
    }
}

@objc(PasteboardItem)
public class PasteboardItem: NSManagedObject
{
    /* Properties */
    @NSManaged public private(set) var date: Date
    @NSManaged public var isMarkedForDeletion: Bool
    
    public var location: CLLocation? {
        get {
            guard let latitude, let longitude else { return nil }
            
            let coordinate = CLLocation(latitude: latitude.doubleValue, longitude: longitude.doubleValue)
            return coordinate
        }
        set {
            self.latitude = newValue?.coordinate.latitude as? NSNumber
            self.longitude = newValue?.coordinate.longitude as? NSNumber
        }
    }
    @NSManaged private var latitude: NSNumber?
    @NSManaged private var longitude: NSNumber?
    
    /* Relationships */
    @nonobjc public var representations: [PasteboardItemRepresentation] {
        return self._representations.array as! [PasteboardItemRepresentation]
    }
    @NSManaged @objc(representations) private var _representations: NSOrderedSet
    
    @NSManaged public var preferredRepresentation: PasteboardItemRepresentation?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init?(representations: [PasteboardItemRepresentation], context: NSManagedObjectContext)
    {
        guard !representations.isEmpty else { return nil }
        
        super.init(entity: PasteboardItem.entity(), insertInto: context)
        
        self._representations = NSOrderedSet(array: representations)
        
        let prioritizedRepresentationTypes = PasteboardItemRepresentation.RepresentationType.allCases.sorted { $0.priority > $1.priority }
        for type in prioritizedRepresentationTypes
        {
            guard let representation = representations.first(where: { $0.type == type }) else { continue }
            
            self.preferredRepresentation = representation
            break
        }
    }
    
    override public func awakeFromInsert()
    {
        super.awakeFromInsert()
        
        self.date = Date()
    }
}

public extension PasteboardItem
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PasteboardItem>
    {
        return NSFetchRequest<PasteboardItem>(entityName: "PasteboardItem")
    }
    
    class func historyFetchRequest() -> NSFetchRequest<PasteboardItem>
    {
        let fetchRequest = PasteboardItem.fetchRequest() as NSFetchRequest<PasteboardItem>
        fetchRequest.predicate = NSPredicate(format: "%K == NO", #keyPath(PasteboardItem.isMarkedForDeletion))
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PasteboardItem.date, ascending: false)]
        fetchRequest.fetchLimit = UserDefaults.shared.historyLimit.rawValue
        return fetchRequest
    }
}

// SwiftUI
extension PasteboardItem
{
    class func make(item: NSItemProviderWriting, date: Date = Date(), context: NSManagedObjectContext) -> PasteboardItem
    {
        let itemProvider = NSItemProvider(object: item)
        let semaphore = DispatchSemaphore(value: 0)
        
        let childContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        var objectID: NSManagedObjectID!
        
        PasteboardItemRepresentation.representations(for: itemProvider, in: childContext) { (representations) in
            let item = PasteboardItem(representations: representations, context: childContext)!
            item.date = date
            
            try! childContext.obtainPermanentIDs(for: [item])
            objectID = item.objectID
            
            try! childContext.save()
            semaphore.signal()
        }
        semaphore.wait()
                
        let pasteboardItem = context.object(with: objectID) as! PasteboardItem
        return pasteboardItem
    }
}
