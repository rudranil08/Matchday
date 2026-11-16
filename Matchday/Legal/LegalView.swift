import SwiftUI

/// A legal page in Matchday's own style: display-face title, DM Sans body, cards on the chalk ground.
struct LegalView: View {
    @Environment(\.palette) private var t
    @Environment(\.dismiss) private var dismiss
    let doc: LegalDoc
    var showsClose = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(doc.title.uppercased()).font(AppFont.display(26)).foregroundStyle(t.ink)
                    Text(doc.intro).font(AppFont.regular(15)).foregroundStyle(t.muted).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(doc.sections.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.heading.uppercased()).font(AppFont.semibold(12)).tracking(1.2).foregroundStyle(t.muted)
                            Text(s.body).font(AppFont.regular(15)).foregroundStyle(t.ink).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16).card()
                        }
                    }
                }
                .padding(20)
            }
            .background(t.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.font(AppFont.bold(16)) }
                }
            }
        }
    }
}

/// "By continuing you agree to the Terms of Use and Privacy Policy", with both tappable.
struct LegalAgreement: View {
    var light = false
    @State private var open: LegalDoc?

    var body: some View {
        let base: Color = light ? .white.opacity(0.6) : Palette.light.muted
        let link: Color = light ? .white : Palette.light.accent
        (Text("By continuing you agree to the ").foregroundStyle(base)
         + Text("[Terms of Use](matchday-legal://terms)").foregroundStyle(link)
         + Text(" and have read the ").foregroundStyle(base)
         + Text("[Privacy Policy](matchday-legal://privacy)").foregroundStyle(link)
         + Text(".").foregroundStyle(base))
            .font(AppFont.medium(12))
            .tint(link)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .environment(\.openURL, OpenURLAction { url in
                open = LegalDoc.all.first { $0.id == url.host }
                return .handled
            })
            .sheet(item: $open) { LegalView(doc: $0).environment(\.palette, Palette.light).environment(\.colorScheme, .light) }
    }
}
