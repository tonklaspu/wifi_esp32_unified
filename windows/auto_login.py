"""Windows captive-portal auto-login (authorized accounts only).
Install: py -m pip install playwright && py -m playwright install chromium
Run: py auto_login.py
"""
import getpass
import os
import sys
import time
import urllib.request
import urllib.error
from urllib.parse import urlparse

PORTAL_URL = os.getenv('PORTAL_URL', 'http://1.1.1.2/')
# IMPORTANT: Add any VERIFIED redirect hostnames here, comma-separated.
ALLOWED_HOSTS = {h.strip().lower() for h in os.getenv('PORTAL_ALLOWED_HOSTS', '1.1.1.2').split(',') if h.strip()}
CHECK_INTERVAL = 30
RETRY_AFTER_FAILURE = 300
TEST_URL = os.getenv('PORTAL_TEST_URL', 'http://www.msftconnecttest.com/connecttest.txt')
EXPECTED = os.getenv('PORTAL_TEST_EXPECTED', 'Microsoft Connect Test')
# Edit selectors only if your portal uses unusual fields.
USERNAME_SELECTOR = os.getenv('PORTAL_USER_SELECTOR', 'input[name="username"], input[name="user"], input[name="email"], input[type="email"], input[autocomplete="username"], input[type="text"]')
PASSWORD_SELECTOR = os.getenv('PORTAL_PASS_SELECTOR', 'input[type="password"]')
SUBMIT_SELECTOR = os.getenv('PORTAL_SUBMIT_SELECTOR', 'button[type="submit"], input[type="submit"], button:has-text("Login"), button:has-text("Log in"), button:has-text("Sign in"), button:has-text("เข้าสู่ระบบ")')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def online():
    try:
        req = urllib.request.Request(TEST_URL, headers={'User-Agent': 'Mozilla/5.0'}, method='GET')
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=8) as r:
            content = r.read(1000).decode('utf-8', 'replace').strip()
            return r.status == 200 and content == EXPECTED
    except (OSError, urllib.error.URLError):
        return False

def host_allowed(url):
    try:
        parsed = urlparse(url)
        return (parsed.scheme in ('http', 'https') and
                parsed.username is None and parsed.password is None and
                (parsed.hostname or '').lower() in ALLOWED_HOSTS)
    except ValueError:
        return False


def first_visible(frame, selector):
    for field in frame.locator(selector).all():
        if field.is_visible() and field.is_enabled():
            return field
    return None


def form_destinations_allowed(user_field, pass_field, submit):
    # Check native form submission destinations before typing any credentials.
    # The portal's JavaScript must still be trusted; this is not a JS sandbox.
    inspect_form = '''el => {
        const form = el.form;
        if (!form) return null;
        const destinations = [form.action || location.href];
        for (const control of form.elements) {
            if (control.hasAttribute('formaction')) destinations.push(control.formAction);
        }
        return destinations;
    }'''
    for field in (user_field, pass_field, submit):
        if field is not None:
            destinations = field.evaluate(inspect_form)
            if destinations and not all(host_allowed(url) for url in destinations):
                return False
    return True

def do_login(browser, username, password):
    context = browser.new_context(ignore_https_errors=False)
    page = context.new_page()
    try:
        print(f'Opening {PORTAL_URL}')
        page.goto(PORTAL_URL, wait_until='domcontentloaded', timeout=20000)
        page.wait_for_timeout(1200)
        if not host_allowed(page.url):
            print('BLOCKED: Portal redirected to an unapproved host.')
            return False
        frames = list(page.frames)
        target = None
        for frame in frames:
            if not host_allowed(frame.url):
                continue
            try:
                user_field = first_visible(frame, USERNAME_SELECTOR)
                pass_field = first_visible(frame, PASSWORD_SELECTOR)
                if user_field is not None and pass_field is not None:
                    target = frame
                    break
            except Exception:
                continue
        if target is None:
            print('Login form not detected. Portal may use custom fields or a multi-step login.')
            print('Check portal page and update selectors (see README).')
            return False
        # Restrict credentials to explicitly trusted page/frame destinations.
        for address in (page.url, target.url):
            if not host_allowed(address):
                print('BLOCKED: Login form is on an unapproved host.')
                print('Verify the hostname independently before adding it to PORTAL_ALLOWED_HOSTS.')
                return False
        submit = first_visible(target, SUBMIT_SELECTOR)
        if not form_destinations_allowed(user_field, pass_field, submit):
            print('BLOCKED: Form submits to an unapproved destination. Verify portal configuration.')
            return False
        user_field.fill(username, timeout=5000)
        pass_field.fill(password, timeout=5000)
        if submit is not None:
            submit.click(timeout=5000)
        else:
            pass_field.press('Enter', timeout=5000)
        for _ in range(12):
            time.sleep(1)
            if online():
                print('Login succeeded: internet test passed.')
                return True
        print('Internet test did not pass. Check error message on portal or form selectors.')
        return False
    except Exception as exc:
        # Browser exception messages can include form values; do not log them.
        print(f'Portal login not completed ({type(exc).__name__}). Inspect the portal and selectors.')
        return False
    finally:
        context.close()

def main():
    if not host_allowed(PORTAL_URL):
        sys.exit('PORTAL_URL host must appear in PORTAL_ALLOWED_HOSTS')
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit('Install dependencies: python -m pip install -r requirements.txt; python -m playwright install chromium')
    print('Connect Windows to the public Wi-Fi before running this script.')
    username = os.getenv('PORTAL_USERNAME') or input('Portal username: ')
    password = os.getenv('PORTAL_PASSWORD') or getpass.getpass('Portal password (hidden): ')
    if not username or not password:
        sys.exit('Username and password are required.')
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        next_attempt = 0
        was_online = None
        try:
            while True:
                connected = online()
                if connected:
                    if was_online is not True:
                        print('Internet OK. ESP32 can use Windows hotspot if sharing is enabled.')
                    was_online = True
                else:
                    if was_online is not False:
                        print('Internet not available / portal login may be required.')
                    was_online = False
                    if time.monotonic() >= next_attempt:
                        success = do_login(browser, username, password)
                        next_attempt = time.monotonic() + (CHECK_INTERVAL if success else RETRY_AFTER_FAILURE)
                time.sleep(CHECK_INTERVAL)
        except KeyboardInterrupt:
            print('\nStopped.')
        finally:
            browser.close()

if __name__ == '__main__':
    main()
