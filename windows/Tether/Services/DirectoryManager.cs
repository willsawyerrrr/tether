using System.Diagnostics;
using Tether.Models;

namespace Tether.Services;

/// <summary>
/// Owns the list of added directories, their persisted state, and the
/// <see cref="RemoteControlSession"/> running for each one that is started.
/// </summary>
/// <remarks>
/// <see cref="Changed"/> may be raised from a background thread (child-process output/exit
/// callbacks run off the UI thread) — subscribers are responsible for marshalling back to the
/// UI thread before touching UI controls.
/// </remarks>
public sealed class DirectoryManager : IDisposable
{
    private readonly DirectoryStore _store = new();
    private readonly Dictionary<string, RemoteControlSession> _sessions = new(StringComparer.OrdinalIgnoreCase);

    public DirectoryManager()
    {
        Directories = _store.Load().Select(LoadDirectory).ToList();
    }

    /// <summary>
    /// Builds a directory from its persisted record. When the record's process id still belongs
    /// to a live <c>cmd</c>/<c>wsl</c> process — the two direct children <see
    /// cref="RemoteControlSession"/> ever launches — that process almost certainly still fronts
    /// this directory's server from before this app last quit (see the note on
    /// <see cref="Dispose"/>), so it's surfaced as <see cref="DirectoryStatus.RunningUntracked"/>
    /// rather than <see cref="DirectoryStatus.Stopped"/>, and its pid is kept so it can still be
    /// stopped — the alternative, starting a new session for the same directory, is exactly the
    /// orphaned-duplicate outcome this is meant to avoid. The join URL persisted with the record
    /// stays valid for as long as that process lives, so it is restored as
    /// <see cref="DirectoryStatus.Ready"/>; a server that hadn't reported one yet is surfaced as
    /// <see cref="DirectoryStatus.RunningUntracked"/>.
    /// </summary>
    private static ManagedDirectory LoadDirectory(DirectoryRecord record)
    {
        var directory = new ManagedDirectory { Path = record.Path };

        if (record.Pid is int pid && IsLikelyOrphanedSession(pid))
        {
            directory.Pid = pid;
            directory.JoinUrl = record.JoinUrl;
            directory.Status = record.JoinUrl is null ? DirectoryStatus.RunningUntracked : DirectoryStatus.Ready;
        }

        return directory;
    }

    private static bool IsLikelyOrphanedSession(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            return process.ProcessName is "cmd" or "wsl";
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
        {
            // No such process, or it exited between GetProcessById and reading ProcessName.
            return false;
        }
    }

    /// <summary>Directories the user has added, in the order they were added.</summary>
    public List<ManagedDirectory> Directories { get; }

    /// <summary>Raised whenever the directory list or any directory's status changes.</summary>
    public event Action? Changed;

    /// <summary>
    /// Adds a directory if it isn't already present and starts its server. Returns false if it
    /// was a duplicate.
    /// </summary>
    public bool AddDirectory(string path)
    {
        if (Directories.Any(d => string.Equals(d.Path, path, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var directory = new ManagedDirectory { Path = path };
        Directories.Add(directory);
        Persist();
        StartDirectory(directory);
        return true;
    }

    /// <summary>Stops the directory's server if running, then removes it from the list.</summary>
    public void RemoveDirectory(ManagedDirectory directory)
    {
        StopDirectory(directory);
        Directories.Remove(directory);
        Persist();
        Changed?.Invoke();
    }

    /// <summary>
    /// Starts the server for <paramref name="directory"/>, unless it's already running — whether
    /// as a session this instance is managing, or one detected as still running from before this
    /// app last started (see <see cref="IsDetachedRunning"/>; stop it first).
    /// </summary>
    public void StartDirectory(ManagedDirectory directory)
    {
        if (_sessions.ContainsKey(directory.Path) || IsDetachedRunning(directory))
        {
            return;
        }

        directory.Status = DirectoryStatus.Connecting;
        directory.JoinUrl = null;
        directory.ErrorMessage = null;

        var session = new RemoteControlSession(directory.Path, directory.Name);
        session.Ready += url => OnReady(directory, url);
        session.Failed += message => OnFailed(directory, message);
        session.Exited += () => OnExited(directory);
        _sessions[directory.Path] = session;

        try
        {
            session.Start();
            directory.Pid = session.ProcessId;
        }
        catch (Exception ex)
        {
            _sessions.Remove(directory.Path);
            session.Dispose();
            directory.Status = DirectoryStatus.Error;
            directory.ErrorMessage = ex.Message;
        }

        Persist();
        Changed?.Invoke();
    }

    /// <summary>
    /// Stops the server for <paramref name="directory"/> if it is running — whether as a session
    /// this instance is managing, or one detected as still running from before this app last
    /// started (by its pid alone, since nothing here launched it).
    /// </summary>
    public void StopDirectory(ManagedDirectory directory)
    {
        if (_sessions.TryGetValue(directory.Path, out var session))
        {
            session.Stop();
            return;
        }

        if (IsDetachedRunning(directory) && directory.Pid is int pid)
        {
            KillOrphan(pid);
            directory.Status = DirectoryStatus.Stopped;
            directory.JoinUrl = null;
            directory.Pid = null;
            Persist();
            Changed?.Invoke();
        }
    }

    /// <summary>
    /// Whether <paramref name="directory"/> is running from an earlier launch, with no session
    /// this instance is managing.
    /// </summary>
    private bool IsDetachedRunning(ManagedDirectory directory) =>
        !_sessions.ContainsKey(directory.Path)
        && directory.Status is DirectoryStatus.Ready or DirectoryStatus.RunningUntracked;

    private static void KillOrphan(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException)
        {
            // Already exited.
        }
    }

    private void OnReady(ManagedDirectory directory, string url)
    {
        directory.Status = DirectoryStatus.Ready;
        directory.JoinUrl = url;
        directory.ErrorMessage = null;
        Persist();
        Changed?.Invoke();
    }

    private void OnFailed(ManagedDirectory directory, string message)
    {
        directory.Status = DirectoryStatus.Error;
        directory.ErrorMessage = message;
        directory.JoinUrl = null;
        Changed?.Invoke();
    }

    private void OnExited(ManagedDirectory directory)
    {
        if (_sessions.TryGetValue(directory.Path, out var session))
        {
            _sessions.Remove(directory.Path);
            session.Dispose();
        }

        // A session that exited without ever becoming ready already went through OnFailed
        // (RemoteControlSession guarantees Failed fires before Exited in that case), so only a
        // clean stop or a post-ready crash reach here with a non-Error status.
        if (directory.Status != DirectoryStatus.Error)
        {
            directory.Status = DirectoryStatus.Stopped;
            directory.JoinUrl = null;
        }

        directory.Pid = null;
        Persist();
        Changed?.Invoke();
    }

    private void Persist()
    {
        _store.Save(Directories.Select(d => new DirectoryRecord { Path = d.Path, Pid = d.Pid, JoinUrl = d.JoinUrl }));
    }

    /// <summary>
    /// Releases this manager's own tracking of running sessions without stopping them: the
    /// servers they front are left running so they survive the app quitting or being reinstalled.
    /// See <see cref="LoadDirectory"/> for how the next launch detects them.
    /// </summary>
    public void Dispose()
    {
        foreach (var session in _sessions.Values)
        {
            session.Dispose();
        }
    }
}
