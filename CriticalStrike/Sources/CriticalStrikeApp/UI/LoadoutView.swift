import SwiftUI
import CriticalStrikeCore

struct LoadoutView: View {
    @EnvironmentObject private var app: AppState
    @State private var editingSlot: LoadoutSlot = .primary

    private var profile: PlayerProfile { app.profile }
    private var loadout: Loadout { profile.selectedLoadout }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Loadout", subtitle: loadout.name,
                         onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: profile.wallet) { app.go(to: .store) }))

            classSelector

            HStack(alignment: .top, spacing: 12) {
                slotColumn
                weaponDetail
            }
        }
        .padding(16)
    }

    private var classSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profile.loadouts.indices, id: \.self) { index in
                    let entry = profile.loadouts[index]
                    Button {
                        app.selectLoadout(index)
                    } label: {
                        Text(entry.name)
                            .font(Theme.body(13))
                            .foregroundStyle(index == profile.selectedLoadoutIndex
                                             ? Theme.textPrimary : Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(index == profile.selectedLoadoutIndex
                                                       ? Theme.accent.opacity(0.22) : Theme.surfaceElevated))
                            .overlay(Capsule().strokeBorder(
                                index == profile.selectedLoadoutIndex ? Theme.accent : Theme.stroke,
                                lineWidth: 1))
                    }
                }
            }
        }
    }

    private var slotColumn: some View {
        VStack(spacing: 8) {
            slotButton(.primary, build: loadout.primary)
            slotButton(.secondary, build: loadout.secondary)
            slotButton(.melee, build: loadout.melee)
            equipmentRow
            perkRow
            Spacer()
        }
        .frame(width: 230)
    }

    private func slotButton(_ slot: LoadoutSlot, build: WeaponBuild) -> some View {
        let weapon = build.resolved()
        return Button {
            editingSlot = slot
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.displayName.uppercased())
                    .font(Theme.caption(9))
                    .foregroundStyle(Theme.textTertiary)
                Text(weapon.name)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    RarityBadge(rarity: weapon.rarity)
                    if !build.normalizedAttachments.isEmpty {
                        Text("\(build.normalizedAttachments.count) parts")
                            .font(Theme.caption(9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .fill(editingSlot == slot ? Theme.accent.opacity(0.14) : Theme.surfaceElevated))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                .strokeBorder(editingSlot == slot ? Theme.accent : Theme.stroke, lineWidth: 1))
        }
    }

    private var equipmentRow: some View {
        HStack(spacing: 8) {
            equipmentPicker(title: "Lethal", current: loadout.lethal,
                            options: GrenadeDatabase.grenades(forSlot: .lethal)) { id in
                app.updateSelectedLoadout { $0.lethal = id }
            }
            equipmentPicker(title: "Tactical", current: loadout.tactical,
                            options: GrenadeDatabase.grenades(forSlot: .tactical)) { id in
                app.updateSelectedLoadout { $0.tactical = id }
            }
        }
    }

    private func equipmentPicker(title: String, current: ContentID, options: [GrenadeData],
                                 onSelect: @escaping (ContentID) -> Void) -> some View {
        Menu {
            ForEach(options) { grenade in
                Button {
                    guard grenade.unlockLevel <= profile.level else {
                        app.showToast("Unlocks at level \(grenade.unlockLevel)", style: .warning)
                        return
                    }
                    onSelect(grenade.id)
                } label: {
                    Label(grenade.name, systemImage: grenade.unlockLevel <= profile.level
                          ? "checkmark.circle" : "lock.fill")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(Theme.caption(9))
                    .foregroundStyle(Theme.textTertiary)
                Text(GrenadeDatabase.grenade(current)?.name ?? "—")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated))
        }
    }

    private var perkRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PERKS")
                .font(Theme.caption(9))
                .foregroundStyle(Theme.textTertiary)
            ForEach(1...3, id: \.self) { tier in
                Menu {
                    ForEach(PerkDatabase.perks(tier: tier)) { perk in
                        Button {
                            guard profile.unlocks.hasPerk(perk.id), perk.unlockLevel <= profile.level else {
                                app.showToast("Unlocks at level \(perk.unlockLevel)", style: .warning)
                                return
                            }
                            app.updateSelectedLoadout { current in
                                var perks = current.perks.filter {
                                    PerkDatabase.perk($0)?.tier != tier
                                }
                                perks.append(perk.id)
                                current.perks = perks
                            }
                        } label: {
                            Text("\(perk.name) — \(perk.description)")
                        }
                    }
                } label: {
                    let selected = loadout.perks.compactMap(PerkDatabase.perk).first { $0.tier == tier }
                    HStack {
                        Text(selected?.name ?? "Empty")
                            .font(Theme.body(12))
                            .foregroundStyle(selected == nil ? Theme.textTertiary : Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surfaceElevated))
                }
            }
        }
    }

    // MARK: Weapon detail

    private var weaponDetail: some View {
        let build = loadout.build(for: editingSlot) ?? loadout.primary
        let weapon = build.resolved()
        let base = WeaponDatabase.weaponOrDefault(build.weapon)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weapon.name).font(Theme.display(20)).foregroundStyle(Theme.textPrimary)
                    Text(weapon.weaponClass.displayName)
                        .font(Theme.caption(11)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Change Weapon") { app.go(to: .armory) }
                    .buttonStyle(SecondaryButtonStyle())
            }

            VStack(spacing: 5) {
                ForEach(weapon.statBars.stats) { stat in
                    StatBarRow(label: stat.name, value: stat.value,
                               comparison: base.statBars.value(named: stat.name))
                }
            }

            Text("ATTACHMENTS")
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textTertiary)

            ScrollView {
                ForEach(AttachmentSlot.allCases, id: \.self) { slot in
                    attachmentRow(slot: slot, build: build)
                }
            }

            HStack {
                Text("\(profile.unlocks.kills(with: build.weapon)) kills")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("Weapon level \(profile.unlocks.weaponLevel(build.weapon))")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panel()
    }

    private func attachmentRow(slot: AttachmentSlot, build: WeaponBuild) -> some View {
        let options = AttachmentDatabase.attachments(for: slot)
        let equipped = build.normalizedAttachments.first {
            AttachmentDatabase.attachment($0)?.slot == slot
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(slot.displayName.uppercased())
                .font(Theme.caption(9))
                .foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options) { attachment in
                        let unlocked = profile.unlocks.hasAttachment(attachment.id, on: build.weapon)
                        let kills = profile.unlocks.kills(with: build.weapon)
                        Button {
                            guard unlocked else {
                                app.showToast("\(attachment.unlockKills - kills) more kills",
                                              style: .warning)
                                return
                            }
                            app.toggleAttachment(attachment.id, slot: editingSlot)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.name)
                                    .font(Theme.caption(11))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(attachment.description)
                                    .font(Theme.caption(8))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(2)
                            }
                            .frame(width: 132, height: 52, alignment: .topLeading)
                            .padding(7)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(equipped == attachment.id
                                      ? Theme.accent.opacity(0.18) : Theme.surfaceElevated))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(equipped == attachment.id ? Theme.accent : Theme.stroke,
                                              lineWidth: 1))
                            .overlay {
                                if !unlocked {
                                    LockedOverlay(requirement: "\(attachment.unlockKills) kills")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}

struct ArmoryView: View {
    @EnvironmentObject private var app: AppState
    @State private var category: WeaponClass = .assaultRifle

    private var profile: PlayerProfile { app.profile }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Armory", subtitle: "\(profile.unlocks.weapons.count) weapons owned",
                         onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: profile.wallet) { app.go(to: .store) }))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WeaponClass.allCases, id: \.self) { option in
                        Button(option.displayName) { category = option }
                            .buttonStyle(SecondaryButtonStyle())
                            .opacity(category == option ? 1 : 0.5)
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(WeaponDatabase.weapons(of: category)) { weapon in
                        weaponCard(weapon)
                    }
                }
            }
        }
        .padding(16)
    }

    private func weaponCard(_ weapon: WeaponData) -> some View {
        let owned = profile.unlocks.hasWeapon(weapon.id)
        let levelLocked = weapon.unlockLevel > profile.level
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(weapon.name).font(Theme.title(15)).foregroundStyle(Theme.textPrimary)
                Spacer()
                RarityBadge(rarity: weapon.rarity)
            }
            HStack(spacing: 10) {
                miniStat("DPS", String(format: "%.0f", weapon.damagePerSecond))
                miniStat("TTK", String(format: "%.2fs", DamageModel.timeToKill(weapon: weapon)))
                miniStat("MAG", "\(weapon.magazineSize)")
            }
            ForEach(weapon.statBars.stats.prefix(3)) { stat in
                StatBarRow(label: stat.name, value: stat.value)
            }
            if owned {
                Button("Equip") {
                    app.equipWeapon(weapon.id, slot: weapon.weaponClass.slot)
                    app.go(to: .loadout)
                }
                .buttonStyle(SecondaryButtonStyle(wide: true))
            } else if levelLocked {
                Text("Unlocks at level \(weapon.unlockLevel)")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            } else {
                Button {
                    app.buyWeapon(weapon.id)
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: weapon.storeCostCoins > 0
                                        ? CurrencyKind.coins.colorHex : CurrencyKind.gems.colorHex))
                            .frame(width: 8, height: 8)
                        Text("\(weapon.storeCostCoins > 0 ? weapon.storeCostCoins : weapon.storeCostGems)")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(wide: true))
            }
        }
        .padding(11)
        .panel(elevated: true)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
            Text(label).font(Theme.caption(8)).foregroundStyle(Theme.textTertiary)
        }
    }
}
