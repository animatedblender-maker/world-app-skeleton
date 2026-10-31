package com.matterya.matterya.data.hubs

import com.matterya.matterya.model.HubArchiveIdentity

/** iOS `HubCategoryClassifier.swift` — categories, personas, keyword scores preserved. */
object HubCategoryClassifier {
    val categories = listOf(
        "comedy", "music", "travel", "nature", "food", "sports",
        "tech", "fitness", "film", "culture", "history", "education",
        "animals", "cars", "news", "fashion", "gaming", "kids", "social", "daily",
    )

    data class ChannelPersona(val slug: String, val displayName: String, val parent: String)

    val personasByCategory: Map<String, List<ChannelPersona>> = mapOf(
        "comedy" to listOf(
            ChannelPersona("comedy_vault", "Comedy Vault", "comedy"),
            ChannelPersona("comedy_commercials", "Ad Break Funny", "comedy"),
            ChannelPersona("comedy_skits", "Sketch Archive", "comedy"),
        ),
        "music" to listOf(
            ChannelPersona("music_classics", "Music Classics", "music"),
            ChannelPersona("music_jazz", "Jazz Room", "music"),
            ChannelPersona("music_concerts", "Live Stage", "music"),
            ChannelPersona("music_radio", "Radio Days", "music"),
        ),
        "travel" to listOf(
            ChannelPersona("travel_cities", "City Walks", "travel"),
            ChannelPersona("travel_world", "World Routes", "travel"),
            ChannelPersona("travel_trains", "Rails & Roads", "travel"),
        ),
        "nature" to listOf(
            ChannelPersona("nature_wild", "Wild Earth", "nature"),
            ChannelPersona("nature_ocean", "Ocean Archive", "nature"),
            ChannelPersona("nature_sky", "Sky & Weather", "nature"),
        ),
        "food" to listOf(
            ChannelPersona("food_kitchen", "Archive Kitchen", "food"),
            ChannelPersona("food_ads", "Tasty Ads", "food"),
            ChannelPersona("food_farms", "Farm to Table", "food"),
        ),
        "sports" to listOf(
            ChannelPersona("sports_field", "Field Day", "sports"),
            ChannelPersona("sports_ball", "Ball Archive", "sports"),
            ChannelPersona("sports_racing", "Speed Line", "sports"),
        ),
        "tech" to listOf(
            ChannelPersona("tech_future", "Future Tech", "tech"),
            ChannelPersona("tech_gadgets", "Gadget Desk", "tech"),
            ChannelPersona("tech_computers", "Computer Age", "tech"),
        ),
        "fitness" to listOf(
            ChannelPersona("fitness_move", "Move More", "fitness"),
            ChannelPersona("fitness_health", "Healthy Archive", "fitness"),
            ChannelPersona("fitness_dance", "Dance Fitness", "fitness"),
        ),
        "film" to listOf(
            ChannelPersona("film_cinema", "Cinema Room", "film"),
            ChannelPersona("film_trailer", "Trailer Vault", "film"),
            ChannelPersona("film_tv", "TV Classics", "film"),
            ChannelPersona("film_animation", "Animation Cell", "film"),
        ),
        "culture" to listOf(
            ChannelPersona("culture_arts", "Arts & Letters", "culture"),
            ChannelPersona("culture_world", "World Cultures", "culture"),
            ChannelPersona("culture_design", "Design Desk", "culture"),
        ),
        "history" to listOf(
            ChannelPersona("history_reels", "History Reels", "history"),
            ChannelPersona("history_war", "War Archive", "history"),
            ChannelPersona("history_newsreel", "Newsreel Desk", "history"),
        ),
        "education" to listOf(
            ChannelPersona("edu_classroom", "Classroom", "education"),
            ChannelPersona("edu_science", "Science Hour", "education"),
            ChannelPersona("edu_howto", "How-To Archive", "education"),
        ),
        "animals" to listOf(
            ChannelPersona("animals_pets", "Pet Parade", "animals"),
            ChannelPersona("animals_wild", "Creature Feature", "animals"),
        ),
        "cars" to listOf(
            ChannelPersona("cars_classic", "Classic Motors", "cars"),
            ChannelPersona("cars_race", "Race Day", "cars"),
        ),
        "news" to listOf(
            ChannelPersona("news_desk", "News Desk", "news"),
            ChannelPersona("news_broadcast", "Broadcast Days", "news"),
        ),
        "fashion" to listOf(
            ChannelPersona("fashion_style", "Style Archive", "fashion"),
            ChannelPersona("fashion_runway", "Runway Retro", "fashion"),
        ),
        "gaming" to listOf(
            ChannelPersona("gaming_arcade", "Arcade Vault", "gaming"),
            ChannelPersona("gaming_play", "Play Room", "gaming"),
        ),
        "kids" to listOf(
            ChannelPersona("kids_fun", "Kids Fun", "kids"),
            ChannelPersona("kids_stories", "Story Time", "kids"),
        ),
        "social" to listOf(
            ChannelPersona("social_life", "Social Life", "social"),
            ChannelPersona("social_people", "People Watch", "social"),
            ChannelPersona("social_street", "Street Scenes", "social"),
        ),
        "daily" to listOf(
            ChannelPersona("daily_life", "Daily Life", "daily"),
            ChannelPersona("daily_home", "Home Hour", "daily"),
        ),
    )

    private val keywordBuckets: List<Pair<String, List<String>>> = listOf(
        "comedy" to listOf("comedy", "funny", "humor", "humour", "joke", "sketch", "laugh", "gag", "parody", "satire", "slapstick", "standup", "sitcom", "prank"),
        "music" to listOf("music", "song", "jazz", "blues", "concert", "orchestra", "band", "singer", "piano", "guitar", "opera", "symphony", "choir", "melody", "soundtrack", "anthem", "hymn"),
        "travel" to listOf("travel", "trip", "tour", "voyage", "journey", "city", "paris", "london", "tokyo", "san francisco", "market street", "vista", "abroad", "cruise", "railway", "train", "airport", "hotel", "stockholm", "ridderholmen"),
        "nature" to listOf("nature", "forest", "wildlife", "mountain", "river", "ocean", "sea", "lake", "garden", "flower", "landscape", "earth", "weather", "storm", "volcano", "glacier", "time lapse", "timelapse"),
        "food" to listOf("food", "recipe", "cook", "kitchen", "breakfast", "dinner", "cereal", "coffee", "restaurant", "farm", "bread", "fruit", "vegetable", "meal", "bananas", "preserve", "frosted flakes", "kellogg"),
        "sports" to listOf("sport", "football", "baseball", "basketball", "soccer", "tennis", "golf", "olympics", "race", "racing", "boxing", "wrestling", "athletic", "stadium", "team", "fireman"),
        "tech" to listOf("tech", "computer", "robot", "electronic", "telephone", "engineering", "invention", "space", "rocket", "satellite", "digital", "technicolor", "countdown"),
        "fitness" to listOf("fitness", "exercise", "workout", "yoga", "gym", "posture", "calisthenics", "aerobics", "strength", "physical education", "health: your"),
        "film" to listOf("movie", "cinema", "trailer", "cartoon", "animation", "animated", "feature", "disney", "film", "commercial", "commercials", "tv classic", "silent film"),
        "culture" to listOf("culture", "art", "museum", "dance", "ballet", "theatre", "theater", "architecture", "literature", "poetry", "fashion show"),
        "history" to listOf("history", "historical", "war", "wwii", "ww2", "civil war", "newsreel", "archival", "vintage 19", "hindenburg", "korean war", "world war"),
        "education" to listOf("education", "school", "classroom", "lesson", "howto", "how to", "tutorial", "instruction", "science for", "learn", "teaching"),
        "animals" to listOf("animal", "dog", "cat", "pet", "bird", "horse", "zoo", "wildlife", "creature", "puppy", "kitten"),
        "cars" to listOf("car", "auto", "automobile", "motor", "vehicle", "truck", "honda", "ford", "chevrolet", "racing car", "drive"),
        "news" to listOf("news", "broadcast", "reporter", "headline", "bulletin", "newscast", "anchor"),
        "fashion" to listOf("fashion", "style", "clothing", "dress", "runway", "model", "wardrobe", "beauty"),
        "gaming" to listOf("game", "gaming", "arcade", "video game", "play station", "nintendo", "atari"),
        "kids" to listOf("kids", "children", "child", "nursery", "cartoon for kids", "story time", "babies"),
        "social" to listOf("people", "family", "community", "street", "crowd", "party", "wedding", "social", "friends"),
        "daily" to listOf("daily", "home", "house", "routine", "morning", "evening", "housework", "domestic"),
    )

    fun classify(
        title: String?,
        body: String?,
        tags: List<String>,
        creator: String?,
        seedSlug: String?,
    ): String {
        val blob = listOfNotNull(title, body, creator, tags.joinToString(" ")).joinToString(" ").lowercase()
        val scores = mutableMapOf<String, Int>()
        for ((category, words) in keywordBuckets) {
            var score = 0
            for (word in words) {
                if (blob.contains(word)) score += if (word.length >= 6) 3 else 2
            }
            if (score > 0) scores[category] = (scores[category] ?: 0) + score
        }
        for (tag in tags) {
            val t = tag.lowercase()
            if (t in categories) scores[t] = (scores[t] ?: 0) + 4
            if (t == "funny" || t == "spark" || t == "short") {
                scores["comedy"] = (scores["comedy"] ?: 0) + 2
            }
        }
        seedSlug?.lowercase()?.takeIf { it in categories }?.let {
            scores[it] = (scores[it] ?: 0) + 1
        }
        val best = scores.maxWithOrNull(compareBy({ it.value }, { it.key }))
        if (best != null && best.value >= 2) return best.key
        seedSlug?.lowercase()?.takeIf { it in categories }?.let { return it }
        return "daily"
    }

    fun persona(forCategory: String, seed: String): ChannelPersona {
        val parent = parentCategory(forCategory)
        val list = personasByCategory[parent]
            ?: listOf(ChannelPersona(parent, parent.replaceFirstChar { it.uppercase() }, parent))
        val idx = (stableHash(seed) % list.size.toULong()).toInt()
        return list[idx]
    }

    fun parentCategory(of: String): String {
        val s = of.lowercase()
        if (s in categories) return s
        val head = s.split("_").firstOrNull() ?: s
        if (head in categories) return head
        if (head == "edu") return "education"
        return s
    }

    fun displayName(forPersonaSlug: String, isSpark: Boolean = false): String {
        @Suppress("UNUSED_VARIABLE")
        val _a = forPersonaSlug
        @Suppress("UNUSED_VARIABLE")
        val _b = isSpark
        return HubArchiveIdentity.archiveChannelDisplayName
    }

    private fun stableHash(value: String): ULong {
        var hash = 2_166_136_261uL
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toUByte().toULong())
            hash *= 16_777_619uL
        }
        return hash
    }

    fun <T> shuffled(items: List<T>, seed: ULong): List<T> {
        if (items.size <= 1) return items
        val result = items.toMutableList()
        var state = if (seed == 0uL) 1uL else seed
        for (i in result.lastIndex downTo 1) {
            state = state * 6_364_136_223_846_793_005uL + 1uL
            val j = (state % (i + 1).toULong()).toInt()
            result[i] = result[j].also { result[j] = result[i] }
        }
        return result
    }
}
