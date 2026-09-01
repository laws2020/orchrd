# Reveal the raw value of a secret

Extracts the underlying character value from an `orchrd_secret` object.
This is the only supported way to obtain the raw string, and it is
deliberately explicit so that every exposure point is visible in review.

## Usage

``` r
reveal(x)
```

## Arguments

- x:

  An `orchrd_secret` object from
  [`secret()`](https://laws2020.github.io/orchrd/reference/secret.md).

## Value

A plain character string containing the secret value.

## See also

[`secret()`](https://laws2020.github.io/orchrd/reference/secret.md)

## Examples

``` r
if (FALSE) { # \dontrun{
key <- secret("AZURE_KEY")
raw <- reveal(key)
} # }
```
