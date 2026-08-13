public enum Flags {
    /// ISO 3166-1 alpha-2 → flag emoji via Unicode regional indicators. nil for anything not 2 ASCII letters.
    public static func emoji(countryCode: String) -> String? {
        let code = countryCode.uppercased()
        guard code.count == 2, code.allSatisfy({ ("A"..."Z").contains($0) }) else { return nil }
        var out = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard let regional = Unicode.Scalar(0x1F1E6 + scalar.value - Unicode.Scalar("A").value) else { return nil }
            out.append(regional)
        }
        return String(out)
    }
}
