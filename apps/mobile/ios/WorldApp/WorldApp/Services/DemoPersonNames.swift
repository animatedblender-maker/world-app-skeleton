import Foundation

/// Demo / seed people names drawn from popular lists on [Behind the Name](https://www.behindthename.com/)
/// (given names) and common US surnames (also catalogued there).
///
/// Names are deterministic per author ID so the same fake user always looks the same.
enum DemoPersonNames {
    // Popular given names (Behind the Name / SSA-style lists — mixed genders, global feel).
    private static let givenNames: [String] = [
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
    ]

    // Common surnames listed on Behind the Name (US census–style popularity).
    private static let surnames: [String] = [
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
    ]

    /// Stable full name for a demo author id (e.g. `user_000042`).
    /// Identity is **only** the author id — same Reddit fake user ⇒ same Matterya person
    /// everywhere (posts, comments, profile), regardless of country on a given row.
    static func fullName(forAuthorID authorID: String, countryCode: String? = nil) -> String {
        _ = countryCode // location is separate; never part of identity
        let seed = hashSeed(normalizeAuthorID(authorID))
        let given = givenNames[Int(seed % UInt64(givenNames.count))]
        let family = surnames[Int((seed / 97) % UInt64(surnames.count))]
        return "\(given) \(family)"
    }

    /// Stable username handle derived from the full name + author id.
    static func username(forAuthorID authorID: String, countryCode: String? = nil) -> String {
        let name = fullName(forAuthorID: authorID, countryCode: countryCode)
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "ü", with: "u")
            .filter { $0.isLetter || $0.isNumber }
        let suffix = String(format: "%02d", Int(hashSeed(normalizeAuthorID(authorID)) % 100))
        let base = String(slug.prefix(14))
        return base.isEmpty ? "member\(suffix)" : "\(base)\(suffix)"
    }

    /// Canonical avatar seed (DiceBear) — same id always same face.
    static func avatarURL(forAuthorID authorID: String) -> String {
        let id = normalizeAuthorID(authorID)
        return "https://api.dicebear.com/7.x/notionists/png?seed=\(id)&backgroundColor=b6e3f4,c0aede,d1d4f9"
    }

    /// Normalize `user_123` → `user_000123` so ids collide correctly.
    static func normalizeAuthorID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("user_"),
              let number = Int(trimmed.replacingOccurrences(of: "user_", with: ""))
        else { return trimmed }
        return String(format: "user_%06d", number)
    }

    static func author(
        id authorID: String,
        countryName: String? = nil,
        countryCode: String? = nil
    ) -> PostAuthor {
        let id = normalizeAuthorID(authorID)
        return PostAuthor(
            userID: id,
            displayName: fullName(forAuthorID: id),
            username: username(forAuthorID: id),
            avatarURL: avatarURL(forAuthorID: id),
            countryName: countryName,
            countryCode: countryCode?.uppercased(),
            lastReadAt: nil
        )
    }

    /// True when a stored display name is still a placeholder like "User 000123".
    static func isPlaceholderDisplayName(_ value: String?) -> Bool {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return true
        }
        if raw.range(of: #"^User\s+\d+$"#, options: .regularExpression) != nil { return true }
        if raw.range(of: #"^user\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if raw.lowercased().hasPrefix("user_") { return true }
        if raw.caseInsensitiveCompare("Member") == .orderedSame { return true }
        return false
    }

    private static func hashSeed(_ value: String) -> UInt64 {
        var hash: UInt64 = 2166136261
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 16777619
        }
        return hash
    }
}
