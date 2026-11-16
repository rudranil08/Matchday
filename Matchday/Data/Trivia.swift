import Foundation

// Fixed facts, checked by hand. The daily quiz mixes these with questions built from live data.
struct TriviaQuestion: Codable, Hashable {
    let q: String
    let options: [String]
    let answer: Int
    let why: String
}

let trivia: [TriviaQuestion] = [
    .init(q: "Which club went the whole 2003–04 Premier League season unbeaten?", options: ["Chelsea", "Arsenal", "Man Utd", "Liverpool"], answer: 1, why: "Arsenal’s “Invincibles” won 26 and drew 12."),
    .init(q: "Who is the Premier League’s all-time top scorer?", options: ["Wayne Rooney", "Harry Kane", "Alan Shearer", "Thierry Henry"], answer: 2, why: "Alan Shearer scored 260 Premier League goals."),
    .init(q: "Who scored 41 goals in a single Bundesliga season?", options: ["Gerd Müller", "Harry Kane", "Robert Lewandowski", "Erling Haaland"], answer: 2, why: "Lewandowski did it for Bayern in 2020–21."),
    .init(q: "Which club won the 2023–24 Bundesliga without losing a game?", options: ["Bayern Munich", "Dortmund", "Bayer Leverkusen", "RB Leipzig"], answer: 2, why: "Leverkusen went all 34 league games unbeaten."),
    .init(q: "Who is LaLiga’s all-time top scorer?", options: ["Cristiano Ronaldo", "Lionel Messi", "Telmo Zarra", "Hugo Sánchez"], answer: 1, why: "Messi scored 474 LaLiga goals for Barcelona."),
    .init(q: "Which club won Ligue 1 in 2016–17, ending PSG’s run?", options: ["Lyon", "Marseille", "Monaco", "Lille"], answer: 2, why: "Monaco won it with Mbappé breaking through."),
    .init(q: "Which club has won the most Premier League titles?", options: ["Man City", "Man Utd", "Chelsea", "Arsenal"], answer: 1, why: "Manchester United won 13 under Sir Alex Ferguson."),
    .init(q: "Which country hosted the 2022 World Cup?", options: ["Qatar", "Russia", "UAE", "Saudi Arabia"], answer: 0, why: "Argentina beat France in the final in Lusail."),
    .init(q: "Which club won the 2015–16 Premier League at 5000–1?", options: ["Tottenham", "Leicester City", "West Ham", "Southampton"], answer: 1, why: "Claudio Ranieri’s Leicester finished 10 points clear."),
    .init(q: "How many points did Man City reach in 2017–18?", options: ["95", "98", "100", "102"], answer: 2, why: "Pep Guardiola’s “Centurions” were the first to 100."),
    .init(q: "How many Premier League goals did Erling Haaland score in 2022–23?", options: ["32", "34", "36", "38"], answer: 2, why: "A record for a 38-game Premier League season."),
    .init(q: "Who scored the Premier League’s fastest hat-trick?", options: ["Sadio Mané", "Robbie Fowler", "Mohamed Salah", "Sergio Agüero"], answer: 0, why: "2 minutes 56 seconds for Southampton against Aston Villa in 2015."),
    .init(q: "Which goalkeeper kept the most Premier League clean sheets?", options: ["David de Gea", "Edwin van der Sar", "Petr Čech", "David James"], answer: 2, why: "Čech kept 202 for Chelsea and Arsenal."),
    .init(q: "Which club has won the most LaLiga titles?", options: ["Barcelona", "Real Madrid", "Atlético Madrid", "Athletic Club"], answer: 1, why: "Real Madrid have won more than 35."),
    .init(q: "Which club has won the most Bundesliga titles?", options: ["Dortmund", "Bayern Munich", "Mönchengladbach", "Hamburg"], answer: 1, why: "Bayern have won over 30, including 11 in a row from 2013 to 2023."),
    .init(q: "Which club has won the most Ligue 1 titles?", options: ["Saint-Étienne", "Marseille", "PSG", "Lyon"], answer: 2, why: "PSG passed Saint-Étienne’s record of 10 in 2023."),
    .init(q: "Lyon won Ligue 1 how many times in a row from 2002?", options: ["5", "6", "7", "8"], answer: 2, why: "Seven straight titles, 2001–02 to 2007–08."),
    .init(q: "Who won the 2022 Ballon d’Or?", options: ["Lionel Messi", "Karim Benzema", "Robert Lewandowski", "Kevin De Bruyne"], answer: 1, why: "Benzema won it after a 44-goal season for Real Madrid."),
    .init(q: "Which country won Euro 2024?", options: ["England", "France", "Spain", "Germany"], answer: 2, why: "Spain beat England 2–1 in the final in Berlin."),
    .init(q: "Which club did Arsène Wenger manage for 22 years?", options: ["Monaco", "Arsenal", "Nagoya Grampus", "PSG"], answer: 1, why: "From 1996 to 2018, with three league titles."),
    .init(q: "Who is the Bundesliga’s all-time top scorer?", options: ["Robert Lewandowski", "Gerd Müller", "Klaus Fischer", "Jupp Heynckes"], answer: 1, why: "Gerd Müller scored 365 Bundesliga goals for Bayern."),
]

/// Today's five questions: the same set all day, a new set tomorrow.
func dailyTrivia(count: Int, day: Date = Date()) -> [Int] {
    let dayNumber = Int(day.timeIntervalSince1970 / 86_400)
    var rng = SeededGenerator(seed: UInt64(dayNumber))
    return Array(trivia.indices.shuffled(using: &rng).prefix(count))
}

/// Small deterministic generator (SplitMix64), so "today's" shuffle is the same on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
