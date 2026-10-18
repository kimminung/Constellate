import Foundation

let defaultPriorityLabel = "Normal"

extension Item {
    var priorityLabel: String {
        switch priority {
        case .low: "Low"
        case .normal: defaultPriorityLabel
        case .high: "High"
        }
    }
}

func formatItem(_ item: Item) -> String {
    "\(item.name) [\(item.priorityLabel)]"
}
