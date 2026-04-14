# URL Discovery Pipeline

Single Bash script for URL discovery only. This workflow collects subdomains, probes live hosts, gathers historical and crawled URLs, normalizes them, deduplicates them, and saves the final output files.

It does not perform vulnerability scanning.

## Script

Run:

```bash
chmod +x ./install_tools.sh
chmod +x ./url_discovery.sh
```

## Tool Installation

Use the installer before running the URL discovery pipeline.

```bash
./install_tools.sh
```

The installer checks whether the required tools are present and attempts to install missing ones automatically.

The main pipeline script also performs an automatic dependency check at startup and warns when required tooling is missing for the selected mode.

- Target platform: Kali/Debian-style Linux
- Uses `apt` for base dependencies and `amass`
- Uses `go install` for the Go-based tools
- Uses `pipx` with a `pip` fallback for the Python-based tools
- Writes execution details to `install_tools.log`

Check only, without installing:

```bash
./install_tools.sh --check-only
```

If a fresh shell does not find the installed commands, export:

```bash
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"
```

## Modes

### 1. Interactive root-domain mode

If you run the script without `STDIN` and without `-f`, it prompts for a root domain and enumerates subdomains first.

```bash
./url_discovery.sh
```

You can also skip the prompt:

```bash
./url_discovery.sh -d example.com
```

### 2. Existing subdomain file mode

If you provide `-f`, the script skips subdomain enumeration and uses the file as the input target list.

```bash
./url_discovery.sh -f subdomains.txt
./url_discovery.sh -f subdomains.txt -o output_dir
```

### 3. STDIN mode

If `STDIN` is present, the script does not prompt the user.

```bash
cat subdomains.txt | ./url_discovery.sh
subfinder -d example.com | ./url_discovery.sh
```

If both `STDIN` and `-f` are provided, file mode wins and `STDIN` is ignored.

## Pipeline

Subdomain enumeration:
- `subfinder`
- `assetfinder`
- `amass`

Probing:
- `httpx`

URL collection:
- `waybackurls`
- `gau`
- `waymore`
- `katana`
- `hakrawler`
- `xnLinkFinder`

Installation coverage:
- `subfinder`
- `assetfinder`
- `amass`
- `httpx`
- `waybackurls`
- `gau`
- `waymore`
- `katana`
- `hakrawler`
- `xnLinkFinder`

## Output Files

By default, the script writes results to:

```bash
./url_discovery_<timestamp>/
```

Files created:

- `subdomains_unique.txt`
- `live_hosts.txt`
- `urls_raw.txt`
- `urls_unique.txt`
- `urls_with_params.txt`
- `pipeline.log`

## Behavior Notes

- Missing tools are logged and skipped.
- `url_discovery.sh` warns at startup about missing dependencies and suggests `install_tools.sh` when it is available.
- Tool failures do not stop the full pipeline.
- Temporary files are created safely and cleaned up on exit.
- URLs are normalized before deduplication.
- `urls_with_params.txt` contains only URLs with `?` query parameters.
- The script is intended for practical Kali/Linux usage.

## Options

```bash
./url_discovery.sh [-f subdomains.txt] [-o output_dir] [-d root-domain]
```

- `-f, --file` use an existing file as input
- `-o, --output` set the output directory
- `-d, --domain` provide the root domain without prompting
- `-h, --help` show help text

## Example Runs

Install tools first:

```bash
./install_tools.sh
```

Interactive:

```bash
./url_discovery.sh
```

File mode:

```bash
./url_discovery.sh -f targets.txt
```

STDIN mode:

```bash
cat targets.txt | ./url_discovery.sh
```