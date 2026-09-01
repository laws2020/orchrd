# Diagnose Docker Infrastructure

Runs a comprehensive diagnostic assessment of the Docker infrastructure
associated with a project (R, JavaScript/web, or mixed). The report
examines the local environment, Docker installation and Engine
availability, containers, networking, system resources, and common
project security risks.

## Usage

``` r
diagnose(
  portal_container = NULL,
  api_container = NULL,
  db_container = NULL,
  project_path = getwd(),
  timeout = 15
)
```

## Arguments

- portal_container:

  Optional name of the container running the web portal.

- api_container:

  Optional name of the container running the API.

- db_container:

  Optional name of the container running the database.

- project_path:

  Path to the project being diagnosed. Defaults to the current working
  directory.

- timeout:

  Numeric. Seconds before any single Docker call is abandoned (guards
  against an unresponsive daemon). Default `15`.

## Value

An object of class `dockrinfra_diagnosis` (also printed).

## Details

Container names are optional. When omitted, `diagnose()` discovers the
containers currently visible to Docker.

## Examples

``` r
if (FALSE) { # \dontrun{
diagnose()
diagnose(portal_container = "my-portal", api_container = "my-api")
diagnose(project_path = "C:/projects/my-project")
} # }
```
