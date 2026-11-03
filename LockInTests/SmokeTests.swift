import Testing

struct SmokeTests {
    @Test func durationFormatting() {
        #expect(DurationFormat.clock(65) == "1:05")
        #expect(DurationFormat.clock(3725) == "1:02:05")
        #expect(DurationFormat.short(5400) == "1h 30m")
    }
}
