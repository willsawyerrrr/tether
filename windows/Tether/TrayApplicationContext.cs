using System.Runtime.InteropServices;
using Tether.Models;
using Tether.Services;

namespace Tether;

/// <summary>
/// Application shell: a tray icon with a context menu listing added directories and their
/// status, driven entirely by <see cref="DirectoryManager"/>. There is no main window.
/// </summary>
public sealed class TrayApplicationContext : ApplicationContext
{
    private readonly DirectoryManager _manager;
    private readonly NotifyIcon _notifyIcon;

    // An invisible control whose sole purpose is to give us a window handle to marshal
    // DirectoryManager.Changed callbacks (which can arrive on a background thread) back onto
    // the UI thread via Invoke/BeginInvoke.
    private readonly Control _uiThread = new();

    // NotifyIcon's own right-click path calls this internally before showing its context menu;
    // showing the menu manually (below, for left-click) has to do the same or the menu never
    // becomes the foreground window, so Windows never detects a click elsewhere as "lost focus"
    // and the menu lingers open until it's clicked on directly.
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    public TrayApplicationContext()
    {
        _uiThread.CreateControl();

        _manager = new DirectoryManager();
        _manager.Changed += OnManagerChanged;

        _notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Tether",
            ContextMenuStrip = new ContextMenuStrip(),
            Visible = true,
        };
        _notifyIcon.ContextMenuStrip!.Opening += (_, _) => RebuildMenu();

        // NotifyIcon only opens its ContextMenuStrip automatically on a right-click; show it on
        // a left-click too so the tray icon behaves the same either way.
        _notifyIcon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left)
            {
                SetForegroundWindow(_uiThread.Handle);
                _notifyIcon.ContextMenuStrip!.Show(Cursor.Position);
            }
        };

        RebuildMenu();
    }

    private void OnManagerChanged()
    {
        if (_uiThread.InvokeRequired)
        {
            _uiThread.BeginInvoke(new Action(RebuildMenu));
        }
        else
        {
            RebuildMenu();
        }
    }

    private void RebuildMenu()
    {
        var menu = _notifyIcon.ContextMenuStrip!;
        menu.Items.Clear();

        if (_manager.Directories.Count == 0)
        {
            menu.Items.Add(new ToolStripMenuItem("No directories added") { Enabled = false });
        }
        else
        {
            foreach (var directory in _manager.Directories.OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase))
            {
                menu.Items.Add(BuildDirectoryMenuItem(directory));
            }
        }

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Add Directory...", null, (_, _) => OnAddDirectory()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => OnQuit()));
    }

    private ToolStripMenuItem BuildDirectoryMenuItem(ManagedDirectory directory)
    {
        var item = new ToolStripMenuItem($"{directory.Name} ({StatusLabel(directory.Status)})");

        switch (directory.Status)
        {
            case DirectoryStatus.Stopped:
            case DirectoryStatus.Error:
                item.DropDownItems.Add(new ToolStripMenuItem("Start", null, (_, _) => _manager.StartDirectory(directory)));
                break;
            case DirectoryStatus.Connecting:
                item.DropDownItems.Add(new ToolStripMenuItem("Stop", null, (_, _) => _manager.StopDirectory(directory)));
                break;
            case DirectoryStatus.Ready:
                item.DropDownItems.Add(new ToolStripMenuItem("Stop", null, (_, _) => _manager.StopDirectory(directory)));
                item.DropDownItems.Add(new ToolStripMenuItem("Copy Join URL", null, (_, _) => CopyJoinUrl(directory)));
                break;
            case DirectoryStatus.RunningUntracked:
                item.DropDownItems.Add(new ToolStripMenuItem("Stop", null, (_, _) => _manager.StopDirectory(directory)));
                item.DropDownItems.Add(new ToolStripMenuItem("Still running from before this app last started — stop it to get a join link again.") { Enabled = false });
                break;
        }

        if (directory.Status == DirectoryStatus.Error && directory.ErrorMessage is { } errorMessage)
        {
            item.DropDownItems.Add(new ToolStripMenuItem(errorMessage) { Enabled = false });
        }

        item.DropDownItems.Add(new ToolStripSeparator());
        item.DropDownItems.Add(new ToolStripMenuItem("Remove", null, (_, _) => _manager.RemoveDirectory(directory)));

        return item;
    }

    private static string StatusLabel(DirectoryStatus status) => status switch
    {
        DirectoryStatus.Stopped => "Stopped",
        DirectoryStatus.Connecting => "Connecting...",
        DirectoryStatus.Ready => "Ready",
        DirectoryStatus.Error => "Error",
        DirectoryStatus.RunningUntracked => "Running",
        _ => status.ToString(),
    };

    private void CopyJoinUrl(ManagedDirectory directory)
    {
        if (directory.JoinUrl is null)
        {
            return;
        }

        Clipboard.SetText(directory.JoinUrl);
    }

    private void OnAddDirectory()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose a directory to manage",
            UseDescriptionForTitle = true,
        };

        if (dialog.ShowDialog() == DialogResult.OK)
        {
            _manager.AddDirectory(dialog.SelectedPath);
        }
    }

    private void OnQuit()
    {
        // Running servers are intentionally left running: quitting the manager (including for a
        // reinstall) should not interrupt a session someone might be connected to. See
        // DirectoryManager.Dispose for what that means on the next launch.
        ExitThread();
    }

    protected override void ExitThreadCore()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _manager.Dispose();
        _uiThread.Dispose();
        base.ExitThreadCore();
    }
}
