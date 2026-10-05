using System.Diagnostics;
using System.Text.RegularExpressions;

namespace Tether.Services;

/// <summary>
/// Wraps a single <c>claude remote-control</c> child process for one directory: starts it,
/// parses its stdout/stderr for readiness and errors, and stops it.
/// </summary>
public sealed class RemoteControlSession : IDisposable
{
    private static readonly Regex JoinUrlPattern =
        new(@"https://claude\.ai/code\?environment=\S+", RegexOptions.Compiled);

    private const string WorkspaceNotTrustedMarker = "Workspace not trusted";

    private readonly string _directoryPath;
    private readonly string _name;
    private Process? _process;
    private string? _lastStderrLine;
    private bool _becameReady;
    private bool _userRequestedStop;
    private bool _failed;

    public RemoteControlSession(string directoryPath, string name)
    {
        _directoryPath = directoryPath;
        _name = name;
    }

    /// <summary>Raised with the join URL once the server reports it is ready.</summary>
    public event Action<string>? Ready;

    /// <summary>Raised with an error message if the process reports a failure (e.g. untrusted workspace).</summary>
    public event Action<string>? Failed;

    /// <summary>Raised when the process exits, for any reason.</summary>
    public event Action? Exited;

    /// <summary>The launched process's id, once <see cref="Start"/> has been called.</summary>
    public int? ProcessId => _process?.Id;

    /// <summary>
    /// Starts <c>claude remote-control</c> with its working directory set to the target
    /// directory. Runs headless: stdin is closed immediately, and stdout/stderr are read
    /// asynchronously line by line.
    /// </summary>
    public void Start()
    {
        var startInfo = BuildStartInfo(ClaudeCommand.Current);

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        process.OutputDataReceived += OnOutputDataReceived;
        process.ErrorDataReceived += OnErrorDataReceived;
        process.Exited += (_, _) =>
        {
            if (!_becameReady && !_userRequestedStop && !_failed)
            {
                var message = _lastStderrLine
                    ?? $"claude remote-control exited unexpectedly (exit code {process.ExitCode}).";
                Failed?.Invoke(message);
            }

            Exited?.Invoke();
        };
        _process = process;

        process.Start();
        process.StandardInput.Close();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
    }

    /// <summary>
    /// Builds the launch command for <paramref name="strategy"/>: either <c>claude</c> directly
    /// on the Windows PATH (routed through <c>cmd.exe</c>, since an npm-installed global CLI is
    /// typically a <c>.cmd</c>/<c>.bat</c> shim that <see cref="Process.Start()"/> won't resolve
    /// on its own — it doesn't probe PATHEXT the way cmd.exe does), or, when Claude Code is only
    /// installed inside WSL, <c>wsl.exe --cd &lt;linux path&gt; -- &lt;claude&gt; ...</c>.
    /// </summary>
    private ProcessStartInfo BuildStartInfo(ClaudeCommand.Strategy strategy)
    {
        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        if (!strategy.UseWsl)
        {
            startInfo.FileName = "cmd.exe";
            startInfo.WorkingDirectory = _directoryPath;
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add("claude");
            startInfo.ArgumentList.Add("remote-control");
            startInfo.ArgumentList.Add("--name");
            startInfo.ArgumentList.Add(_name);
            startInfo.ArgumentList.Add("--no-create-session-in-dir");
            return startInfo;
        }

        var (linuxPath, distro) = WslPath.Translate(_directoryPath);

        startInfo.FileName = "wsl.exe";
        if (distro is not null)
        {
            startInfo.ArgumentList.Add("-d");
            startInfo.ArgumentList.Add(distro);
        }

        startInfo.ArgumentList.Add("--cd");
        startInfo.ArgumentList.Add(linuxPath);
        startInfo.ArgumentList.Add("--");
        startInfo.ArgumentList.Add(strategy.WslClaudePath!);
        startInfo.ArgumentList.Add("remote-control");
        startInfo.ArgumentList.Add("--name");
        startInfo.ArgumentList.Add(_name);
        startInfo.ArgumentList.Add("--no-create-session-in-dir");
        return startInfo;
    }

    private void OnOutputDataReceived(object? sender, DataReceivedEventArgs e)
    {
        if (e.Data is null)
        {
            return;
        }

        var line = AnsiStripper.Strip(e.Data);
        FailOnWorkspaceNotTrusted(line);

        var match = JoinUrlPattern.Match(line);
        if (match.Success)
        {
            _becameReady = true;
            Ready?.Invoke(match.Value);
        }
    }

    private void OnErrorDataReceived(object? sender, DataReceivedEventArgs e)
    {
        if (e.Data is null)
        {
            return;
        }

        var line = AnsiStripper.Strip(e.Data);
        if (!string.IsNullOrWhiteSpace(line))
        {
            _lastStderrLine = line;
        }

        FailOnWorkspaceNotTrusted(line);
    }

    /// <summary>
    /// Reports the exact line as the failure the moment the trust error appears on either
    /// stream, rather than waiting for exit and guessing from whatever line stderr saw last.
    /// </summary>
    private void FailOnWorkspaceNotTrusted(string line)
    {
        if (_failed || _becameReady || !line.Contains(WorkspaceNotTrustedMarker, StringComparison.Ordinal))
        {
            return;
        }

        _failed = true;
        Failed?.Invoke(line);
    }

    /// <summary>
    /// Terminates the process. A detached child process has no console to deliver a Ctrl+C /
    /// Ctrl+Break event to on Windows, so there is no graceful-shutdown signal available the way
    /// SIGTERM is on Unix; killing the whole process tree is the only reliable option.
    /// </summary>
    public void Stop()
    {
        if (_process is null)
        {
            return;
        }

        // Marks this as a deliberate stop so the exit handler reports it as such, rather than as
        // a failure just because it happened before the process ever reported ready.
        _userRequestedStop = true;

        try
        {
            if (!_process.HasExited)
            {
                _process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
            // Process already exited between the HasExited check and Kill.
        }
    }

    public void Dispose()
    {
        if (_process is null)
        {
            return;
        }

        _process.OutputDataReceived -= OnOutputDataReceived;
        _process.ErrorDataReceived -= OnErrorDataReceived;
        _process.Dispose();
    }
}
