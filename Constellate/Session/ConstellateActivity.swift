import Foundation
#if canImport(GroupActivities)
import GroupActivities

/// SharePlay activity for a Constellate meeting. Requires the `com.apple.developer.group-session` entitlement.
nonisolated struct ConstellateActivity: GroupActivity {
    static let activityIdentifier = "com.coulson.Constellate.meeting"

    var projectName: String
    /// Language of the inviter's app, so the invitation card reads the same way the meeting will.
    var languageCode: String = "ko"

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Constellate · \(projectName)"
        meta.subtitle = languageCode == "en" ? "Walk the code constellation together" : "코드 별자리를 함께 걸어요"
        meta.type = .generic
        return meta
    }
}
#endif
