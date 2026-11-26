using Tether.Services;

namespace Tether.Tests;

public class RemoteControlSessionTests
{
    [Fact]
    public async Task Start_ReportsTheServersOwnErrorWhenItExitsImmediately()
    {
        var directory = Directory.CreateTempSubdirectory();
        // cmd.exe resolves `claude` in the working directory ahead of the PATH.
        File.WriteAllText(
            Path.Combine(directory.FullName, "claude.cmd"), "@>&2 echo Stand-in failure\r\n@exit /b 1\r\n");
        string? failure = null;
        var exited = new TaskCompletionSource();

        using (var session = new RemoteControlSession(directory.FullName, "stand-in"))
        {
            session.Failed += message => failure = message;
            session.Exited += () => exited.TrySetResult();
            session.Start();
            await exited.Task.WaitAsync(TimeSpan.FromSeconds(30));
        }

        Assert.Equal("Stand-in failure", failure);
        directory.Delete(recursive: true);
    }
}
