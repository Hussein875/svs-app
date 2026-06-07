//
//  Persistence.swift
//  SVS App
//
//  Created by Hussein Souleiman on 09.12.25.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            print("Core Data preview save failed: \(error)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SVS_App")
        if inMemory {
            if let first = container.persistentStoreDescriptions.first {
                first.url = URL(fileURLWithPath: "/dev/null")
            } else {
                print("Core Data store description missing for in-memory container.")
            }
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                print("Core Data persistent store failed to load: \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
