import Foundation

struct GlowCommandInterpreter {
    func interpret(_ recognizedText: String) -> GlowCommand {
        let words = Self.normalizedWords(from: recognizedText)
        guard !words.isEmpty else { return .unknown }

        if Self.containsAnySequence([
            ["check", "connection"], ["check", "the", "connection"],
            ["check", "my", "light", "connection"],
            ["connection", "status"], ["light", "connected"],
            ["is", "my", "light", "connected"]
        ], in: words) {
            return .checkConnection
        }
        if Self.containsAnySequence([
            ["reconnect"], ["connect", "again"], ["connect", "to", "the", "light"],
            ["connect", "to", "my", "light"]
        ], in: words) {
            return .reconnect
        }
        if let brightness = Self.brightness(in: words) {
            return .setBrightness(brightness)
        }
        if let color = Self.color(in: words) {
            return .setColor(color)
        }
        if Self.isPowerOn(words) { return .powerOn }
        if Self.isPowerOff(words) { return .powerOff }

        return .unknown
    }

    private static func normalizedWords(from text: String) -> [String] {
        let lowercased = text.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
        let normalized = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                return " "
            }
            return Character(scalar)
        }
        return String(normalized)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func containsAnySequence(_ sequences: [[String]], in words: [String]) -> Bool {
        sequences.contains { containsSequence($0, in: words) }
    }

    private static func containsSequence(_ sequence: [String], in words: [String]) -> Bool {
        guard !sequence.isEmpty, words.count >= sequence.count else { return false }
        return (0...(words.count - sequence.count)).contains { start in
            Array(words[start..<(start + sequence.count)]) == sequence
        }
    }

    private static func brightness(in words: [String]) -> Int? {
        guard let brightnessIndex = words.firstIndex(where: { $0 == "brightness" || $0 == "bright" }) else {
            return nil
        }

        var index = brightnessIndex + 1
        while index < words.count {
            let word = words[index]
            if word == "percent" || word == "percentage" {
                index += 1
                continue
            }
            if word == "to" || word == "at" || word == "is" {
                index += 1
                continue
            }
            guard let number = numberValue(at: index, in: words), (0...100).contains(number.value) else {
                return nil
            }
            return number.value
        }
        return nil
    }

    private static func numberValue(at index: Int, in words: [String]) -> (value: Int, length: Int)? {
        if let value = Int(words[index]) { return (value, 1) }

        let values: [String: Int] = [
            "zero": 0,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
            "seven": 7,
            "eight": 8,
            "nine": 9,
            "ten": 10,
            "eleven": 11,
            "twelve": 12,
            "thirteen": 13,
            "fourteen": 14,
            "fifteen": 15,
            "sixteen": 16,
            "seventeen": 17,
            "eighteen": 18,
            "nineteen": 19,
            "twenty": 20,
            "thirty": 30,
            "forty": 40,
            "fifty": 50,
            "sixty": 60,
            "seventy": 70,
            "eighty": 80,
            "ninety": 90,
            "onehundred": 100
        ]
        guard let value = values[words[index]] else { return nil }
        if value == 1, words.indices.contains(index + 1), words[index + 1] == "hundred" {
            return (100, 2)
        }
        if value >= 20, value.isMultiple(of: 10), words.indices.contains(index + 1),
           let ones = values[words[index + 1]], (1...9).contains(ones) {
            return (value + ones, 2)
        }
        return (value, 1)
    }

    private static func color(in words: [String]) -> GlowColor? {
        if containsSequence(["warm", "white"], in: words) { return .warmWhite }
        if containsSequence(["cool", "white"], in: words) { return .coolWhite }

        for color in GlowColor.allCases {
            let colorWords = color.displayName.lowercased().split(separator: " ").map(String.init)
            if containsSequence(colorWords, in: words) { return color }
        }
        return nil
    }

    private static func isPowerOn(_ words: [String]) -> Bool {
        containsAnySequence([
            ["turn", "on"], ["switch", "on"], ["power", "on"],
            ["turn", "it", "on"], ["switch", "it", "on"],
            ["turn", "the", "light", "on"], ["turn", "the", "lights", "on"],
            ["switch", "the", "light", "on"], ["switch", "the", "lights", "on"],
            ["lights", "on"], ["light", "on"]
        ], in: words)
    }

    private static func isPowerOff(_ words: [String]) -> Bool {
        containsAnySequence([
            ["turn", "off"], ["switch", "off"], ["power", "off"],
            ["turn", "it", "off"], ["switch", "it", "off"],
            ["turn", "the", "light", "off"], ["turn", "the", "lights", "off"],
            ["switch", "the", "light", "off"], ["switch", "the", "lights", "off"],
            ["lights", "off"], ["light", "off"]
        ], in: words)
    }
}