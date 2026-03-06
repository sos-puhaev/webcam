func formatMAC(_ input: String) -> String {
    let hex = input.uppercased().filter { "0123456789ABCDEF".contains($0) }
    var result = ""

    for (index, char) in hex.enumerated() {
        if index != 0 && index % 2 == 0 {
            result.append(":")
        }
        if result.count < 17 {
            result.append(char)
        }
    }
    return result
}
