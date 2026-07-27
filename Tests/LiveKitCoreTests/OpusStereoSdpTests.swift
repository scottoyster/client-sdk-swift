/*
 * Copyright 2026 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

@testable import LiveKit
import Testing

struct OpusStereoSdpTests {
    /// Two audio sections: mid 0 is sent in stereo, mid 1 is not.
    private static let offer = """
    v=0\r
    o=- 0 0 IN IP4 127.0.0.1\r
    s=-\r
    t=0 0\r
    m=audio 9 UDP/TLS/RTP/SAVPF 111\r
    a=mid:0\r
    a=rtpmap:111 opus/48000/2\r
    a=fmtp:111 minptime=10;useinbandfec=1;sprop-stereo=1\r
    m=audio 9 UDP/TLS/RTP/SAVPF 111\r
    a=mid:1\r
    a=rtpmap:111 opus/48000/2\r
    a=fmtp:111 minptime=10;useinbandfec=1\r
    m=video 9 UDP/TLS/RTP/SAVPF 96\r
    a=mid:2\r
    a=rtpmap:96 VP8/90000\r
    """

    @Test func extractsOnlyStereoSendingMids() {
        #expect(Transport.stereoMids(fromOffer: Self.offer) == ["0"])
    }

    @Test func addsStereoToMatchingMidOnly() {
        let answer = Transport.mungeOpusStereo(Self.offer, stereoMids: ["0"])
        let lines = answer.components(separatedBy: "\r\n")

        let fmtps = lines.filter { $0.hasPrefix("a=fmtp:111") }
        #expect(fmtps.count == 2)
        #expect(fmtps[0].hasSuffix(";stereo=1"))
        // mid 1 was not in the set, so it must be untouched.
        #expect(!fmtps[1].contains("stereo=1"))
    }

    /// `sprop-stereo=1` contains "stereo=1" as a substring. A naive
    /// `contains` check (as in client-sdk-js) treats the section as already
    /// stereo and skips it — leaving the receiver in mono, which is the exact
    /// bug this code exists to fix.
    @Test func spropStereoDoesNotSuppressTheReceiverPreference() {
        let munged = Transport.mungeOpusStereo(Self.offer, stereoMids: ["0"])
        let fmtp = munged.components(separatedBy: "\r\n")
            .first { $0.hasPrefix("a=fmtp:111") }
        #expect(fmtp?.contains("sprop-stereo=1") == true)
        #expect(fmtp?.hasSuffix(";stereo=1") == true)
    }

    @Test func isIdempotent() {
        let once = Transport.mungeOpusStereo(Self.offer, stereoMids: ["0"])
        let twice = Transport.mungeOpusStereo(once, stereoMids: ["0"])
        #expect(once == twice)
    }

    @Test func emptyMidSetIsANoOp() {
        #expect(Transport.mungeOpusStereo(Self.offer, stereoMids: []) == Self.offer)
    }

    @Test func preservesLineEndings() {
        let lf = Self.offer.replacingOccurrences(of: "\r\n", with: "\n")
        let munged = Transport.mungeOpusStereo(lf, stereoMids: ["0"])
        #expect(!munged.contains("\r\n"))
        #expect(munged.contains(";stereo=1"))
    }

    /// A payload type other than 111, and a section whose `a=mid:` comes
    /// AFTER its `a=fmtp:` — legal SDP, and the reason the munger resolves
    /// mids in a first pass before rewriting.
    @Test func handlesMidAfterFmtpAndNonDefaultPayload() {
        let sdp = """
        v=0\r
        m=audio 9 UDP/TLS/RTP/SAVPF 63\r
        a=rtpmap:63 opus/48000/2\r
        a=fmtp:63 useinbandfec=1;sprop-stereo=1\r
        a=mid:audio0\r
        """
        #expect(Transport.stereoMids(fromOffer: sdp) == ["audio0"])
        let munged = Transport.mungeOpusStereo(sdp, stereoMids: ["audio0"])
        #expect(munged.contains("a=fmtp:63 useinbandfec=1;sprop-stereo=1;stereo=1"))
    }

    @Test func ignoresNonOpusAudioCodecs() {
        let sdp = """
        v=0\r
        m=audio 9 UDP/TLS/RTP/SAVPF 8\r
        a=mid:0\r
        a=rtpmap:8 PCMA/8000\r
        a=fmtp:8 sprop-stereo=1\r
        """
        #expect(Transport.stereoMids(fromOffer: sdp).isEmpty)
    }
}
