import StoreKit
import WidgetKit

enum ProductID {
    static let pro = "com.limuye.everysecondpays.pro"
    static let tips = ["com.limuye.everysecondpays.tip.small", "com.limuye.everysecondpays.tip.medium", "com.limuye.everysecondpays.tip.large"]
    static let all = [pro] + tips
}

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    @Published var products: [Product] = []
    @Published var isPro = Entitlements.isPro
    @Published var hasTipped = Entitlements.hasTipped
    @Published var purchasing: String?
    @Published var lastError: String?
    @Published var thankYou = false
    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await r in Transaction.updates { if case .verified(let t) = r { await self?.handle(t); await t.finish() } }
        }
        Task { await load(); await refresh() }
    }

    var pro: Product? { products.first { $0.id == ProductID.pro } }
    var tips: [Product] { ProductID.tips.compactMap { id in products.first { $0.id == id } } }

    func load() async {
        do { products = try await Product.products(for: ProductID.all) } catch { lastError = error.localizedDescription }
    }

    func refresh() async {
        var pro = false
        for await r in Transaction.currentEntitlements { if case .verified(let t) = r, t.productID == ProductID.pro, t.revocationDate == nil { pro = true } }
        set(pro: pro)
    }

    func buy(_ p: Product) async {
        purchasing = p.id; defer { purchasing = nil }
        do {
            switch try await p.purchase() {
            case .success(let r):
                guard case .verified(let t) = r else { lastError = String(localized: "store.unverified"); return }
                await handle(t); await t.finish()
                if t.productType == .consumable { thankYou = true }
            default: break
            }
        } catch { lastError = error.localizedDescription }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { lastError = error.localizedDescription }
        await refresh()
        // Consumable tips aren't restorable by StoreKit; check full history for any tip.
        for await r in Transaction.all { if case .verified(let t) = r, ProductID.tips.contains(t.productID) { setTipped() } }
    }

    private func handle(_ t: Transaction) async {
        if t.productID == ProductID.pro { set(pro: t.revocationDate == nil) }
        if ProductID.tips.contains(t.productID) { setTipped() }
    }
    private func set(pro: Bool) {
        guard pro != Entitlements.isPro || pro != isPro else { return }
        Entitlements.isPro = pro; isPro = pro; WidgetCenter.shared.reloadAllTimelines()
    }
    private func setTipped() { Entitlements.hasTipped = true; hasTipped = true }
}
