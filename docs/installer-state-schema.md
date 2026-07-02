# installer state.json Schema

The `state.json` file tracks the progress of a Lara Diaries installation. It lives in the platform-specific state directory:

| OS      | Path |
|---------|------|
| Windows | `%LOCALAPPDATA%\LaraDiaries\state.json` |
| Linux   | `$HOME/.config/lara-diaries/state.json` |
| macOS   | `$HOME/.config/lara-diaries/state.json` |

## Schema

```json
{
  "version": 1,
  "install_id": "a1b2c3d4-e5f6-4789-abcd-ef0123456789",
  "created_at": "2026-07-01T12:00:00Z",
  "updated_at": "2026-07-01T12:05:00Z",
  "install_type": "fresh",
  "steps": {
    "github_login": {
      "status": "success",
      "started_at": "2026-07-01T12:00:00Z",
      "completed_at": "2026-07-01T12:01:00Z",
      "error": null,
      "rollback": null
    }
  }
}
```

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | int | Schema version (currently 1). Incremented on breaking changes. |
| `install_id` | string | UUID v4 identifying this installation run. |
| `created_at` | string (RFC 3339) | When the state file was created. |
| `updated_at` | string (RFC 3339) | When the state file was last modified. |
| `install_type` | string | `"fresh"`, `"upgrade"`, or custom label. |
| `steps` | object | Map of step names to step objects. |

## Step Object

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | One of: `"pending"`, `"running"`, `"success"`, `"failed"`, `"skipped"`. |
| `started_at` | string or null | RFC 3339 timestamp when the step started running. |
| `completed_at` | string or null | RFC 3339 timestamp when the step reached a terminal status. |
| `error` | string or null | Error message for failed steps. |
| `rollback` | string or null | Description of the rollback action taken or available. |

## Status Lifecycle

```
pending --> running --> success
                  +--> failed
                  +--> skipped
```

- A step starts as `pending` when first referenced.
- `running` is set when execution begins.
- Terminal states: `success`, `failed`, `skipped`.

## Forward Compatibility

The schema is designed for forward compatibility:

- **Unknown fields at the top level** are preserved across read/write cycles using a raw-byte merge technique. A future version adding `"new_field": "value"` will see it preserved when an older version reads and writes the state.
- **Unknown fields within a step object** are preserved through the same mechanism at the step level.
- The `raw` field (internal, not serialized) holds the original JSON bytes so the merge preserves fields the current version does not understand.

This means upgrading the installer will not lose data written by a newer version, as long as the version number is not incremented beyond what the older version can parse.

## Lock File

A companion file `install.lock` lives alongside `state.json`. It contains:

```
<PID>
<timestamp (RFC 3339)>
<hostname>
```

The lock prevents concurrent installations and detects stale installations.
