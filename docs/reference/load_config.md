# Load a configuration file into memory

Reads a YAML, JSON, or `.env` format file and stores the values in
memory so they can be retrieved with
[`config_get()`](https://laws2020.github.io/orchrd/reference/config_get.md)
anywhere in the session. Call once at the top of a script — then use
[`config_get()`](https://laws2020.github.io/orchrd/reference/config_get.md)
throughout.

## Usage

``` r
load_config(path, env = NULL, override = TRUE, verbose = TRUE)
```

## Arguments

- path:

  Character. Path to the config file.

- env:

  Character. If the file contains multiple environments (e.g.
  `default:`, `production:`), load this one. `NULL` (default) loads the
  top-level keys. Requesting an environment that does not exist is an
  error (no silent fallback to the whole document).

- override:

  Logical. If `TRUE` (default), the new config replaces any config
  already in memory. If `FALSE`, the new config is **deep-merged** under
  the existing one — existing keys (at any depth) win.

- verbose:

  Logical. Print a confirmation message (default `TRUE`).

## Value

Invisibly returns the loaded config as a named list.

## Details

For sensitive values (API keys, passwords) use
[`secret()`](https://laws2020.github.io/orchrd/reference/secret.md)
instead — it validates presence, masks the value, and prevents logging.
`load_config()` is for non-sensitive configuration: paths, URLs, feature
flags, endpoint names, dataset names.

Supported formats:

- **YAML** (`.yml`, `.yaml`) — requires the `yaml` package.

- **JSON** (`.json`) — uses `jsonlite`, already a dependency.

- **env** (`.env`, `config.env`) — `KEY=value`, one per line. Lines
  starting with `#`, inline `# comments`, and an `export ` prefix are
  handled.

## See also

[`config_get()`](https://laws2020.github.io/orchrd/reference/config_get.md),
[`config_all()`](https://laws2020.github.io/orchrd/reference/config_all.md),
[`secret()`](https://laws2020.github.io/orchrd/reference/secret.md) for
credentials.

## Examples

``` r
if (FALSE) { # \dontrun{
load_config("config.yml")
config_get("cache_dir")
config_get("sources", "cbn")
load_config("config.yml", env = "production")
} # }
```
