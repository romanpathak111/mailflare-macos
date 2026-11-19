import SwiftUI

/// The Status board: one column per status, a card for each conversation. Dragging a card to
/// another column changes its status.
struct StatusBoardView: View {
	@Environment(MailStore.self) private var store
	/// The account the board is limited to; nil shows every account.
	@State private var accountFilter: String?
	/// The column a card is being dragged over.
	@State private var targeted: ThreadStatus?
	@State private var confirmingArchive = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			header
			GeometryReader { proxy in
				let gap: CGFloat = 12, padding: CGFloat = 20
				let width = max(220, (proxy.size.width - padding * 2 - gap * 3) / 4)
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(alignment: .top, spacing: gap) {
						ForEach(ThreadStatus.allCases) { status in
							column(status).frame(width: width)
						}
					}
					.padding(.horizontal, padding)
					.padding(.bottom, 16)
					.frame(maxHeight: .infinity, alignment: .top)
				}
			}
		}
		.background(AppTheme.background)
		.confirmationDialog("Archive all \(records(.canArchive).count) conversations?", isPresented: $confirmingArchive, titleVisibility: .visible) {
			Button("Archive All") { store.archive(records: records(.canArchive)) }
		} message: {
			Text("They move to Archive and leave the board. You can still find them there.")
		}
	}

	private func records(_ status: ThreadStatus) -> [ThreadRecord] {
		store.statuses.records(with: status).filter { accountFilter == nil || $0.accountID == accountFilter }
	}

	// MARK: Header

	private var header: some View {
		HStack(alignment: .bottom, spacing: 10) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Status board").font(.system(size: 26, weight: .bold)).tracking(-0.5)
				Text("Drag a conversation to change its status. Sort unsorted mail to file what just arrived.")
					.font(Typography.notice).foregroundStyle(.secondary).lineLimit(1)
			}
			Spacer(minLength: 12)
			if store.accountList.count > 1 { filterMenu }
			Button {
				store.sortUnsortedMail()
			} label: {
				HStack(spacing: 6) {
					if store.isSortingStatuses { ProgressView().controlSize(.small).scaleEffect(0.7) } else { HIcon(.sparkles, size: 14) }
					Text("Sort unsorted mail")
				}
			}
			.buttonStyle(.pillProminent)
			.disabled(store.isSortingStatuses)
		}
		.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 18)
	}

	private var filterMenu: some View {
		Menu {
			Button { accountFilter = nil } label: { Text(accountFilter == nil ? "✓  All accounts" : "All accounts") }
			Divider()
			ForEach(store.accountList) { account in
				Button { accountFilter = account.id } label: {
					Text(accountFilter == account.id ? "✓  \(store.accountName(account))" : store.accountName(account))
				}
			}
		} label: {
			HStack(spacing: 6) {
				HIcon(.filter, size: 14)
				Text(accountFilter.flatMap { id in store.accountList.first { $0.id == id } }.map(store.accountName) ?? "Filter")
			}
			.font(.system(size: 13, weight: .medium))
			.padding(.horizontal, 14).padding(.vertical, 7)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.railSelection.opacity(0.7)))
		}
		.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
	}

	// MARK: Columns

	private func column(_ status: ThreadStatus) -> some View {
		let cards = records(status)
		let isTarget = targeted == status
		let isFocus = store.boardFocus == status
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				StatusDot(status: status)
				Text(status.title).font(Typography.notice.weight(.semibold)).lineLimit(1)
				Spacer(minLength: 4)
				Text("\(cards.count)").font(Typography.notice.weight(.semibold))
			}
			.foregroundStyle(status.ink)
			.padding(.horizontal, 12).frame(height: 36)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(status.tint))
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(status.dot, lineWidth: isFocus ? 1.5 : 0))

			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(spacing: 10) {
					if isTarget {
						RoundedRectangle(cornerRadius: 12, style: .continuous)
							.strokeBorder(status.dot, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
							.frame(height: 70)
							.overlay(Text("Drop here").font(Typography.notice.weight(.semibold)).foregroundStyle(status.ink))
					}
					ForEach(cards) { record in
						BoardCard(record: record, status: status)
							.draggable(record.id)
					}
					if cards.isEmpty && !isTarget {
						Text("Nothing here").font(Typography.notice).foregroundStyle(.tertiary)
							.frame(maxWidth: .infinity, minHeight: 60)
					}
					if status == .canArchive && !cards.isEmpty {
						Button("Archive all \(cards.count)") { confirmingArchive = true }
							.buttonStyle(.pill).frame(maxWidth: .infinity)
					}
				}
				.padding(.bottom, 8)
			}
		}
		.frame(maxHeight: .infinity, alignment: .top)
		.contentShape(Rectangle())
		.dropDestination(for: String.self) { keys, _ in
			var moved = false
			for key in keys {
				if let record = store.statuses.records[key], record.status != status { store.setStatus(status, for: record); moved = true }
			}
			return moved
		} isTargeted: { over in
			if over { targeted = status } else if targeted == status { targeted = nil }
		}
	}
}

/// One conversation on the board: what it is, what it wants, who sent it, and how long ago.
private struct BoardCard: View {
	@Environment(MailStore.self) private var store
	let record: ThreadRecord
	let status: ThreadStatus
	@State private var isHovering = false

	private var detail: String { record.ask.flatMap { $0.isEmpty ? nil : $0 } ?? record.preview }
	private var isDue: Bool { record.age() == "Due today" }

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text(record.subject.isEmpty ? "(No Subject)" : record.subject).font(Typography.bodySemibold).lineLimit(2)
			if !detail.isEmpty {
				Text(detail).font(Typography.notice).foregroundStyle(.primary.opacity(0.8)).lineLimit(2)
			}
			HStack {
				Text(record.senderDisplay).lineLimit(1)
				Spacer(minLength: 6)
				Text(record.age()).fontWeight(isDue ? .bold : .regular).foregroundStyle(isDue ? status.ink : Color.secondary).lineLimit(1)
			}
			.font(Typography.meta).foregroundStyle(.secondary)
			.padding(.top, 4)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.elevated))
		.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isHovering ? status.dot.opacity(0.7) : AppTheme.cardStroke, lineWidth: 1))
		.shadow(color: AppTheme.composerShadow.opacity(isHovering ? 0.6 : 0), radius: 6, y: 2)
		.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
		.onHover { isHovering = $0 }
		.onTapGesture { store.open(record) }
		.contextMenu {
			Button("Open") { store.open(record) }
			Button("Reply") { store.reply(to: record) }
			Divider()
			ForEach(ThreadStatus.allCases.filter { $0 != status }) { other in
				Button("Move to \(other.title)") { store.setStatus(other, for: record) }
			}
			Divider()
			Button("Archive") { store.archive(records: [record]) }
			Button("Clear Status") { store.statuses.remove(account: record.accountID, message: record.messageID) }
		}
		.help(record.subject)
	}
}
