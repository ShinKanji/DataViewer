import Foundation

nonisolated enum PlotGroupDisplayNaming {
    static func friendlyName(
        for descriptor: ChannelDescriptor,
        derivedRecords: [UUID: DerivedChannelRecord] = [:]
    ) -> String {
        if let derived = derivedRecords[descriptor.id] {
            return derived.displayName
        }
        if ChannelColumnNaming.usesVelocityKPHDisplayName(descriptor.columnName) {
            return ChannelColumnNaming.unifiedVelocityKPHDisplayName
        }
        return descriptor.columnName
    }

    static func channelNames(
        for group: PlotGroup,
        catalogByID: [UUID: ChannelDescriptor],
        derivedRecords: [UUID: DerivedChannelRecord] = [:]
    ) -> [String] {
        group.channelIDs.compactMap { channelID in
            guard let descriptor = catalogByID[channelID] else { return nil }
            return friendlyName(for: descriptor, derivedRecords: derivedRecords)
        }
    }

    static func title(
        for group: PlotGroup,
        catalogByID: [UUID: ChannelDescriptor],
        derivedRecords: [UUID: DerivedChannelRecord] = [:]
    ) -> String {
        let names = channelNames(for: group, catalogByID: catalogByID, derivedRecords: derivedRecords)
        if group.channelIDs.count == 1,
           let channelID = group.channelIDs.first,
           let descriptor = catalogByID[channelID] {
            return friendlyName(for: descriptor, derivedRecords: derivedRecords)
        }
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return joinedPreview(from: names, totalCount: group.channelIDs.count)
    }

    static func subtitle(
        for group: PlotGroup,
        catalogByID: [UUID: ChannelDescriptor],
        derivedRecords: [UUID: DerivedChannelRecord] = [:]
    ) -> String? {
        guard group.channelIDs.count > 1 else { return nil }
        let names = channelNames(for: group, catalogByID: catalogByID, derivedRecords: derivedRecords)
        guard !names.isEmpty else { return nil }
        return joinedPreview(from: names, totalCount: names.count)
    }

    static func joinedPreview(from names: [String], totalCount: Int) -> String {
        let preview = names.prefix(3)
        let joined = preview.joined(separator: "、")
        if totalCount > 3 {
            return "\(joined) 等\(totalCount)项"
        }
        return joined
    }

    static func showsChartHeader(for group: PlotGroup) -> Bool {
        group.channelIDs.count > 1
    }
}
