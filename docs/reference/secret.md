# Retrieve a secret environment variable safely

Reads a secret from environment variables with three guarantees that
plain [`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html) does not
provide:

## Usage

``` r
secret(name, desc = NULL, default = NULL)
```

## Arguments

- name:

  Character(1). The environment variable name.

- desc:

  Character(1) or NULL. Human-readable description of what this secret
  is used for. Shown in the error message if the variable is missing.

- default:

  Character(1) or NULL. A default value used if the variable is not set.
  Setting a default suppresses the missing-variable error. Use with
  caution - in production, secrets should always be explicit.

## Value

An S3 object of class `orchrd_secret`.

## Details

1.  Presence validation - errors immediately if the variable is not set,
    with a clear message explaining what it is needed for.

2.  Log safety - the value is held in a locked environment and never
    surfaces through
    [`as.character()`](https://rdrr.io/r/base/character.html),
    [`format()`](https://rdrr.io/r/base/format.html),
    [`print()`](https://rdrr.io/r/base/print.html),
    [`str()`](https://rdrr.io/r/utils/str.html),
    [`unclass()`](https://rdrr.io/r/base/class.html), or
    [`dput()`](https://rdrr.io/r/base/dput.html). It is therefore never
    captured by
    [`log_step()`](https://laws2020.github.io/orchrd/reference/log_step.md)
    or
    [`with_log()`](https://laws2020.github.io/orchrd/reference/with_log.md),
    even at debug level.

3.  Masked printing - the `orchrd_secret` object prints as
    `<secret: VAR_NAME>`.

To obtain the underlying value you must call
[`reveal()`](https://laws2020.github.io/orchrd/reference/reveal.md)
explicitly. This is intentional: it makes every point where a secret is
exposed grep-able in code review.

## See also

[`reveal()`](https://laws2020.github.io/orchrd/reference/reveal.md) to
extract the raw value,
[`need()`](https://laws2020.github.io/orchrd/reference/need.md) to
validate multiple secrets at once before a pipeline starts.

## Examples

``` r
if (FALSE) { # \dontrun{
key <- secret("AZURE_KEY")
key
# <secret: AZURE_KEY>

raw <- reveal(secret("AZURE_KEY"))
key <- secret("AZURE_KEY", default = "dev-placeholder")
} # }
```
