package com.matterya.matterya.data.demo

import com.matterya.matterya.model.PostAuthor

/**
 * Demo / seed people names — iOS `DemoPersonNames.swift`.
 * Deterministic per author ID so the same fake user always looks the same.
 */
object DemoPersonNames {
    private val givenNames: List<String> = listOf(
        "Liam", "Olivia", "Noah", "Charlotte", "Oliver", "Emma", "Theodore", "Amelia",
        "Henry", "Sophia", "James", "Mia", "Elijah", "Isabella", "Mateo", "Evelyn",
        "William", "Sofia", "Lucas", "Eliana", "Benjamin", "Harper", "Levi", "Luna",
        "Ezra", "Camila", "Sebastian", "Gianna", "Jack", "Elizabeth", "Daniel", "Eleanor",
        "Samuel", "Ella", "Michael", "Abigail", "Ethan", "Sofia", "Asher", "Avery",
        "John", "Scarlett", "Hudson", "Emily", "Luca", "Aria", "Leo", "Penelope",
        "Elias", "Chloe", "Owen", "Layla", "Alexander", "Mila", "Dylan", "Nora",
        "Santiago", "Hazel", "Julian", "Lily", "David", "Aurora", "Joseph", "Nova",
        "Matthew", "Ellie", "Luke", "Hannah", "Jackson", "Grace", "Maverick", "Isla",
        "Miles", "Violet", "Wyatt", "Willow", "Thomas", "Emilia", "Jacob", "Stella",
        "Isaac", "Zoe", "Mason", "Naomi", "Gabriel", "Victoria", "Anthony", "Riley",
        "Logan", "Lucy", "Carter", "Ivy", "Aiden", "Paisley", "Grayson", "Everly",
        "Caleb", "Elena", "Cooper", "Iris", "Charles", "Maya", "Roman", "Leah",
        "Josiah", "Claire", "Ezekiel", "Madeline", "Thiago", "Aaliyah", "Isaiah", "Anna",
        "Joshua", "Valentina", "Wesley", "Ruby", "Jayden", "Kennedy", "Bennett", "Sophie",
        "Nathan", "Alice", "Angel", "Natalia", "Nolan", "Bella", "Waylon", "Skylar",
        "Cameron", "Cora", "Brooks", "Jade", "Andrew", "Athena", "Beau", "Maria",
        "Weston", "Lydia", "Rowan", "Sarah", "Adrian", "Lillian", "Lincoln", "Josephine",
        "Enzo", "Julia", "Ian", "Delilah", "Kai", "Caroline", "Christian", "Sadie",
        "Axel", "Piper", "Aaron", "Lyla", "Theo", "Autumn", "Silas", "Paisley",
        "Walker", "Serenity", "Jonathan", "Eva", "Leonardo", "Genesis", "Everett", "Emery",
        "Micah", "Sloane", "Ryan", "Clara", "August", "Madelyn", "Gael", "Ariana",
        "Robert", "Samantha", "Jose", "Allison", "Eli", "Gabriella", "Jeremiah", "Margaret",
        "Luka", "Josephine", "Amir", "Remi", "Parker", "Brielle", "Colton", "Adeline",
        "Myles", "Quinn", "Adam", "Nevaeh", "Atlas", "Kaylee", "Xavier", "Peyton",
        "Amina", "Yusuf", "Fatima", "Omar", "Zara", "Hassan", "Layla", "Ibrahim",
        "Mei", "Hiro", "Yuki", "Kenji", "Sakura", "Hana", "Sora", "Rina",
        "Priya", "Arjun", "Ananya", "Rohan", "Isha", "Vikram", "Aisha", "Dev",
        "Sofia", "Diego", "Valentina", "Carlos", "Lucia", "Miguel", "Camila", "Javier",
        "Amara", "Kwame", "Zuri", "Jelani", "Nia", "Tariq", "Imani", "Kofi",
        "Ines", "Hugo", "Chloe", "Louis", "Camille", "Antoine", "Juliette", "Pierre",
        "Greta", "Lukas", "Freya", "Jonas", "Maja", "Erik", "Astrid", "Nils",
        "Giulia", "Marco", "Chiara", "Lorenzo", "Francesca", "Alessandro", "Elena", "Matteo",
        "Anya", "Dmitri", "Katya", "Ivan", "Mila", "Nikita", "Olga", "Sergei",
        "Yara", "Rafael", "Beatriz", "Thiago", "Larissa", "Gabriel", "Isabela", "Pedro",
    )

    private val surnames: List<String> = listOf(
        "Smith", "Johnson", "Williams", "Jones", "Brown", "Davis", "Miller", "Wilson",
        "Moore", "Taylor", "Anderson", "Thomas", "Jackson", "White", "Harris", "Martin",
        "Thompson", "Garcia", "Martinez", "Robinson", "Clark", "Rodriguez", "Lewis", "Lee",
        "Walker", "Hall", "Allen", "Young", "Hernandez", "King", "Wright", "Lopez",
        "Hill", "Scott", "Green", "Adams", "Baker", "Gonzalez", "Nelson", "Carter",
        "Mitchell", "Perez", "Roberts", "Turner", "Phillips", "Campbell", "Parker", "Evans",
        "Edwards", "Collins", "Stewart", "Sanchez", "Morris", "Rogers", "Reed", "Cook",
        "Morgan", "Bell", "Murphy", "Bailey", "Rivera", "Cooper", "Richardson", "Cox",
        "Howard", "Ward", "Torres", "Peterson", "Gray", "Ramirez", "James", "Watson",
        "Brooks", "Kelly", "Sanders", "Price", "Bennett", "Wood", "Barnes", "Ross",
        "Henderson", "Coleman", "Jenkins", "Perry", "Powell", "Long", "Patterson", "Hughes",
        "Flores", "Washington", "Butler", "Simmons", "Foster", "Gonzales", "Bryant", "Alexander",
        "Russell", "Griffin", "Diaz", "Hayes", "Myers", "Ford", "Hamilton", "Graham",
        "Sullivan", "Wallace", "Woods", "Cole", "West", "Jordan", "Owens", "Reynolds",
        "Fisher", "Ellis", "Harrison", "Gibson", "McDonald", "Cruz", "Marshall", "Ortiz",
        "Gomez", "Murray", "Freeman", "Wells", "Webb", "Simpson", "Stevens", "Tucker",
        "Porter", "Hunter", "Hicks", "Crawford", "Henry", "Boyd", "Mason", "Morales",
        "Kennedy", "Warren", "Dixon", "Ramos", "Reyes", "Burns", "Gordon", "Shaw",
        "Holmes", "Rice", "Robertson", "Hunt", "Black", "Daniels", "Palmer", "Mills",
        "Nichols", "Grant", "Knight", "Ferguson", "Rose", "Stone", "Hawkins", "Dunn",
        "Perkins", "Hudson", "Spencer", "Gardner", "Stephens", "Payne", "Pierce", "Berry",
        "Matthews", "Arnold", "Wagner", "Willis", "Ray", "Watkins", "Olson", "Carroll",
        "Duncan", "Snyder", "Hart", "Cunningham", "Bradley", "Lane", "Andrews", "Ruiz",
        "Harper", "Fox", "Riley", "Armstrong", "Carpenter", "Weaver", "Greene", "Lawrence",
        "Elliott", "Chavez", "Sims", "Austin", "Peters", "Kelley", "Franklin", "Lawson",
        "Nguyen", "Kim", "Patel", "Singh", "Chen", "Wang", "Ali", "Khan",
        "Ahmed", "Hassan", "Silva", "Costa", "Santos", "Oliveira", "Rossi", "Ferrari",
        "Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker",
        "Dubois", "Moreau", "Laurent", "Simon", "Michel", "Lefebvre", "Garcia", "Bernard",
        "Yamamoto", "Tanaka", "Suzuki", "Watanabe", "Ito", "Nakamura", "Kobayashi", "Sato",
        "Park", "Choi", "Jung", "Kang", "Yoon", "Han", "Oh", "Shin",
        "Okafor", "Mensah", "Diallo", "Traore", "Nwosu", "Abebe", "Okello", "Kamau",
    )

    fun fullName(forAuthorId: String, countryCode: String? = null): String {
        @Suppress("UNUSED_VARIABLE")
        val _c = countryCode
        val seed = hashSeed(normalizeAuthorId(forAuthorId))
        val given = givenNames[(seed % givenNames.size.toULong()).toInt()]
        val family = surnames[((seed / 97uL) % surnames.size.toULong()).toInt()]
        return "$given $family"
    }

    fun username(forAuthorId: String, countryCode: String? = null): String {
        val name = fullName(forAuthorId, countryCode)
        val slug = name.lowercase()
            .replace(" ", "")
            .replace("ü", "u")
            .filter { it.isLetterOrDigit() }
        val suffix = String.format("%02d", (hashSeed(normalizeAuthorId(forAuthorId)) % 100uL).toInt())
        val base = slug.take(14)
        return if (base.isEmpty()) "member$suffix" else "$base$suffix"
    }

    fun avatarUrl(forAuthorId: String): String {
        val id = normalizeAuthorId(forAuthorId)
        return "https://api.dicebear.com/7.x/notionists/png?seed=$id&backgroundColor=b6e3f4,c0aede,d1d4f9"
    }

    fun normalizeAuthorId(raw: String): String {
        val trimmed = raw.trim()
        if (!trimmed.startsWith("user_")) return trimmed
        val number = trimmed.removePrefix("user_").toIntOrNull() ?: return trimmed
        return String.format("user_%06d", number)
    }

    fun author(
        id: String,
        countryName: String? = null,
        countryCode: String? = null,
    ): PostAuthor {
        val normalized = normalizeAuthorId(id)
        return PostAuthor(
            userId = normalized,
            displayName = fullName(normalized),
            username = username(normalized),
            avatarUrl = avatarUrl(normalized),
            countryName = countryName,
            countryCode = countryCode?.uppercase(),
            lastReadAt = null,
        )
    }

    fun isPlaceholderDisplayName(value: String?): Boolean {
        val raw = value?.trim().orEmpty()
        if (raw.isEmpty()) return true
        if (Regex("""^User\s+\d+$""").containsMatchIn(raw)) return true
        if (Regex("""^user\d+$""", RegexOption.IGNORE_CASE).containsMatchIn(raw)) return true
        if (raw.lowercase().startsWith("user_")) return true
        if (raw.equals("Member", ignoreCase = true)) return true
        return false
    }

    private fun hashSeed(value: String): ULong {
        var hash = 2166136261uL
        for (byte in value.encodeToByteArray()) {
            hash = hash xor byte.toUByte().toULong()
            hash *= 16777619uL
        }
        return hash
    }
}
