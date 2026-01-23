#!/usr/bin/env python3
"""
Resolve Superhuman download URLs from their update channel.

Superhuman publishes their latest version information at a public URL,
so we can fetch version and download URLs directly without browser automation.

Falls back to Playwright-based resolution if the update channel is unavailable.
"""

import argparse
import re
import sys
import urllib.parse

import requests
import yaml

try:
    from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False


# Superhuman update channel base URL
UPDATE_CHANNEL_BASE = "https://storage.googleapis.com/download.superhuman.com/native-update"

# Fallback: Download page and selector for Playwright-based resolution
DOWNLOAD_PAGE_URL = "https://superhuman.com/download"
DOWNLOAD_SELECTOR = r"#\31 d0sej8 > div > section:nth-child(2) > button > a"

# User agent to appear as a regular browser
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"


def fetch_latest_yml(timeout: int = 10) -> dict | None:
    """
    Fetch and parse the latest.yml from Superhuman's update channel.

    Returns:
        Parsed YAML content as a dict, or None if fetch failed.
    """
    url = f"{UPDATE_CHANNEL_BASE}/latest.yml"
    try:
        response = requests.get(url, timeout=timeout)
        response.raise_for_status()
        return yaml.safe_load(response.text)
    except (requests.RequestException, yaml.YAMLError) as e:
        print(f"Error fetching latest.yml: {e}", file=sys.stderr)
        return None


def resolve_from_update_channel(arch: str) -> dict | None:
    """
    Resolve download URL and version from Superhuman's update channel.

    Args:
        arch: Architecture to resolve ('amd64' or 'arm64')

    Returns:
        Dict with 'url' and 'version' keys, or None if resolution failed.
    """
    latest = fetch_latest_yml()
    if not latest:
        return None

    version = latest.get("version")
    if not version:
        print("Error: No version found in latest.yml", file=sys.stderr)
        return None

    # Construct download URL based on architecture
    # AMD64: "Superhuman Setup X.X.X-latest.exe"
    # ARM64: "Superhuman Setup X.X.X-latest-arm64.exe"
    if arch == "amd64":
        filename = f"Superhuman Setup {version}-latest.exe"
    else:
        filename = f"Superhuman Setup {version}-latest-arm64.exe"

    # URL-encode the filename (spaces -> %20)
    encoded_filename = urllib.parse.quote(filename)
    url = f"{UPDATE_CHANNEL_BASE}/{encoded_filename}"

    return {"url": url, "version": version}


def resolve_via_playwright(timeout: int = 30000) -> str | None:
    """
    Resolve download URL via Playwright by navigating to the download page.

    This is a fallback method if the update channel is unavailable.

    Returns:
        The resolved download URL, or None if resolution failed.
    """
    if not PLAYWRIGHT_AVAILABLE:
        print("Playwright not available for fallback resolution", file=sys.stderr)
        return None

    resolved_url = None

    def handle_request(request):
        nonlocal resolved_url
        url = request.url
        # Look for the Google Cloud Storage URL
        if "storage.googleapis.com" in url and url.endswith(".exe"):
            resolved_url = url

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            user_agent=USER_AGENT,
            viewport={"width": 1920, "height": 1080},
            accept_downloads=True,
        )

        # Apply stealth settings
        context.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
            Object.defineProperty(navigator, 'platform', { get: () => 'Linux x86_64' });
            Object.defineProperty(navigator, 'vendor', { get: () => 'Google Inc.' });
        """)

        page = context.new_page()
        page.on("request", handle_request)

        try:
            # Navigate to the download page
            page.goto(DOWNLOAD_PAGE_URL, timeout=timeout, wait_until="domcontentloaded")

            # Try to find and click the download button using the provided selector
            try:
                download_link = page.locator(DOWNLOAD_SELECTOR)
                if download_link.count() > 0:
                    href = download_link.get_attribute("href")
                    if href:
                        resolved_url = href
            except Exception as e:
                print(f"Error finding download link: {e}", file=sys.stderr)

            # Give it a moment to capture any redirects
            page.wait_for_timeout(2000)

        except PlaywrightTimeout:
            print("Timeout navigating to download page", file=sys.stderr)
        except Exception as e:
            print(f"Error navigating to download page: {e}", file=sys.stderr)
        finally:
            browser.close()

    return resolved_url


def extract_version_from_url(url: str) -> str | None:
    """
    Extract version number from a download URL.

    Superhuman URLs typically contain version like "Superhuman Setup 1038.0.17-latest.exe"
    """
    # Try pattern like "Setup X.X.X-latest"
    match = re.search(r"Setup[%20\s]+(\d+\.\d+\.\d+)", url)
    if match:
        return match.group(1)

    # Try pattern with version in path
    match = re.search(r"/(\d+\.\d+\.\d+)/", url)
    if match:
        return match.group(1)

    return None


def verify_url_exists(url: str, timeout: int = 10) -> bool:
    """
    Verify that a URL exists by making a HEAD request.

    Returns True if the URL returns a 200 status code.
    """
    try:
        response = requests.head(url, timeout=timeout, allow_redirects=True)
        return response.status_code == 200
    except requests.RequestException:
        return False


def derive_arm64_url_from_amd64(amd64_url: str) -> str | None:
    """
    Derive the ARM64 download URL from an AMD64 URL by pattern substitution.
    """
    if not amd64_url:
        return None

    # Superhuman pattern: "-latest.exe" -> "-latest-arm64.exe"
    if "-latest.exe" in amd64_url:
        return amd64_url.replace("-latest.exe", "-latest-arm64.exe")

    return None


def main():
    parser = argparse.ArgumentParser(
        description="Resolve Superhuman download URLs"
    )
    parser.add_argument(
        "arch",
        choices=["amd64", "arm64", "all"],
        help="Architecture to resolve (amd64, arm64, or all)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30000,
        help="Timeout in milliseconds for Playwright fallback (default: 30000)",
    )
    parser.add_argument(
        "--format",
        choices=["url", "version", "both"],
        default="url",
        help="Output format (default: url)",
    )
    parser.add_argument(
        "--use-playwright",
        action="store_true",
        help="Force use of Playwright instead of update channel",
    )

    args = parser.parse_args()

    architectures = ["amd64", "arm64"] if args.arch == "all" else [args.arch]

    results = {}

    if args.use_playwright:
        # Force Playwright-based resolution
        print("Using Playwright to resolve download URL...", file=sys.stderr)
        url = resolve_via_playwright(args.timeout)
        if url:
            version = extract_version_from_url(url)
            results["amd64"] = {"url": url, "version": version}
            print(f"  Resolved: {url}", file=sys.stderr)
            if version:
                print(f"  Version: {version}", file=sys.stderr)
        else:
            print("  Failed to resolve URL via Playwright", file=sys.stderr)
            results["amd64"] = None

        # Derive ARM64 if needed
        if "arm64" in architectures and results.get("amd64"):
            derived_url = derive_arm64_url_from_amd64(results["amd64"]["url"])
            if derived_url and verify_url_exists(derived_url):
                version = extract_version_from_url(derived_url)
                results["arm64"] = {"url": derived_url, "version": version}
            else:
                results["arm64"] = None
    else:
        # Use update channel (preferred method)
        for arch in architectures:
            print(f"Resolving {arch} download URL from update channel...", file=sys.stderr)
            result = resolve_from_update_channel(arch)

            if result:
                print(f"  URL: {result['url']}", file=sys.stderr)
                print(f"  Version: {result['version']}", file=sys.stderr)

                # Verify the URL exists
                print("  Verifying URL exists...", file=sys.stderr)
                if verify_url_exists(result["url"]):
                    results[arch] = result
                    print("  ✓ URL verified", file=sys.stderr)
                else:
                    print("  ✗ URL does not exist (404)", file=sys.stderr)
                    results[arch] = None
            else:
                print(f"  Failed to resolve {arch} URL from update channel", file=sys.stderr)
                results[arch] = None

    # Output results based on format
    for arch, result in results.items():
        if result is None:
            continue

        prefix = f"{arch.upper()}_" if len(architectures) > 1 else ""

        if args.format == "url":
            print(f"{prefix}URL={result['url']}")
        elif args.format == "version":
            if result["version"]:
                print(f"{prefix}VERSION={result['version']}")
        elif args.format == "both":
            print(f"{prefix}URL={result['url']}")
            if result["version"]:
                print(f"{prefix}VERSION={result['version']}")

    # Exit with error if any resolution failed
    if any(r is None for r in results.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
