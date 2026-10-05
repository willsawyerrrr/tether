using Tether.Services;

namespace Tether.Tests;

public class AnsiStripperTests
{
    [Fact]
    public void Strip_LeavesPlainTextUntouched() =>
        Assert.Equal("hello world", AnsiStripper.Strip("hello world"));

    [Fact]
    public void Strip_RemovesCursorMovementAndEraseCodes() =>
        Assert.Equal("Ready", AnsiStripper.Strip("\x1b[7A\x1b[JReady"));

    [Fact]
    public void Strip_RemovesColourCodesWithParameters() =>
        Assert.Equal("ok", AnsiStripper.Strip("\x1b[1;32mok\x1b[0m"));

    [Fact]
    public void Strip_RemovesSequencesWithIntermediateBytes() =>
        Assert.Equal("x", AnsiStripper.Strip("\x1b[2 qx"));

    [Fact]
    public void Strip_PreservesNewlines() =>
        Assert.Equal("a\nb", AnsiStripper.Strip("\x1b[Ka\n\x1b[Kb"));

    [Fact]
    public void Strip_ReturnsEmptyForEmpty() =>
        Assert.Equal(string.Empty, AnsiStripper.Strip(string.Empty));
}
