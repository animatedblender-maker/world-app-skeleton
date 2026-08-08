import Foundation

/// Reclassifies Archive hub seed rows into accurate categories + multi-channel personas.
enum HubCategoryClassifier {
    /// Top-level shelves (filters + hubOrder).
    static let categories: [String] = [
        "comedy", "music", "travel", "nature", "food", "sports",
        "tech", "fitness", "film", "culture", "history", "education",
        "animals", "cars", "news", "fashion", "gaming", "kids", "social", "daily",
    ]

    struct ChannelPersona: Sendable {
        let slug: String
        let displayName: String
        let parent: String
    }

    /// Multiple fake channels per category so Hubs feels like many creators.
    static let personasByCategory: [String: [ChannelPersona]] = [
        "comedy": [
            .init(slug: "comedy_vault", displayName: "Comedy Vault", parent: "comedy"),
            .init(slug: "comedy_commercials", displayName: "Ad Break Funny", parent: "comedy"),
            .init(slug: "comedy_skits", displayName: "Sketch Archive", parent: "comedy"),
        ],
        "music": [
            .init(slug: "music_classics", displayName: "Music Classics", parent: "music"),
            .init(slug: "music_jazz", displayName: "Jazz Room", parent: "music"),
            .init(slug: "music_concerts", displayName: "Live Stage", parent: "music"),
            .init(slug: "music_radio", displayName: "Radio Days", parent: "music"),
        ],
        "travel": [
            .init(slug: "travel_cities", displayName: "City Walks", parent: "travel"),
            .init(slug: "travel_world", displayName: "World Routes", parent: "travel"),
            .init(slug: "travel_trains", displayName: "Rails & Roads", parent: "travel"),
        ],
        "nature": [
            .init(slug: "nature_wild", displayName: "Wild Earth", parent: "nature"),
            .init(slug: "nature_ocean", displayName: "Ocean Archive", parent: "nature"),
            .init(slug: "nature_sky", displayName: "Sky & Weather", parent: "nature"),
        ],
        "food": [
            .init(slug: "food_kitchen", displayName: "Archive Kitchen", parent: "food"),
            .init(slug: "food_ads", displayName: "Tasty Ads", parent: "food"),
            .init(slug: "food_farms", displayName: "Farm to Table", parent: "food"),
        ],
        "sports": [
            .init(slug: "sports_field", displayName: "Field Day", parent: "sports"),
            .init(slug: "sports_ball", displayName: "Ball Archive", parent: "sports"),
            .init(slug: "sports_racing", displayName: "Speed Line", parent: "sports"),
        ],
        "tech": [
            .init(slug: "tech_future", displayName: "Future Tech", parent: "tech"),
            .init(slug: "tech_gadgets", displayName: "Gadget Desk", parent: "tech"),
            .init(slug: "tech_computers", displayName: "Computer Age", parent: "tech"),
        ],
        "fitness": [
            .init(slug: "fitness_move", displayName: "Move More", parent: "fitness"),
            .init(slug: "fitness_health", displayName: "Healthy Archive", parent: "fitness"),
            .init(slug: "fitness_dance", displayName: "Dance Fitness", parent: "fitness"),
        ],
        "film": [
            .init(slug: "film_cinema", displayName: "Cinema Room", parent: "film"),
            .init(slug: "film_trailer", displayName: "Trailer Vault", parent: "film"),
            .init(slug: "film_tv", displayName: "TV Classics", parent: "film"),
            .init(slug: "film_animation", displayName: "Animation Cell", parent: "film"),
        ],
        "culture": [
            .init(slug: "culture_arts", displayName: "Arts & Letters", parent: "culture"),
            .init(slug: "culture_world", displayName: "World Cultures", parent: "culture"),
            .init(slug: "culture_design", displayName: "Design Desk", parent: "culture"),
        ],
        "history": [
            .init(slug: "history_reels", displayName: "History Reels", parent: "history"),
            .init(slug: "history_war", displayName: "War Archive", parent: "history"),
            .init(slug: "history_newsreel", displayName: "Newsreel Desk", parent: "history"),
        ],
        "education": [
            .init(slug: "edu_classroom", displayName: "Classroom", parent: "education"),
            .init(slug: "edu_science", displayName: "Science Hour", parent: "education"),
            .init(slug: "edu_howto", displayName: "How-To Archive", parent: "education"),
        ],
        "animals": [
            .init(slug: "animals_pets", displayName: "Pet Parade", parent: "animals"),
            .init(slug: "animals_wild", displayName: "Creature Feature", parent: "animals"),
        ],
        "cars": [
            .init(slug: "cars_classic", displayName: "Classic Motors", parent: "cars"),
            .init(slug: "cars_race", displayName: "Race Day", parent: "cars"),
        ],
        "news": [
            .init(slug: "news_desk", displayName: "News Desk", parent: "news"),
            .init(slug: "news_broadcast", displayName: "Broadcast Days", parent: "news"),
        ],
        "fashion": [
            .init(slug: "fashion_style", displayName: "Style Archive", parent: "fashion"),
            .init(slug: "fashion_runway", displayName: "Runway Retro", parent: "fashion"),
        ],
        "gaming": [
            .init(slug: "gaming_arcade", displayName: "Arcade Vault", parent: "gaming"),
            .init(slug: "gaming_play", displayName: "Play Room", parent: "gaming"),
        ],
        "kids": [
            .init(slug: "kids_fun", displayName: "Kids Fun", parent: "kids"),
            .init(slug: "kids_stories", displayName: "Story Time", parent: "kids"),
        ],
        "social": [
            .init(slug: "social_life", displayName: "Social Life", parent: "social"),
            .init(slug: "social_people", displayName: "People Watch", parent: "social"),
            .init(slug: "social_street", displayName: "Street Scenes", parent: "social"),
        ],
        "daily": [
            .init(slug: "daily_life", displayName: "Daily Life", parent: "daily"),
            .init(slug: "daily_home", displayName: "Home Hour", parent: "daily"),
        ],
    ]

    private static let keywordBuckets: [(category: String, words: [String])] = [
        ("comedy", ["comedy", "funny", "humor", "humour", "joke", "sketch", "laugh", "gag", "parody", "satire", "slapstick", "standup", "sitcom", "prank"]),
        ("music", ["music", "song", "jazz", "blues", "concert", "orchestra", "band", "singer", "piano", "guitar", "opera", "symphony", "choir", "melody", "soundtrack", "anthem", "hymn"]),
        ("travel", ["travel", "trip", "tour", "voyage", "journey", "city", "paris", "london", "tokyo", "san francisco", "market street", "vista", "abroad", "cruise", "railway", "train", "airport", "hotel", "stockholm", "ridderholmen"]),
        ("nature", ["nature", "forest", "wildlife", "mountain", "river", "ocean", "sea", "lake", "garden", "flower", "landscape", "earth", "weather", "storm", "volcano", "glacier", "time lapse", "timelapse"]),
        ("food", ["food", "recipe", "cook", "kitchen", "breakfast", "dinner", "cereal", "coffee", "restaurant", "farm", "bread", "fruit", "vegetable", "meal", "bananas", "preserve", "frosted flakes", "kellogg"]),
        ("sports", ["sport", "football", "baseball", "basketball", "soccer", "tennis", "golf", "olympics", "race", "racing", "boxing", "wrestling", "athletic", "stadium", "team", "fireman"]),
        ("tech", ["tech", "computer", "robot", "electronic", "telephone", "engineering", "invention", "space", "rocket", "satellite", "digital", "technicolor", "countdown"]),
        ("fitness", ["fitness", "exercise", "workout", "yoga", "gym", "posture", "calisthenics", "aerobics", "strength", "physical education", "health: your"]),
        ("film", ["movie", "cinema", "trailer", "cartoon", "animation", "animated", "feature", "disney", "film", "commercial", "commercials", "tv classic", "silent film"]),
        ("culture", ["culture", "art", "museum", "dance", "ballet", "theatre", "theater", "architecture", "literature", "poetry", "fashion show"]),
        ("history", ["history", "historical", "war", "wwii", "ww2", "civil war", "newsreel", "archival", "vintage 19", "hindenburg", "korean war", "world war"]),
        ("education", ["education", "school", "classroom", "lesson", "howto", "how to", "tutorial", "instruction", "science for", "learn", "teaching"]),
        ("animals", ["animal", "dog", "cat", "pet", "bird", "horse", "zoo", "wildlife", "creature", "puppy", "kitten"]),
        ("cars", ["car", "auto", "automobile", "motor", "vehicle", "truck", "honda", "ford", "chevrolet", "racing car", "drive"]),
        ("news", ["news", "broadcast", "reporter", "headline", "bulletin", "newscast", "anchor"]),
        ("fashion", ["fashion", "style", "clothing", "dress", "runway", "model", "wardrobe", "beauty"]),
        ("gaming", ["game", "gaming", "arcade", "video game", "play station", "nintendo", "atari"]),
        ("kids", ["kids", "children", "child", "nursery", "cartoon for kids", "story time", "babies"]),
        ("social", ["people", "family", "community", "street", "crowd", "party", "wedding", "social", "friends"]),
        ("daily", ["daily", "home", "house", "routine", "morning", "evening", "housework", "domestic"]),
    ]

    /// Pick best parent category from free text (+ optional seed slug as weak prior).
    nonisolated static func classify(
        title: String?,
        body: String?,
        tags: [String],
        creator: String?,
        seedSlug: String?
    ) -> String {
        let blob = [
            title ?? "",
            body ?? "",
            creator ?? "",
            tags.joined(separator: " "),
        ]
        .joined(separator: " ")
        .lowercased()

        var scores: [String: Int] = [:]
        for bucket in keywordBuckets {
            var score = 0
            for word in bucket.words {
                if blob.contains(word) {
                    score += word.count >= 6 ? 3 : 2
                }
            }
            if score > 0 {
                scores[bucket.category, default: 0] += score
            }
        }

        // Tags often include the category name.
        for tag in tags {
            let t = tag.lowercased()
            if categories.contains(t) {
                scores[t, default: 0] += 4
            }
            if t == "funny" || t == "spark" || t == "short" {
                scores["comedy", default: 0] += 2
            }
        }

        // Weak prior from original seed slug when still a known category.
        if let seed = seedSlug?.lowercased(), categories.contains(seed) {
            scores[seed, default: 0] += 1
        }

        // Prefer the highest score; on ties keep seed if valid, else comedy/social last resort.
        if let best = scores.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key > b.key
        }), best.value >= 2 {
            return best.key
        }

        if let seed = seedSlug?.lowercased(), categories.contains(seed) {
            return seed
        }
        return "daily"
    }

    /// Stable persona channel inside a parent category (hash of video id).
    nonisolated static func persona(forCategory category: String, seed: String) -> ChannelPersona {
        let parent = parentCategory(of: category)
        let list = personasByCategory[parent]
            ?? [.init(slug: parent, displayName: parent.capitalized, parent: parent)]
        let idx = Int(stableHash(seed) % UInt64(list.count))
        return list[idx]
    }

    /// Parent category for a persona slug (`music_jazz` → `music`) or raw category.
    nonisolated static func parentCategory(of slug: String) -> String {
        let s = slug.lowercased()
        if categories.contains(s) { return s }
        if let under = s.split(separator: "_").first {
            let head = String(under)
            if categories.contains(head) { return head }
            // edu_* → education
            if head == "edu" { return "education" }
        }
        return s
    }

    /// Catalog channel display — always **The Archive** (single R2 / hub channel).
    nonisolated static func displayName(forPersonaSlug slug: String, isSpark: Bool) -> String {
        _ = slug
        _ = isSpark
        return HubVideoSeedService.archiveChannelDisplayName
    }

    nonisolated private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 16_777_619
        }
        return hash
    }

    /// Deterministic shuffle for Sparks recommendations (different seed → different order).
    nonisolated static func shuffled<T>(_ items: [T], seed: UInt64) -> [T] {
        guard items.count > 1 else { return items }
        var result = items
        var state = seed == 0 ? 1 : seed
        for i in stride(from: result.count - 1, through: 1, by: -1) {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let j = Int(state % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }
}
