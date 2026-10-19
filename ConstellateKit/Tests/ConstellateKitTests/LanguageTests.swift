import Foundation
import Testing
@testable import ConstellateKit

/// Korean is the primary language; English stays available. Every Kit builder that writes prose must
/// honour `HostLanguage`, and single-language display names must exist for every enum the app shows.
@Suite struct LanguageTests {
    let graph = SampleGraph.orbitNotes()

    @Test func defaultsAndPicking() {
        #expect(HostLanguage.appDefault == .korean)
        #expect(HostLanguage.korean.pick("가", "a") == "가")
        #expect(HostLanguage.english.pick("가", "a") == "a")
        #expect(HostLanguage.korean.fallback == .english && HostLanguage.english.fallback == .korean)
        #expect(HostLanguage(rawValue: "ko") == .korean && HostLanguage(rawValue: "en") == .english)
        #expect(HostLanguage.korean.localeIdentifier == "ko_KR" && HostLanguage.korean.voiceLanguage == "ko-KR")
    }

    @Test func tourNarratesInKorean() throws {
        let ko = TourBuilder().tour(for: graph, maxSteps: 8, language: .korean)
        let en = TourBuilder().tour(for: graph, maxSteps: 8, language: .english)
        #expect(ko.title.contains("둘러보기"))
        #expect(en.title.contains("overview"))
        #expect(ko.steps.map(\.nodeID) == en.steps.map(\.nodeID), "language changes words, not the route")
        let first = try #require(ko.steps.first)
        #expect(first.narration.contains("진입점"))
        #expect(first.title.hasPrefix("진입점"))
        for step in ko.steps {
            #expect(!step.narration.isEmpty)
            #expect(!step.narration.contains(" is a "), "no English sentence fragments in Korean narration")
        }
        // Default stays English so existing callers (and TourTests) are unchanged.
        #expect(TourBuilder().tour(for: graph).steps.first?.narration.contains("entry point") == true)
    }

    @Test func clusterSummaryInKorean() throws {
        let cluster = try #require(ClusterBuilder().clusters(from: graph, granularity: .folder).first)
        let ko = ClusterBuilder.heuristicSummary(for: cluster, in: graph, language: .korean)
        let en = ClusterBuilder.heuristicSummary(for: cluster, in: graph, language: .english)
        #expect(ko.contains("줄") && ko.hasPrefix(cluster.title))
        #expect(en.contains("lines") && en == ClusterBuilder.heuristicSummary(for: cluster, in: graph))
    }

    @Test func singleLanguageNamesExistForEveryCase() {
        for language in HostLanguage.allCases {
            for layer in ArchitectureLayer.allCases { #expect(!layer.name(language).isEmpty) }
            for kind in NodeKind.allCases { #expect(!kind.name(language).isEmpty) }
            for kind in EdgeKind.allCases { #expect(!kind.name(language).isEmpty) }
            for g in ClusterGranularity.allCases { #expect(!g.name(language).isEmpty) }
            for mode in MeetingMode.allCases { #expect(!mode.name(language).isEmpty) }
            for style in LayoutStyle.allCases { #expect(!style.name(language).isEmpty && !style.axes(language).isEmpty) }
            for mode in RelationDisplayMode.allCases { #expect(!mode.name(language).isEmpty) }
            for kind in RelationKind.allCases {
                #expect(!kind.style.name(language).isEmpty && !kind.hint(language).isEmpty)
                for outgoing in [true, false] {
                    let phrase = kind.phrase(outgoing: outgoing, language: language)
                    #expect(!phrase.isEmpty && !phrase.contains(" · "))
                }
            }
        }
        #expect(RelationKind.presents.phrase(outgoing: true, language: .korean) == "띄우는 화면")
        #expect(RelationKind.presents.phrase(outgoing: true, language: .english) == "Presents")
        #expect(LayoutStyle.celestial.name(.korean) == "천구" && LayoutStyle.celestial.name(.english) == "Celestial")
    }
}
