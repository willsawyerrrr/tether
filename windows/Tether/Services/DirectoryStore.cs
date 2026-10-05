using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Tether.Models;

namespace Tether.Services;

/// <summary>
/// Persists each added directory's path and last-known server process id as JSON under
/// <c>%APPDATA%\Tether\directories.json</c>.
/// </summary>
public sealed class DirectoryStore
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Tether",
        "directories.json");

    /// <summary>
    /// Loads the persisted directory records, or an empty list if none have been saved yet or the
    /// file cannot be read or parsed.
    /// </summary>
    public List<DirectoryRecord> Load()
    {
        try
        {
            if (!File.Exists(FilePath))
            {
                return new List<DirectoryRecord>();
            }

            var json = File.ReadAllText(FilePath);
            return JsonSerializer.Deserialize<List<DirectoryRecord>>(json) ?? new List<DirectoryRecord>();
        }
        catch (Exception)
        {
            return new List<DirectoryRecord>();
        }
    }

    /// <summary>Persists <paramref name="records"/>, creating the containing directory if needed.</summary>
    public void Save(IEnumerable<DirectoryRecord> records)
    {
        var directory = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var json = JsonSerializer.Serialize(records.ToList(), new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(FilePath, json);
    }
}
