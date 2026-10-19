// SPDX-License-Identifier: LGPL-3.0-only
// Sec-MS-GEC v2 algorithm adapted from rany2/edge-tts, src/edge_tts/drm.py.
// Upstream contributors: rany and HarryXiaoCN. Swift adaptation, 2026.
// Source: https://github.com/rany2/edge-tts/blob/master/src/edge_tts/drm.py
// License: https://www.gnu.org/licenses/lgpl-3.0.html

import Foundation

/// v2 is a modified SHA-256 plus CS64 checksum; ordinary CryptoKit SHA256 is not equivalent.
enum EdgeSpeechToken {
    static func generate(date: Date) -> String {
        let seconds = floor((date.timeIntervalSince1970 + 11_644_473_600) / 300) * 300
        let text = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), seconds * 10_000_000)
            + EdgeSpeechProtocol.clientToken
        let bytes = Array(text.utf8)
        let digest = sha256(bytes)
        let checksum = cs64(bytes, digest: digest)
        return hex(checksum) + "-" + hex(digest)
    }

    private static let initial: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
    ]
    private static let partialState: [UInt32] = [
        0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
        0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2
    ]
    private static let partialSchedule: [UInt32] = [
        0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA,
        0xA622EE8C, 0xD1DD9491, 0xC0DD25A0, 0xF9E70AB6,
        0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33,
        0xD258B060, 0x72766564
    ]
    private static let rounds: [UInt32] = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
    ]

    private static func rotate(_ x: UInt32, _ count: UInt32) -> UInt32 {
        (x >> count) | (x << (32 - count))
    }
    private static func sigma0(_ x: UInt32) -> UInt32 { rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3) }
    private static func sigma1(_ x: UInt32) -> UInt32 { rotate(x, 17) ^ rotate(x, 19) ^ (x >> 10) }
    private static func expand(_ words: inout [UInt32]) {
        while words.count < 64 {
            let i = words.count
            words.append(sigma1(words[i - 2]) &+ words[i - 7] &+ sigma0(words[i - 15]) &+ words[i - 16])
        }
    }
    private static func compress(_ state: [UInt32], _ words: [UInt32], startingAt first: Int = 0) -> [UInt32] {
        var s = state
        for i in first..<64 {
            let k: UInt32 = first == 14 && i == 14 ? 0xC9DC06A7 : rounds[i]
            let choice = (s[4] & s[5]) ^ (~s[4] & s[6])
            let majority = (s[0] & s[1]) ^ (s[0] & s[2]) ^ (s[1] & s[2])
            let t1 = s[7] &+ (rotate(s[4], 6) ^ rotate(s[4], 11) ^ rotate(s[4], 25)) &+ choice &+ k &+ words[i]
            let t2 = (rotate(s[0], 2) ^ rotate(s[0], 13) ^ rotate(s[0], 22)) &+ majority
            s = [t1 &+ t2, s[0], s[1], s[2], s[3] &+ t1, s[4], s[5], s[6]]
        }
        return s
    }
    private static func bigWord(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private static func littleWord(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        var words = [UInt32](repeating: 0, count: 14)
        words.append(bigWord(bytes[0..<3]))
        words.append(bigWord(bytes[3..<7]))
        for i in 16..<30 {
            var value = partialSchedule[i - 16]
            if i - 2 >= 14 { value = value &+ (sigma1(words[i - 2]) ^ (i == 16 ? 0x000B92C0 : 0)) }
            if i - 7 >= 14 { value = value &+ words[i - 7] }
            if i - 15 >= 14 { value = value &+ (sigma0(words[i - 15]) ^ (i == 29 ? 0x059C0B80 : 0)) }
            words.append(value)
        }
        words.append(sigma1(words[28]) &+ words[23] &+ sigma0(words[15]) &+ words[14] &+ 0xC9DC06A7 &- rounds[14])
        expand(&words)
        var state = zip(initial, compress(partialState, words, startingAt: 14)).map { $0 &+ $1 }

        let length = 57 + bytes.count
        var padded = Array(bytes.dropFirst(7)) + [UInt8(0x80)]
        padded += [UInt8](repeating: 0, count: (119 - length % 64) % 64)
        let bitLength = UInt64(length) * 8
        padded += stride(from: 56, through: 0, by: -8).map { UInt8(truncatingIfNeeded: bitLength >> $0) }
        for offset in stride(from: 0, to: padded.count, by: 64) {
            words = stride(from: offset, to: offset + 64, by: 4).map { bigWord(padded[$0..<($0 + 4)]) }
            expand(&words)
            state = zip(state, compress(state, words)).map { $0 &+ $1 }
        }
        return state.flatMap { word in [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: word >> $0) } }
    }

    private static let coefficients: [(UInt32, UInt32)] = [
        (0xE82E91B1, 0xB32700D0), (0x44DE24C6, 0x88DFF51D), (0x3BEB65BC, 0x29514038),
        (0xC89C5933, 0xB328CBDF), (0x8D1EC211, 0xD405B4D5), (0x314EF5D5, 0x26E55F3C),
        (0xE92491B1, 0x607801C6), (0xF0A5B9D5, 0x82B2C1FB), (0x06064CF3, 0xFA51A3DA),
        (0xDA79FA60, 0x207CC464), (0xBED20560, 0x3C3C74F3), (0x89F9C9F8, 0xD2D14B61),
        (0x35FA38C6, 0xBB04A2C1), (0xCB49E3C6, 0xC5626167)
    ]
    private static func cs64(_ bytes: [UInt8], digest: [UInt8]) -> [UInt8] {
        let keys = [littleWord(digest[0..<4]) | 1, littleWord(digest[4..<8]) | 1]
        let factors = keys.map { $0 &* 0x82893933 }
        var terms = coefficients.enumerated().map { $0.element.0 &* factors[$0.offset % 2] }
        var offsets = coefficients.map { $0.1 }
        var padded = [UInt8(0)] + bytes
        padded += [UInt8](repeating: 0, count: (8 - padded.count % 8) % 8)
        for i in 0..<(padded.count / 4) {
            let word = littleWord(padded[(i * 4)..<(i * 4 + 4)])
            var term = word &* keys[i % 2]
            var offset = rotate(word, 16) &* (i % 2 == 0 ? 0xEF0569FB : 0xC31713DB)
            if i == 0 {
                term = term &+ (0xF2F90B1A &* factors[0])
                offset = offset &+ 0x0B1A0000
            }
            terms.append(term)
            offsets.append(offset)
        }
        var swappedSum: UInt32 = 0
        var swappedLast: UInt32 = 0
        var state: UInt32 = 0
        var sum: UInt32 = 0
        for i in stride(from: 0, to: terms.count, by: 2) {
            let q1 = rotate(offsets[i] &+ terms[i], 16) &* 0x76F50F34
            let q2 = rotate(offsets[i + 1] &+ terms[i + 1], 16) &* 0x1881CE3C
            swappedLast = (rotate(q2, 16) &* 0x35BD1EC9) &+ q2
            swappedSum = swappedSum &+ (rotate(q1, 16) &* 0xC3EFEA97) &+ q1 &+ swappedLast
            state = (state &* keys[0]) &+ terms[i]
            for factor: UInt32 in [0xCF98B111, 0x87085B9F, 0x12CEB96D, 0x257E1D83] {
                state = rotate(state, 16) &* factor
            }
            sum = sum &+ state
            state = (state &* keys[1]) &+ terms[i + 1]
            for factor: UInt32 in [0xA27416F5, 0xD38396FF, 0x7C932B89, 0xBFA49F69] {
                state = rotate(state, 16) &* factor
            }
            sum = sum &+ state
        }
        return [swappedLast ^ state, swappedSum ^ sum].flatMap { word in
            [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: word >> $0) }
        }
    }
    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
