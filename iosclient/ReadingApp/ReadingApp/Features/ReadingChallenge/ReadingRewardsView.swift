import SwiftUI

private enum RewardsReferencePalette {
    static let ink = ReadingChallengeTheme.ink
    static let muted = ReadingChallengeTheme.muted
    static let accent = ReadingChallengeTheme.accent
    static let heading = ReadingChallengeTheme.ink
    static let buttonFill = ReadingChallengeTheme.color(0x0057ED, dark: 0x1455CB)
    static let neutral = ReadingChallengeTheme.softBlue
    static let blush = ReadingChallengeTheme.softBlue
    static let gold = ReadingChallengeTheme.heroGold
    static let badge = ReadingChallengeTheme.surface.opacity(0.6)
    static let cardGradient = ReadingChallengeTheme.heroGradient

    static func tier(_ stars: Int, stronger: Bool = false) -> Color {
        // Reward levels share the same blue family; stars and labels identify the tier.
        stronger ? ReadingChallengeTheme.color(0xE3EEFF, dark: 0x223853) : ReadingChallengeTheme.softBlue
    }
}

/// Pastel pairs apply only to the seven reward rows, preserving the blue page theme.
private enum RewardTierRowPalette {
    private static let light: [(UInt32, UInt32)] = [
        (0xFFF0ED, 0xFFDEDB), // Pink
        (0xFFF5E6, 0xFFECCB), // Orange
        (0xFFFBE8, 0xFFF5CD), // Yellow
        (0xF0FFF0, 0xE1FDE4), // Green
        (0xE6FFFB, 0xCDFBF3), // Teal
        (0xE8F4FF, 0xD3E8FF), // Blue
        (0xFAF0FF, 0xF0DEFC)  // Purple
    ]
    private static let dark: [(UInt32, UInt32)] = [
        (0x36262B, 0x482C32), (0x352D24, 0x443629),
        (0x333024, 0x403B27), (0x26332B, 0x2B4031),
        (0x253433, 0x29423E), (0x27323E, 0x2B3E52),
        (0x322B3B, 0x40314C)
    ]

    static func outline(_ stars: Int) -> Color {
        let light: [UInt32] = [0xE7BCB7, 0xE5C691, 0xDBD095, 0xADD3B4, 0x9ACFC5, 0xA9C8E7, 0xCCB6E0]
        let dark: [UInt32] = [0x79545D, 0x7B684A, 0x777049, 0x52725C, 0x4D756E, 0x526D8A, 0x705B84]
        let index = min(max(stars - 1, 0), light.count - 1)
        return ReadingChallengeTheme.color(light[index], dark: dark[index])
    }

    static func color(_ stars: Int, stronger: Bool = false) -> Color {
        let index = min(max(stars - 1, 0), light.count - 1)
        let day = light[index]
        let night = dark[index]
        return ReadingChallengeTheme.color(stronger ? day.1 : day.0, dark: stronger ? night.1 : night.0)
    }
}

private enum ReadingCalendarColors {
    static let pending = ReadingChallengeTheme.color(0xF4F7FC, dark: 0x202A3A)
    static let outline = ReadingChallengeTheme.color(0xC8D5E8, dark: 0x53647C)
    static let gold = ReadingChallengeTheme.color(0xB47700, dark: 0xFFD05C)
    static let earned = ReadingChallengeTheme.color(0xFFF7DA, dark: 0x3D3421)
    static let goldOutline = ReadingChallengeTheme.color(0xFFCB43, dark: 0xA88C4E)
    static let caption = ReadingChallengeTheme.color(0x8D9DB5, dark: 0xA8B9D1)
}

struct ReadingRewardsView: View {
    @ObservedObject var store: ReadingChallengeStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ReadingLoadStatus(store: store)
                challengeHero
                footprints
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("七颗星，七份期待", systemImage: "sparkles").font(.title3.bold()).foregroundStyle(RewardsReferencePalette.heading)
                        Spacer(minLength: 0)
                    }
                    Text("周期结束按最高档发券，奖励不叠加。")
                        .font(.subheadline).foregroundStyle(RewardsReferencePalette.muted)
                    ForEach(store.tiers, id: \.days) { tier in tierRow(tier) }
                }.padding(16).background(ReadingChallengeTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                NavigationLink { ReadingVoucherWallet(store: store) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "ticket.fill").font(.title2).foregroundStyle(.white)
                        Text("查看我的兑换券").font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right").font(.headline)
                    }.foregroundStyle(.white).padding(20)
                        .background(RewardsReferencePalette.buttonFill, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .foregroundStyle(RewardsReferencePalette.ink)
        .background(ReadingChallengeTheme.canvas.ignoresSafeArea())
        .navigationTitle("七星挑战").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .readingRewardScrollAppearance()
        .tint(ReadingChallengeTheme.accent)
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    private var challengeHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label {
                    Text("30 天阅读挑战").foregroundStyle(ReadingChallengeTheme.onHeroSecondary)
                } icon: {
                    Image(systemName: "star.fill").foregroundStyle(ReadingChallengeTheme.heroGold)
                }.font(.headline)
                Spacer(minLength: 8)
                Text("最高 ¥50").font(.caption.bold()).foregroundStyle(ReadingChallengeTheme.heroGold)
                    .padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.20), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(store.completedDays)").font(.system(size: 54, weight: .medium, design: .rounded))
                Text("/ 30 个达标日").font(.headline).foregroundStyle(ReadingChallengeTheme.onHeroSecondary)
            }
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1).accessibilityHidden(true)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.tier.title).font(.headline)
                    if let next = store.tiers.first(where: { $0.days > store.completedDays }) {
                        Text("再达标 \(next.days - store.completedDays) 天，解锁\(next.title) ¥\(next.amount)")
                            .font(.caption).foregroundStyle(ReadingChallengeTheme.onHeroSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if store.tier.stars == 7 {
                        Text("七星点亮！本周期奖励 50 元").font(.caption)
                    } else {
                        Text("挑战进度尚未加载").font(.caption)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("预计").font(.caption).foregroundStyle(ReadingChallengeTheme.onHeroSecondary)
                    Text("¥\(store.tier.amount)").font(.title2.bold()).foregroundStyle(ReadingChallengeTheme.heroGold)
                }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
            .background(RewardsReferencePalette.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: ReadingChallengeTheme.accent.opacity(0.14), radius: 16, y: 10)
    }

    private var footprints: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("把每一天点亮").foregroundStyle(ReadingChallengeTheme.ink)
            } icon: {
                Image(systemName: "sun.max.fill").foregroundStyle(ReadingChallengeTheme.gold)
            }.font(.headline)
            if let cycle = store.cycle {
                Text("\(cycle.startsOn) — \(cycle.endsOn)").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 9) {
                ForEach(1...30, id: \.self) { day in
                    let completed = store.cycle?.completed(on: day) == true
                    VStack(spacing: 5) {
                        Image(systemName: completed ? "star.fill" : "star")
                            .font(.system(size: 19, weight: completed ? .semibold : .light))
                            .foregroundStyle(completed ? ReadingChallengeTheme.gold : ReadingCalendarColors.caption)
                        Text("\(day)").font(.caption.bold())
                            .foregroundStyle(completed ? ReadingCalendarColors.gold : ReadingCalendarColors.caption)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(completed ? ReadingCalendarColors.earned : ReadingCalendarColors.pending, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(
                            completed ? ReadingCalendarColors.goldOutline : ReadingCalendarColors.outline,
                            style: StrokeStyle(lineWidth: 1, dash: completed ? [] : [3, 2])
                        )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("周期第 \(day) 天，\(completed ? "已完成" : "待完成")")
                }
            }
            Text("每天完成阅读任务点亮一颗星，漏学不清零。")
                .font(.caption).foregroundStyle(ReadingChallengeTheme.muted)
        }.padding(20).background(ReadingChallengeTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func tierRow(_ tier: ReadingRewardTier) -> some View {
        let isCurrent = tier == store.tier
        let isEarned = tier.stars <= store.tier.stars
        let statusColor = isEarned ? ReadingCalendarColors.gold : ReadingCalendarColors.caption
        return HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(RewardsReferencePalette.badge).frame(width: 52, height: 58)
                VStack(spacing: 2) {
                    Image(systemName: tier.stars == 7 ? (isEarned ? "crown.fill" : "crown") : (isEarned ? "star.fill" : "star"))
                        .font(.title3).foregroundStyle(isEarned ? ReadingChallengeTheme.gold : RewardsReferencePalette.muted)
                    Text("\(tier.stars)").font(.caption.bold())
                }.foregroundStyle(statusColor)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(tier.title).font(.headline)
                Text("累计达标 \(tier.days) 天").font(.caption).foregroundStyle(RewardsReferencePalette.muted)
                Text(isCurrent ? "当前星级" : (isEarned ? "已达成" : "待达成"))
                    .font(.caption2.bold()).foregroundStyle(statusColor)
            }
            Spacer(minLength: 4)
            Text("¥\(tier.amount)").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(RewardsReferencePalette.ink)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                HStack(spacing: 0) {
                    RewardTierRowPalette.color(tier.stars)
                    RewardTierRowPalette.color(tier.stars, stronger: true)
                }.clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RewardTierRowPalette.outline(tier.stars).opacity(isCurrent ? 1 : 0), lineWidth: 1))
    }
}

struct ReadingVoucherWallet: View {
    @ObservedObject var store: ReadingChallengeStore
    @State private var listState = ReadingVoucherListState()
    private var showRedeemed: Bool { listState.showRedeemed }
    private var displayed: [ReadingVoucher] { listState.displayed(from: store.vouchers) }
    private var unredeemedCount: Int { store.vouchers.filter { $0.redeemedAt == nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                walletHero
                ReadingLoadStatus(store: store)
                HStack(spacing: 8) {
                    filterButton("未兑换", redeemed: false, count: unredeemedCount)
                    filterButton("已兑换", redeemed: true, count: store.vouchers.count - unredeemedCount)
                }.padding(4).background(ReadingChallengeTheme.track, in: RoundedRectangle(cornerRadius: 18))
                if displayed.isEmpty && !store.isLoading && store.errorMessage == nil { emptyWallet }
                ForEach(displayed) { voucher in voucherCard(voucher) }
                Label {
                    Text("给家长看兑换券，拿到奖励后再点击“兑换”。")
                } icon: { Image(systemName: "heart.fill").foregroundStyle(ReadingChallengeTheme.pink) }
                    .font(.caption).foregroundStyle(RewardsReferencePalette.muted).padding(.horizontal, 4)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.foregroundStyle(RewardsReferencePalette.ink)
            .background(ReadingChallengeTheme.canvas.ignoresSafeArea())
            .navigationTitle("我的兑换券").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .readingRewardScrollAppearance()
            .tint(ReadingChallengeTheme.accent)
            .task { await store.refresh() }
            .refreshable { await store.refresh() }
            .onDisappear { listState.clearFeedback() }
    }

    private var walletHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("阅读收获的小惊喜", systemImage: "gift.fill").font(.subheadline.bold()).foregroundStyle(ReadingChallengeTheme.onHeroSecondary)
            Text("每一份努力\n都值得被奖励").font(.system(size: 29, weight: .bold, design: .rounded))
            HStack(spacing: 7) {
                Image(systemName: "ticket.fill").foregroundStyle(ReadingChallengeTheme.pink)
                Text("\(unredeemedCount) 张奖励券待兑换").font(.subheadline.bold())
            }.padding(.horizontal, 13).padding(.vertical, 10)
                .background(.white.opacity(0.22), in: Capsule())
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
            .background(RewardsReferencePalette.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: 26))

    }

    private func filterButton(_ title: String, redeemed: Bool, count: Int) -> some View {
        let selected = showRedeemed == redeemed
        return Button { listState.select(redeemed: redeemed) } label: {
            HStack(spacing: 7) {
                Text(title).font(.subheadline.bold())
                Text("\(count)").font(.caption.bold()).opacity(0.7)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(selected ? RewardsReferencePalette.accent : RewardsReferencePalette.muted)
                .background(selected ? ReadingChallengeTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyWallet: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(RewardsReferencePalette.blush).frame(width: 116, height: 116)
                Image(systemName: showRedeemed ? "checkmark.seal.fill" : "ticket.fill")
                    .font(.system(size: 42)).foregroundStyle(ReadingChallengeTheme.pink)
                    .rotationEffect(.degrees(showRedeemed ? 0 : -14))
            }.accessibilityHidden(true)
            Text(showRedeemed ? "收藏每一次兑现的快乐" : "下一份惊喜，等你来解锁").font(.title3.bold())
            Text(showRedeemed ? "还没有已兑换的券。\n兑现奖励后，这里会留下你的收获。" : "还没有未兑换的券。\n完成 30 天周期并达到奖励档位后，\n就能收获属于你的阅读奖励券。")
                .font(.subheadline).foregroundStyle(RewardsReferencePalette.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 20).padding(.vertical, 32).frame(maxWidth: .infinity)
            .background(ReadingChallengeTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func voucherCard(_ voucher: ReadingVoucher) -> some View {
        let justRedeemed = listState.recentlyRedeemedIDs.contains(voucher.id)
        let redeemed = voucher.redeemedAt != nil && !justRedeemed
        let accent = redeemed ? RewardsReferencePalette.muted : RewardsReferencePalette.accent
        let stars = voucher.stars
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Label("阅读奖励兑换券", systemImage: "ticket.fill").font(.headline)
                Spacer(minLength: 6)
                Text(voucher.redeemedAt != nil ? "已兑换" : "待兑换").font(.caption.bold())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(accent.opacity(0.10), in: Capsule())
            }.foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(.title.bold())
                Text("\(voucher.amount)").font(.system(size: 64, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: redeemed ? "checkmark.seal.fill" : "gift.fill").font(.system(size: 40))
                    .foregroundStyle(redeemed ? RewardsReferencePalette.muted.opacity(0.4) : RewardsReferencePalette.gold)
            }.foregroundStyle(accent)
            Text("\(voucher.tier.title) · 累计达标 \(voucher.days) 天")
                .font(.headline)
            TicketPerforation().stroke(accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 5])).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("来源：30 天阅读周期")
                Text("券号：\(voucher.id)").textSelection(.enabled)
                Text("发放时间：\(voucher.issuedAt.formatted(date: .abbreviated, time: .shortened))")
            }.font(.caption).foregroundStyle(RewardsReferencePalette.muted)
            if let date = voucher.redeemedAt, !justRedeemed {
                Label("奖励已兑现，努力被看见", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(RewardsReferencePalette.muted)
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(RewardsReferencePalette.muted)
            } else {
                Button {
                    Task {
                        if await store.redeem(voucher.id) { listState.didRedeem(voucher.id) }
                    }
                } label: {
                    Label(justRedeemed ? "兑换成功" : (store.redeemingIDs.contains(voucher.id) ? "兑换中…" : "兑换"), systemImage: "checkmark.circle.fill").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(justRedeemed ? ReadingChallengeTheme.accent : .white)
                        .background(justRedeemed ? ReadingChallengeTheme.softBlue : RewardsReferencePalette.buttonFill, in: RoundedRectangle(cornerRadius: 15))
                }.buttonStyle(.plain).disabled(voucher.redeemedAt != nil || store.redeemingIDs.contains(voucher.id))
                    .accessibilityIdentifier("redeemReadingVoucher")
                Text("家长兑现后再点击，无需家长在 App 中确认。")
                    .font(.caption).foregroundStyle(RewardsReferencePalette.muted)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(
                colors: redeemed ? [ReadingChallengeTheme.surface, RewardsReferencePalette.neutral] : [RewardsReferencePalette.tier(stars), RewardsReferencePalette.tier(stars, stronger: true)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .clipShape(RewardTicketShape())
            .overlay(RewardTicketShape().stroke(accent.opacity(0.25), lineWidth: 1))
            .shadow(color: accent.opacity(0.10), radius: 10, y: 5)
    }
}

private struct TicketPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in path.move(to: CGPoint(x: 0, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

private struct RewardTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 24
        let notchY = min(210, rect.height * 0.46)
        return Path { path in
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: rect.width - r, y: 0))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: rect.width, y: notchY - 12))
            path.addQuadCurve(to: CGPoint(x: rect.width, y: notchY + 12), control: CGPoint(x: rect.width - 24, y: notchY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
            path.addQuadCurve(to: CGPoint(x: rect.width - r, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: r, y: rect.height))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - r), control: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: notchY + 12))
            path.addQuadCurve(to: CGPoint(x: 0, y: notchY - 12), control: CGPoint(x: 24, y: notchY))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
            path.closeSubpath()
        }
    }
}
