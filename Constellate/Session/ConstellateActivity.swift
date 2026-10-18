import Foundation
#if canImport(GroupActivities)
import GroupActivities

/// SharePlay activity for a Constellate meeting. Requires the `com.apple.developer.group-session` entitlement.
nonisolated struct ConstellateActivity: GroupActivity {
    static let activityIdentifier = "com.coulson.Constellate.meeting"

    var projectName: String

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Constellate · \(projectName)"
        meta.subtitle = "Walk the code constellation together"
        meta.type = .generic
        return meta
    }
}
#endif
