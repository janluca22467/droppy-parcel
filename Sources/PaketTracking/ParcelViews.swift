import DroppyKit
import SwiftUI

struct ParcelCompactGlyph: View {
    @ObservedObject var droplet: PaketTrackingDroplet

    var body: some View {
        Image(systemName: droplet.arrivingToday.contains { $0.status == .outForDelivery } ? "box.truck.fill" : "shippingbox.fill")
            .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .medium))
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }
}

struct ParcelCompactLabel: View {
    @ObservedObject var droplet: PaketTrackingDroplet

    var body: some View {
        let count = droplet.arrivingToday.count
        Text(count > 1 ? "\(count) heute" : "heute")
            .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .medium, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }
}

struct ParcelWidget: View {
    @ObservedObject var droplet: PaketTrackingDroplet
    let context: ShelfWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            header
            if context.isCompact {
                summary
            } else {
                list
            }
            Spacer(minLength: 0)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12, weight: .medium))
            Text("Pakete")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            if !context.isCompact {
                Button {
                    droplet.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .disabled(droplet.isRefreshing)
                .help("Aktualisieren")
                .accessibilityLabel("Aktualisieren")
            }
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    private var summary: some View {
        let today = droplet.arrivingToday.count
        let open = droplet.parcels.filter { $0.status != .delivered }.count
        return VStack(alignment: .leading, spacing: 2) {
            Text(today > 0 ? "\(today) heute" : (open > 0 ? "\(open) unterwegs" : "Keine Pakete"))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            if today > 0, open > today {
                Text("\(open) insgesamt unterwegs")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if droplet.parcels.isEmpty {
            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                Text("Noch keine Sendung")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                Button("Sendung hinzufügen") { _ = droplet.openSettings() }
                    .buttonStyle(DroppyQuietButtonStyle())
                    .controlSize(.small)
            }
        } else {
            VStack(spacing: DroppySpacing.xsm) {
                ForEach(Array(droplet.sortedParcels.prefix(4))) { parcel in
                    HStack(spacing: DroppySpacing.sm) {
                        Text(parcel.carrier.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                            .frame(width: 28, alignment: .leading)
                        Text(parcel.displayName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        Spacer(minLength: DroppySpacing.md)
                        Text(parcelStatusText(parcel, now: droplet.now))
                            .font(.system(size: 13, weight: parcel.arrivesToday(now: droplet.now) ? .semibold : .regular, design: .rounded))
                            .lineLimit(1)
                            .foregroundStyle(
                                parcel.arrivesToday(now: droplet.now)
                                    ? AdaptiveColors.notchSurfacePrimaryText
                                    : AdaptiveColors.notchSurfaceTertiaryText
                            )
                    }
                }
            }
        }
    }
}

struct ParcelSettings: View {
    @ObservedObject var droplet: PaketTrackingDroplet
    @State private var carrier: ParcelCarrier = .dhl
    @State private var number = ""
    @State private var label = ""
    @State private var key = ""

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Neue Sendung")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(title: "Paketdienst") {
                        Picker("", selection: $carrier) {
                            ForEach(ParcelCarrier.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    DropletStackedRow(title: "Sendungsnummer") {
                        TextField("", text: $number, prompt: Text("0034043400000000"))
                            .textFieldStyle(.roundedBorder)
                    }
                    DropletStackedRow(title: "Bezeichnung (optional)") {
                        TextField("", text: $label, prompt: Text("Kopfhörer"))
                            .textFieldStyle(.roundedBorder)
                    }
                    DropletControlRow(title: "") {
                        Button("Hinzufügen") {
                            droplet.add(carrier: carrier, number: number, label: label)
                            number = ""
                            label = ""
                        }
                        .buttonStyle(DroppyAccentButtonStyle())
                        .controlSize(.small)
                        .disabled(number.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if !droplet.parcels.isEmpty {
                DropletSettingsSection {
                    settingsSectionHeader("Sendungen")
                } content: {
                    DropletSettingsCard {
                        ForEach(droplet.sortedParcels) { parcel in
                            DropletControlRow(title: "\(parcel.carrier.title) · \(parcel.displayName)") {
                                HStack(spacing: DroppySpacing.sm) {
                                    DropletValuePill(text: parcel.error ?? parcelStatusText(parcel, now: droplet.now))
                                    Button {
                                        droplet.remove(parcel.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(DroppyCircleButtonStyle(size: 24))
                                    .accessibilityLabel("Entfernen")
                                }
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("DHL")
            } content: {
                DropletSettingsCard {
                    DropletStackedRow(
                        title: "API-Schlüssel",
                        infoTip: "Kostenlos unter developer.dhl.com als „Shipment Tracking – Unified“ anlegen. DPD braucht keinen Schlüssel."
                    ) {
                        SecureField("", text: $key, prompt: Text("Schlüssel einfügen"))
                            .textFieldStyle(.roundedBorder)
                            .onAppear { key = droplet.dhlKey }
                            .onSubmit { droplet.dhlKey = key }
                            .onChange(of: key) { _, value in droplet.dhlKey = value }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Anzeige")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "In der Notch fixieren",
                        subtitle: "Zeigt „heute“ dauerhaft, solange ein Paket zugestellt wird. Sonst nur beim Darüberfahren.",
                        isOn: Binding(get: { droplet.pinsActivity }, set: { droplet.pinsActivity = $0 })
                    )
                    DropletSliderRow(
                        title: "Aktualisierung",
                        value: "\(Int(droplet.intervalMinutes)) min",
                        binding: Binding(get: { droplet.intervalMinutes }, set: { droplet.intervalMinutes = $0 }),
                        range: 5...60,
                        step: 5
                    )
                }
            }
        }
    }
}
