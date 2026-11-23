import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct AdsView: View {
    @State private var campaigns: [AdCampaign] = []
    @State private var isLoading = true
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var now = Date()
    @State private var busyCampaignIDs: Set<String> = []
    @State private var deletingCampaignID: String?
    @State private var wallet: AdsWalletModel?
    @State private var walletBusy = false

    @State private var editingCampaignID: String?
    @State private var editingCreativeID: String?

    @State private var campaignName = ""
    @State private var placement = "video"
    @State private var status = "draft"
    /// Empty = Worldwide. Non-empty ISO-2 tags from `AdsCountryTargetField`.
    @State private var targetCountryCodes: [String] = []
    @State private var budgetEUR = ""
    @State private var dailyBudgetEUR = ""
    @State private var startAt = Date()
    @State private var endAt = Date()
    @State private var hasStartAt = false
    @State private var hasEndAt = false

    @State private var creativeTitle = ""
    @State private var creativeBody = ""
    @State private var creativeMediaURL = ""
    @State private var clickURL = ""
    @State private var ctaLabel = "Learn more"
    @State private var durationSeconds = 8
    @State private var creativeUploadName = ""
    @State private var uploadingCreative = false
    @State private var selectedVideo: PhotosPickerItem?

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroSection
                composerSection
                campaignsSection
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .screenBackground()
        .navigationTitle("Ads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .refreshable {
            await refreshWallet()
            await loadCampaigns()
        }
        .task {
            await refreshWallet()
            await loadCampaigns()
            try? await Task.sleep(nanoseconds: 900_000_000)
            await loadCampaigns(silent: true)
        }
        .onReceive(clock) { now = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshWallet() }
        }
        // accentBright is matte/off-white — on paper it made nav titles + controls invisible.
        .tint(Theme.ink)
        .preferredColorScheme(.light)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matterya Ads")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
                .tracking(1.2)
            Text("Advertiser dashboard")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Set your own budget, target Worldwide or specific countries, upload a video creative, and reach people in Sparks and Hubs. You control spend — Matterya estimates impressions and views from your budget.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Campaign create is free. Delivery spends from your prepaid wallet (~€0.10 per impression).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
                .padding(.top, 4)
            walletCard
        }
        .adsCard()
    }

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ads wallet")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(wallet?.formattedBalance ?? "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            if let wallet {
                Text(
                    wallet.billingConfigured
                    ? (wallet.hasPaymentMethod
                       ? "Card on file · funds are used as ads deliver."
                       : "Add a card, then top up to run Active campaigns.")
                    : "Billing not configured yet (Stripe keys on server)."
                )
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                walletButton("Add card", busy: walletBusy) {
                    await openCheckout(kind: "setup", amountCents: nil)
                }
                walletButton("€20", busy: walletBusy) {
                    await openCheckout(kind: "topup", amountCents: 2000)
                }
                walletButton("€50", busy: walletBusy) {
                    await openCheckout(kind: "topup", amountCents: 5000)
                }
                walletButton("€100", busy: walletBusy) {
                    await openCheckout(kind: "topup", amountCents: 10000)
                }
            }
        }
        .padding(.top, 8)
    }

    private func walletButton(_ title: String, busy: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.matte.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - Composer

    private var composerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editingCampaignID == nil ? "New campaign" : "Edit campaign")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(editingCampaignID == nil
                         ? "Upload one video creative, then activate the campaign."
                         : "Update campaign settings and replace the video creative at any time.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if editingCampaignID != nil {
                    Button("Cancel") { cancelEdit() }
                        .buttonStyle(MatteryaSecondaryButtonStyle())
                        .fixedSize()
                        .disabled(saving)
                }
            }

            // Single column on phone — 2-up grids crushed labels/date pickers.
            VStack(alignment: .leading, spacing: 14) {
                PremiumTextField(title: "Name", text: $campaignName)
                adsPicker(title: "Placement", selection: $placement, options: [("video", "Video"), ("reel", MatteryaCopy.spark)])
                adsPicker(title: "Status", selection: $status, options: [("draft", "Draft"), ("active", "Active"), ("paused", "Paused")])
                AdsCountryTargetField(selectedCodes: $targetCountryCodes)
                PremiumTextField(title: "Total budget (EUR)", text: $budgetEUR, keyboard: .decimalPad)
                PremiumTextField(title: "Daily budget (EUR)", text: $dailyBudgetEUR, keyboard: .decimalPad)
                budgetEstimateCard
                scheduleToggle(title: "Start", isOn: $hasStartAt, date: $startAt)
                scheduleToggle(title: "End", isOn: $hasEndAt, date: $endAt)
            }

            uploadRow

            if !creativeUploadName.isEmpty {
                Text("Uploaded: \(creativeUploadName)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if !creativeMediaURL.isEmpty, let previewURL = URL(string: creativeMediaURL) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Creative preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                    Text("This hosted file is the one used for pre-roll delivery.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    VideoPlayer(player: AVPlayer(url: previewURL))
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .padding(14)
                .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 14) {
                PremiumTextField(title: "Creative title", text: $creativeTitle)
                PremiumTextField(title: "CTA label", text: $ctaLabel)
                PremiumTextField(title: "Click URL", text: $clickURL, keyboard: .URL)
                durationField
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Ad copy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                TextField("Optional ad copy shown in the pre-roll overlay", text: $creativeBody, axis: .vertical)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            }

            if let successMessage {
                statusBanner(successMessage, isError: false)
            }
            if let errorMessage {
                statusBanner(errorMessage, isError: true)
            }

            Button {
                Task { await saveCampaign() }
            } label: {
                Text(createButtonTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(
                saving
                    || campaignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || creativeMediaURL.isEmpty
            )
        }
        .adsCard()
        .onChange(of: selectedVideo) { _, item in
            Task { await uploadCreative(item) }
        }
    }

    private var budgetEstimateCard: some View {
        let snap = AdsBudgetEstimate.snapshot(
            totalBudgetEUR: Double(budgetEUR.replacingOccurrences(of: ",", with: ".")) ?? 0,
            dailyBudgetEUR: Double(dailyBudgetEUR.replacingOccurrences(of: ",", with: ".")) ?? 0
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text("Estimated reach")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            if snap.totalImpressions <= 0 && snap.dailyImpressions <= 0 {
                Text("Enter a total or daily budget to see estimated impressions and views.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if snap.totalImpressions > 0 {
                    estimateRow(
                        title: "Total budget",
                        impressions: snap.totalImpressions,
                        views: snap.totalViews
                    )
                }
                if snap.dailyImpressions > 0 {
                    estimateRow(
                        title: "Daily budget",
                        impressions: snap.dailyImpressions,
                        views: snap.dailyViews
                    )
                }
                Text(
                    String(
                        format: "Estimates use Matterya’s rate (≈ €%.2f / impression, ~€%.0f CPM). Your wallet needs about €%.2f for the total budget. Actual results vary.",
                        snap.costPerImpressionEUR,
                        snap.effectiveCPM,
                        Double(snap.totalImpressions) * snap.costPerImpressionEUR
                    )
                )
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func estimateRow(title: String, impressions: Int, views: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text("~\(Self.formatCount(impressions)) impressions · ~\(Self.formatCount(views)) video views")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    private static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var createButtonTitle: String {
        if saving {
            return editingCampaignID == nil ? "Creating…" : "Saving…"
        }
        if editingCampaignID != nil {
            return "Save changes"
        }
        return "Create campaign"
    }

    private var uploadRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload creative video")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                Text("Upload one ad video file. The hosted URL is generated automatically.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                Text(uploadingCreative ? "Uploading…" : "Upload video")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            }
            .disabled(uploadingCreative)
        }
        .padding(14)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    private var durationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Duration (sec)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Stepper("\(durationSeconds)s", value: $durationSeconds, in: 3...30)
                .foregroundStyle(Theme.ink)
                .tint(Theme.ink)
                .padding(12)
                .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
        }
    }

    private func adsPicker(title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }

    private func scheduleToggle(title: String, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .tint(Theme.ink)
            if isOn.wrappedValue {
                DatePicker("", selection: date)
                    .labelsHidden()
                    .tint(Theme.ink)
                    .colorScheme(.light)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            }
        }
    }

    private func statusBanner(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(isError ? Theme.danger : Theme.success)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                (isError ? Theme.danger : Theme.success).opacity(0.1),
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )
    }

    // MARK: - Campaigns List

    private var campaignsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Campaigns")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(isLoading ? "Refreshing…" : "Refresh") {
                    Task { await loadCampaigns() }
                }
                .buttonStyle(MatteryaSecondaryButtonStyle())
                .fixedSize()
                .disabled(isLoading)
            }

            if isLoading && campaigns.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if campaigns.isEmpty {
                Text("No campaigns yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ForEach(campaigns) { campaign in
                    campaignCard(campaign)
                }
            }
        }
        .adsCard()
    }

    private func campaignCard(_ campaign: AdCampaign) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(campaign.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                FlowPills(items: campaignMetaPills(campaign))
            }

            HStack(spacing: 10) {
                statPill(value: campaign.impressionCount, label: "Impressions")
                statPill(value: campaign.clickCount, label: "Clicks")
                Spacer(minLength: 0)
            }

            FlowPills(items: budgetPills(campaign))

            Text(campaignTimerText(campaign))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !campaign.creatives.isEmpty {
                VStack(spacing: 8) {
                    ForEach(campaign.creatives) { creative in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(creative.title ?? "Creative")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text("\(creative.mediaKind) · \(creative.durationSeconds)s")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.inkMuted)
                            }
                            Text(creative.body ?? creative.mediaURL)
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    actionButton("Edit", campaign: campaign) { beginEdit(campaign) }
                    actionButton("Draft", campaign: campaign) { await setStatus(campaign, status: "draft") }
                    actionButton("Activate", campaign: campaign) { await setStatus(campaign, status: "active") }
                    actionButton("Pause", campaign: campaign) { await setStatus(campaign, status: "paused") }
                    Button {
                        Task { await deleteCampaign(campaign) }
                    } label: {
                        Text(deletingCampaignID == campaign.id ? "Deleting…" : "Delete")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }
                    .disabled(isCampaignBusy(campaign.id))
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func statPill(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func actionButton(_ title: String, campaign: AdCampaign, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.buttonMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .disabled(isCampaignBusy(campaign.id))
    }

    // MARK: - Actions

    private func refreshWallet() async {
        do {
            wallet = try await AdsService.shared.adsWallet()
        } catch {
            #if DEBUG
            print("[Ads] wallet refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func openCheckout(kind: String, amountCents: Int?) async {
        walletBusy = true
        defer { walletBusy = false }
        do {
            let url = try await AdsService.shared.createAdsWalletCheckout(
                kind: kind,
                amountCents: amountCents
            )
            await UIApplication.shared.open(url)
            successMessage = kind == "setup"
                ? "Finish adding your card in the browser, then return here."
                : "Finish payment in the browser, then return here — balance updates in a few seconds."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCampaigns(silent: Bool = false) async {
        if !silent { isLoading = true }
        if !silent { errorMessage = nil }
        defer { if !silent { isLoading = false } }
        do {
            campaigns = try await AdsService.shared.myCampaigns()
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    private func saveCampaign() async {
        guard !saving else { return }
        guard !creativeMediaURL.isEmpty else {
            errorMessage = "Upload a creative video first."
            return
        }

        saving = true
        errorMessage = nil
        successMessage = nil
        defer { saving = false }

        let input = AdCampaignInput(
            name: campaignName.trimmingCharacters(in: .whitespacesAndNewlines),
            placement: placement,
            status: status,
            targetCountryCodes: targetCountryCodes.map { $0.uppercased() },
            budgetCents: toCents(budgetEUR),
            dailyBudgetCents: toCents(dailyBudgetEUR),
            startAt: hasStartAt ? isoString(startAt) : nil,
            endAt: hasEndAt ? isoString(endAt) : nil
        )

        let creativeInput = AdCreativeInput(
            title: creativeTitle.nilIfEmpty,
            body: creativeBody.nilIfEmpty,
            mediaKind: "video",
            mediaURL: creativeMediaURL,
            clickURL: clickURL.nilIfEmpty,
            ctaLabel: ctaLabel.nilIfEmpty,
            durationSeconds: durationSeconds
        )

        do {
            if let editingCampaignID {
                let updated = try await AdsService.shared.updateCampaign(campaignID: editingCampaignID, input: input)
                if let editingCreativeID {
                    _ = try await AdsService.shared.updateCreative(creativeID: editingCreativeID, input: creativeInput)
                } else {
                    _ = try await AdsService.shared.createCreative(campaignID: updated.id, input: creativeInput)
                }
                successMessage = "Campaign updated."
            } else {
                // Create is free — advertiser-set budgets drive delivery estimates + pacing.
                let campaign = try await AdsService.shared.createCampaign(input: input)
                _ = try await AdsService.shared.createCreative(campaignID: campaign.id, input: creativeInput)
                successMessage = "Campaign created."
            }
            resetForm()
            await loadCampaigns(silent: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setStatus(_ campaign: AdCampaign, status newStatus: String) async {
        guard !isCampaignBusy(campaign.id) else { return }
        if campaign.status.lowercased() == newStatus.lowercased() {
            successMessage = "Campaign already \(newStatus)."
            errorMessage = nil
            return
        }

        busyCampaignIDs.insert(campaign.id)
        errorMessage = nil
        successMessage = nil
        defer { busyCampaignIDs.remove(campaign.id) }

        let input = AdCampaignInput(
            name: campaign.name,
            placement: campaign.placement,
            status: newStatus,
            targetCountryCodes: campaign.targetCountryCodes,
            budgetCents: campaign.budgetCents,
            dailyBudgetCents: campaign.dailyBudgetCents,
            startAt: campaign.startAt,
            endAt: campaign.endAt
        )

        do {
            let updated = try await AdsService.shared.updateCampaign(campaignID: campaign.id, input: input)
            campaigns = campaigns.map { $0.id == updated.id ? updated : $0 }
            successMessage = "Campaign set to \(newStatus)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCampaign(_ campaign: AdCampaign) async {
        guard !isCampaignBusy(campaign.id) else { return }
        busyCampaignIDs.insert(campaign.id)
        deletingCampaignID = campaign.id
        errorMessage = nil
        successMessage = nil
        defer {
            busyCampaignIDs.remove(campaign.id)
            deletingCampaignID = nil
        }

        do {
            let deleted = try await AdsService.shared.deleteCampaign(campaignID: campaign.id)
            guard deleted else { throw NSError(domain: "Ads", code: 1, userInfo: [NSLocalizedDescriptionKey: "Delete was not applied."]) }
            campaigns.removeAll { $0.id == campaign.id }
            if editingCampaignID == campaign.id { resetForm() }
            successMessage = "Campaign deleted."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadCreative(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploadingCreative = true
        errorMessage = nil
        successMessage = nil
        defer {
            uploadingCreative = false
            selectedVideo = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw MediaError.uploadFailed("Could not read video file.")
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mp4"
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
            let uploaded = try await MediaService.shared.uploadAdMedia(data: data, fileExtension: ext, mimeType: mime)
            creativeMediaURL = uploaded.publicURL
            creativeUploadName = "video.\(ext)"
            successMessage = "Creative video uploaded."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginEdit(_ campaign: AdCampaign) {
        let creative = campaign.creatives.first
        editingCampaignID = campaign.id
        editingCreativeID = creative?.id
        campaignName = campaign.name
        placement = campaign.placement
        status = campaign.status
        targetCountryCodes = campaign.targetCountryCodes.map { $0.uppercased() }
        budgetEUR = String(format: "%.2f", Double(campaign.budgetCents) / 100)
        dailyBudgetEUR = String(format: "%.2f", Double(campaign.dailyBudgetCents) / 100)
        if let start = parseDate(campaign.startAt) {
            hasStartAt = true
            startAt = start
        } else {
            hasStartAt = false
        }
        if let end = parseDate(campaign.endAt) {
            hasEndAt = true
            endAt = end
        } else {
            hasEndAt = false
        }
        creativeTitle = creative?.title ?? ""
        creativeBody = creative?.body ?? ""
        creativeMediaURL = creative?.mediaURL ?? ""
        clickURL = creative?.clickURL ?? ""
        ctaLabel = creative?.ctaLabel ?? "Learn more"
        durationSeconds = creative?.durationSeconds ?? 8
        creativeUploadName = ""
        errorMessage = nil
        successMessage = nil
    }

    private func cancelEdit() {
        resetForm()
        errorMessage = nil
        successMessage = nil
    }

    private func resetForm() {
        editingCampaignID = nil
        editingCreativeID = nil
        campaignName = ""
        placement = "video"
        status = "draft"
        targetCountryCodes = []
        budgetEUR = ""
        dailyBudgetEUR = ""
        hasStartAt = false
        hasEndAt = false
        creativeTitle = ""
        creativeBody = ""
        creativeMediaURL = ""
        clickURL = ""
        ctaLabel = "Learn more"
        durationSeconds = 8
        creativeUploadName = ""
    }

    private func isCampaignBusy(_ campaignID: String) -> Bool {
        busyCampaignIDs.contains(campaignID)
    }

    // MARK: - Formatting

    private func campaignMetaPills(_ campaign: AdCampaign) -> [PillItem] {
        var items = [
            PillItem(text: campaign.placement, style: .neutral),
            PillItem(text: campaign.status, style: .neutral),
            PillItem(text: campaignPhaseLabel(campaign), style: phaseStyle(campaign)),
        ]
        if campaign.targetCountryCodes.isEmpty {
            items.append(PillItem(text: "Worldwide", style: .neutral))
        } else {
            items.append(PillItem(text: campaign.targetCountryCodes.joined(separator: ", "), style: .neutral))
        }
        return items
    }

    private func budgetPills(_ campaign: AdCampaign) -> [PillItem] {
        var items = [
            PillItem(text: "Total \(formatMoney(campaign.budgetCents))", style: .neutral),
            PillItem(text: "Daily \(formatMoney(campaign.dailyBudgetCents))", style: .neutral),
        ]
        if let startAt = campaign.startAt, let date = parseDate(startAt) {
            items.append(PillItem(text: "Starts \(mediumDate(date))", style: .neutral))
        }
        if let endAt = campaign.endAt, let date = parseDate(endAt) {
            items.append(PillItem(text: "Ends \(mediumDate(date))", style: .neutral))
        }
        return items
    }

    private func campaignPhase(_ campaign: AdCampaign) -> String {
        let startMs = parseDate(campaign.startAt)?.timeIntervalSince1970
        let endMs = parseDate(campaign.endAt)?.timeIntervalSince1970
        let nowMs = now.timeIntervalSince1970
        if let endMs, nowMs > endMs { return "ended" }
        if let startMs, nowMs < startMs { return "scheduled" }
        return "ongoing"
    }

    private func campaignPhaseLabel(_ campaign: AdCampaign) -> String {
        switch campaignPhase(campaign) {
        case "scheduled": "Scheduled"
        case "ended": "Ended"
        default: "Ongoing"
        }
    }

    private func phaseStyle(_ campaign: AdCampaign) -> PillStyle {
        switch campaignPhase(campaign) {
        case "scheduled": .scheduled
        case "ended": .ended
        default: .live
        }
    }

    private func campaignTimerText(_ campaign: AdCampaign) -> String {
        let phase = campaignPhase(campaign)
        if phase == "scheduled", let start = parseDate(campaign.startAt) {
            return "Starts in \(formatCountdown(start.timeIntervalSince(now)))."
        }
        if phase == "ongoing", let end = parseDate(campaign.endAt) {
            return "Ends in \(formatCountdown(end.timeIntervalSince(now)))."
        }
        if phase == "ended", let end = parseDate(campaign.endAt) {
            return "Ended on \(mediumDate(end))."
        }
        return "No end date set."
    }

    private func formatMoney(_ cents: Int) -> String {
        String(format: "EUR %.2f", Double(cents) / 100)
    }

    private func toCents(_ raw: String) -> Int {
        let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return max(0, Int((value * 100).rounded()))
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let numeric = Double(raw), raw.allSatisfy(\.isNumber) {
            let seconds = numeric > 1_000_000_000_000 ? numeric / 1000 : numeric
            return Date(timeIntervalSince1970: seconds)
        }
        return ISO8601DateFormatter().date(from: raw) ?? DateFormatter.adsFallback.date(from: raw)
    }

    private func mediumDate(_ date: Date) -> String {
        DateFormatter.adsMedium.string(from: date)
    }

    private func formatCountdown(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m \(secs)s" }
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - Helpers

private struct PillItem: Identifiable {
    let id = UUID()
    let text: String
    let style: PillStyle
}

private enum PillStyle {
    case neutral, live, scheduled, ended
}

private struct FlowPills: View {
    let items: [PillItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                Text(item.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(foreground(for: item.style))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(background(for: item.style), in: Capsule())
            }
        }
    }

    private func foreground(for style: PillStyle) -> Color {
        switch style {
        case .live: Theme.success
        case .scheduled: Color(red: 0.12, green: 0.31, blue: 0.58)
        case .ended: Theme.inkMuted
        case .neutral: Theme.inkSecondary
        }
    }

    private func background(for style: PillStyle) -> Color {
        switch style {
        case .live: Theme.success.opacity(0.12)
        case .scheduled: Color(red: 0.93, green: 0.96, blue: 1.0)
        case .ended: Theme.buttonMuted
        case .neutral: Theme.buttonMuted
        }
    }
}

private extension View {
    func adsCard() -> some View {
        padding(Theme.cardPadding + 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius + 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius + 4, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .shadow(color: Theme.ink.opacity(0.04), radius: 8, y: 3)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension DateFormatter {
    static let adsMedium: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let adsFallback: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()
}