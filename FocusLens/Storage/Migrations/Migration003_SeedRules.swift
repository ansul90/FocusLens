import Foundation
import GRDB

enum Migration003_SeedRules {
    static let identifier = "v3_seed_rules"

    static func migrate(_ db: Database) throws {
        // Replace Migration002's placeholder seeds with accurate bundle IDs.
        // Clear rules first (FK child), then categories, then re-seed.
        try db.execute(sql: "DELETE FROM category_rules")
        try db.execute(sql: "DELETE FROM categories")
        // Reset any sessions that pointed to the old category IDs.
        try db.execute(sql: "UPDATE activity_sessions SET category_id = NULL")

        try seedDevelopment(db)
        try seedDevTools(db)
        try seedAITools(db)
        try seedNotesPKM(db)
        try seedCommunication(db)
        try seedOffice(db)
        try seedBrowser(db)
        try seedMedia(db)
        try seedUtilities(db)
    }

    // MARK: - Seed helpers

    private static func insertCategory(_ db: Database, name: String, colorHex: String, score: Int) throws -> Int64 {
        try db.execute(
            sql: "INSERT INTO categories (name, color_hex, is_productive) VALUES (?, ?, ?)",
            arguments: [name, colorHex, score]
        )
        return db.lastInsertedRowID
    }

    private static func insertRules(_ db: Database, categoryId: Int64, bundles: [(String, Int)]) throws {
        for (bundle, priority) in bundles {
            try db.execute(
                sql: "INSERT INTO category_rules (category_id, match_type, match_value, priority) VALUES (?, 'app_bundle', ?, ?)",
                arguments: [categoryId, bundle, priority]
            )
        }
    }

    // MARK: - Categories

    private static func seedDevelopment(_ db: Database) throws {
        let id = try insertCategory(db, name: "Development", colorHex: "#4CAF50", score: 2)
        try insertRules(db, categoryId: id, bundles: [
            ("com.apple.dt.Xcode",               100),
            ("com.microsoft.VSCode",              99),
            ("com.todesktop.230313mzl4w4u92",     98),  // Cursor
            ("com.jetbrains.intellij",            97),
            ("com.jetbrains.intellij.ce",         96),
            ("com.jetbrains.pycharm",             95),
        ])
    }

    private static func seedDevTools(_ db: Database) throws {
        let id = try insertCategory(db, name: "Dev Tools", colorHex: "#8BC34A", score: 2)
        try insertRules(db, categoryId: id, bundles: [
            ("com.googlecode.iterm2",                      100),
            ("com.torusknot.SourceTreeNotMAS",             99),
            ("com.docker.docker",                          98),
            ("com.postmanlabs.mac",                        97),
            ("io.hoppscotch.desktop",                      96),
            ("com.xk72.Charles",                           95),
            ("com.oracle.workbench.MySQLWorkbench",        94),
            ("com.sequel-ace.sequel-ace",                  93),
            ("com.install4j.6538-9936-2386-7331.2",        92),  // JProfiler
            ("org.eclipse.mat.ui.rcp.MemoryAnalyzer",      91),
            ("io.visualvm.VisualVM",                       90),
            ("com.github.variar.klogg",                    89),
        ])
    }

    private static func seedAITools(_ db: Database) throws {
        let id = try insertCategory(db, name: "AI Tools", colorHex: "#2196F3", score: 2)
        try insertRules(db, categoryId: id, bundles: [
            ("com.anthropic.claudefordesktop", 100),
            ("ai.elementlabs.lmstudio",        99),
            ("com.electron.ollama",            98),
        ])
    }

    private static func seedNotesPKM(_ db: Database) throws {
        let id = try insertCategory(db, name: "Notes & PKM", colorHex: "#009688", score: 1)
        try insertRules(db, categoryId: id, bundles: [
            ("notion.id",                        100),
            ("md.obsidian",                       99),
            ("com.anytype.anytype",               98),
            ("com.todoist.mac.Todoist",           97),
            ("com.philipyoungg.session-direct",   96),
            ("com.grammarly.ProjectLlama",        95),
        ])
    }

    private static func seedCommunication(_ db: Database) throws {
        let id = try insertCategory(db, name: "Communication", colorHex: "#FF9800", score: 0)
        try insertRules(db, categoryId: id, bundles: [
            ("com.tinyspeck.slackmacgap", 100),
            ("com.microsoft.teams2",       99),
            ("com.microsoft.Outlook",      98),
            ("us.zoom.xos",                97),
            ("com.hnc.Discord",            96),
        ])
    }

    private static func seedOffice(_ db: Database) throws {
        let id = try insertCategory(db, name: "Office", colorHex: "#3F51B5", score: 1)
        try insertRules(db, categoryId: id, bundles: [
            ("com.microsoft.Word",                      100),
            ("com.microsoft.Excel",                      99),
            ("com.microsoft.Powerpoint",                 98),
            ("com.google.drivefs.shortcuts.docs",        97),
            ("com.google.drivefs.shortcuts.sheets",      96),
            ("com.google.drivefs.shortcuts.slides",      95),
            ("com.jgraph.drawio.desktop",                94),
        ])
    }

    private static func seedBrowser(_ db: Database) throws {
        let id = try insertCategory(db, name: "Browser", colorHex: "#9E9E9E", score: 0)
        try insertRules(db, categoryId: id, bundles: [
            ("com.google.Chrome",     100),
            ("org.mozilla.firefox",    99),
            ("com.brave.Browser",      98),
            ("com.apple.Safari",       97),
            ("ai.perplexity.comet",    96),
        ])
    }

    private static func seedMedia(_ db: Database) throws {
        let id = try insertCategory(db, name: "Media", colorHex: "#F44336", score: -1)
        try insertRules(db, categoryId: id, bundles: [
            ("org.videolan.vlc",                  100),
            ("maccatalyst.com.frontrow.vlog",      99),  // VN video editor
        ])
    }

    private static func seedUtilities(_ db: Database) throws {
        let id = try insertCategory(db, name: "Utilities", colorHex: "#607D8B", score: 0)
        try insertRules(db, categoryId: id, bundles: [
            ("com.raycast.macos",                          100),
            ("com.knollsoft.Rectangle",                     99),
            ("com.dwarvesv.minimalbar",                     98),
            ("com.clipy-app.Clipy",                         97),
            ("org.herf.Flux",                               96),
            ("com.sindresorhus.Pandan",                     95),
            ("cc.ffitch.shottr",                            94),
            ("com.softwarehow.grab2text",                   93),
            ("net.freemacsoft.AppCleaner",                  92),
            ("com.piriform.ccleaner",                       91),
            ("com.omnigroup.OmniDiskSweeper",               90),
            ("com.max-langer.Latest",                       89),
            ("cx.c3.theunarchiver",                         88),
            ("com.YAC.Backtrack",                           87),
            ("com.waseem.TempBox",                          86),
            ("com.siddharthvaddem.openscreen",              85),
            ("com.google.drivefs",                          84),
            ("com.microsoft.OneDrive-mac",                  83),
            ("com.google.android.mtpviewer",                82),
            ("org.keepassxc.keepassxc",                     81),
            ("me.proton.pass.electron",                     80),
            ("com.okta.mobile",                             79),
            ("com.paloaltonetworks.GlobalProtect.client",   78),
            ("com.crowdstrike.falcon.App",                  77),
            ("com.ws1.hub.mac",                             76),
            ("com.logi.optionsplus",                        75),
            ("com.seagate.toolkit",                         74),
        ])
    }
}
