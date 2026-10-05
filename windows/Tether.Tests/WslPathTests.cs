using Tether.Services;

namespace Tether.Tests;

public class WslPathTests
{
    [Theory]
    [InlineData(@"C:\Users\me\proj", "/mnt/c/Users/me/proj")]
    [InlineData(@"D:\code", "/mnt/d/code")]
    public void Translate_MapsDrivePathsToMnt(string input, string expected)
    {
        var (linux, distro) = WslPath.Translate(input);
        Assert.Equal(expected, linux);
        Assert.Null(distro);
    }

    [Theory]
    [InlineData(@"\\wsl.localhost\Ubuntu\home\me\proj", "/home/me/proj", "Ubuntu")]
    [InlineData(@"\\wsl$\Debian\srv", "/srv", "Debian")]
    [InlineData(@"\\WSL.LOCALHOST\Ubuntu-22.04\tmp", "/tmp", "Ubuntu-22.04")]
    public void Translate_MapsWslUncPathsAndReturnsDistro(string input, string expected, string expectedDistro)
    {
        var (linux, distro) = WslPath.Translate(input);
        Assert.Equal(expected, linux);
        Assert.Equal(expectedDistro, distro);
    }

    [Fact]
    public void Translate_FallsBackToSlashConversion()
    {
        var (linux, distro) = WslPath.Translate(@"relative\dir");
        Assert.Equal("relative/dir", linux);
        Assert.Null(distro);
    }
}
