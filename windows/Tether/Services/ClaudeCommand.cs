using System.Diagnostics;

namespace Tether.Services;

/// <summary>
/// Resolves how to invoke the <c>claude</c> CLI on this machine: natively on the Windows PATH,
/// or — since many Windows machines only ever have Claude Code installed inside WSL — by
/// shelling out to a WSL distribution's login shell. Resolved once and cached for the app's
/// lifetime.
/// </summary>
public static class ClaudeCommand
{
    private static readonly Lazy<Strategy> Resolved = new(Resolve);

    public static Strategy Current => Resolved.Value;

    /// <param name="UseWsl">False to invoke <c>claude</c> directly on the Windows PATH.</param>
    /// <param name="WslClaudePath">
    /// Absolute path to <c>claude</c> inside WSL's default distribution, when <see cref="UseWsl"/>
    /// is true.
    /// </param>
    public sealed record Strategy(bool UseWsl, string? WslClaudePath);

    private static Strategy Resolve()
    {
        if (IsNativeClaudeAvailable())
        {
            return new Strategy(UseWsl: false, WslClaudePath: null);
        }

        var wslClaudePath = TryResolveClaudeInWsl();
        return new Strategy(UseWsl: wslClaudePath is not null, WslClaudePath: wslClaudePath);
    }

    private static bool IsNativeClaudeAvailable()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "cmd.exe",
                ArgumentList = { "/c", "where", "claude" },
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            });
            if (process is null)
            {
                return false;
            }

            process.WaitForExit(5000);
            return process.ExitCode == 0;
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return false;
        }
    }

    /// <summary>
    /// Looks up <c>claude</c> inside WSL's default distribution, via a login shell so PATH
    /// customizations in the user's shell profile (e.g. a Homebrew or nvm install of the CLI)
    /// are picked up the same way they would be from an interactive WSL terminal. Only the
    /// default distribution is checked — a directory that resolves to a different distribution
    /// (see <see cref="WslPath.Translate"/>) is assumed to share the same install.
    /// </summary>
    private static string? TryResolveClaudeInWsl()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "wsl.exe",
                ArgumentList = { "-e", "zsh", "-lc", "command -v claude" },
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            });
            if (process is null)
            {
                return null;
            }

            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(10000);

            var path = output.Trim();
            return process.ExitCode == 0 && path.Length > 0 ? path : null;
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }
}
