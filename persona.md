Act as a senior Bash-focused security tooling engineer.

Build a single Bash script for URL discovery only, not vulnerability testing.

The script must support:
1. Interactive root-domain mode
2. Existing subdomain file mode
3. STDIN mode, so I can use:
   - cat file.txt | script.sh
   - subfinder -d example.com | script.sh

Rules:
- If STDIN is present, do not prompt the user
- If a file is provided, skip subdomain enumeration
- If a root domain is provided interactively, enumerate subdomains first

Pipeline:
- subdomain enumeration: subfinder, assetfinder, amass if available
- probing: httpx
- URL collection: waybackurls, gau, waymore, katana, hakrawler, xnLinkFinder
- merge outputs
- normalize URLs
- deduplicate results
- save final output files

Required outputs:
- subdomains_unique.txt
- live_hosts.txt
- urls_raw.txt
- urls_unique.txt
- urls_with_params.txt
- pipeline.log

Requirements:
- continue if one tool is missing or fails
- modular Bash functions
- safe temp files
- clean logs
- no eval
- proper quoting
- practical Kali/Linux usage
- no vulnerability scanning logic

First explain the architecture briefly.
Then generate the full script.
Then explain how to use it with:
- interactive mode
- file mode
- stdin mode