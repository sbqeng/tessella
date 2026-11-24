# Mosaic Market: the demo shop

A small tile shop with the features of a classic practice store (test personas, sorting,
a cart, a three-step checkout), a smoother interface and a full Playwright suite (API and
UI) built on page objects. It is Tessella's test target and demo: run the suite, point
Tessella at the reports, and see what it makes of the failures.

- **Backend:** Starlette (the toolkit FastAPI is built on) on uvicorn, with in-memory data.
- **Frontend:** one HTML page, no build step: sign-in, patterns (sort, search), product page,
  cart (quantities, undo), checkout (details, overview with discount, thank-you), my orders,
  a side menu (all patterns, my orders, about, reset app state, log out). Cart, sign-in and
  sort order survive a reload; dark mode, phone layout and keyboard navigation work.
- **Tests:** everything on Playwright: API tests on its request context, UI tests with
  pytest-playwright, an Allure report with a screenshot per UI test, a Playwright trace per
  UI test. See [The test suite](#the-test-suite).
- **Logs:** every API request goes to `logs/app.log`, with the full traceback when a request
  crashes. Tessella reads this file as backend evidence.

## Test accounts and personas

`anna` / `anna-pass` and `bob` / `bob-pass` are the suite's customers; their shop behaves
normally. Six personas share the password `mosaic-pass`, each with a quirk that appears only
when you sign in as it:

| Persona | What it does |
|---|---|
| `standard` | Everything works |
| `locked` | Cannot sign in: "Sorry, this user has been locked out" |
| `problem` | One image on every pattern, sorting does nothing, some Add buttons do nothing, the last name will not type |
| `slow` | Signing in takes 2.5 s |
| `error` | Removing from the cart and placing an order fail with an error |
| `visual` | A tile is rotated, a button and the cart badge are out of place, one price is wrong |

## The test suite

Everything runs on Playwright: API tests use its request context, UI tests use
pytest-playwright. Tests never touch URLs or selectors directly; they go through a small
framework in `tests/framework/`, each part with one job:

| Part | Job |
|---|---|
| `data.py` | Accounts, products, delivery details, prices: test data by meaning |
| `api/session.py` | `ApiSession`: the transport (base URL, token), nothing else |
| `api/clients.py` | `AuthApi`, `CatalogueApi`, `OrdersApi`: one client per API area, returning responses, never asserting; `OrderSteps` builds orders in a given state |
| `pages/components.py` | `Header`, `SideMenu`, `Toast`: parts every screen shares |
| `pages/screens.py` | One page object per screen (`LoginPage`, `InventoryPage`, `CartPage`, `CheckoutInfoPage`, …); actions that change screen return the next page object |
| `flows.py` | `Shopper`: journeys across screens (sign in, fill the cart, buy) |
| `conftest.py` | Fixtures that hand these to tests (dependency injection) |

Adding a screen means a new page object and fixture, not edits to existing tests. A run
(`pytest`) covers auth, catalogue and orders over the API and every screen in the browser:
95 tests.

## Run it yourself, step by step

The commands assume the repository is at `~/Documents/Projects/tessella` and its virtual
environment is `venv/` in the repository root, as set up in the main README's Getting
started. Adjust the paths if yours differ. You need two terminals: one runs the shop, the
other runs everything else.

### Step 1: Install (once)

```bash
cd ~/Documents/Projects/tessella
source venv/bin/activate
pip install -e ".[all,dev]"            # Tessella itself, if you have not done it yet

cd examples/demo_shop
pip install -r requirements.txt        # starlette, uvicorn, pytest, allure-pytest, pytest-playwright
playwright install chromium            # the browser the UI tests drive (about 150 MB)
```

Then give the demo its settings (your own `tessella.yaml` is never committed):

```bash
cp tessella.example.yaml tessella.yaml
```

Check it worked:

```bash
python -c "import starlette, uvicorn, allure, pytest_playwright; print('ok')"
```

You'll also need the [Allure commandline](https://allurereport.org/docs/install/) (`allure
generate`/`allure open`) — `run_suite.sh` calls it directly, so it must be on your `PATH`.

On a fresh Linux machine Chromium may refuse to start because system libraries are
missing. `playwright install-deps chromium` installs them (it asks for sudo).

### Step 2: Start the shop (terminal 1)

```bash
cd ~/Documents/Projects/tessella/examples/demo_shop
source ../../venv/bin/activate
uvicorn shop.app:app --port 8765
```

Leave it running. Data lives in memory, so stopping the shop (Ctrl+C) empties it. Every
API request is logged to `logs/app.log`.

### Step 3: Try the shop in the browser

Open <http://127.0.0.1:8765>, sign in as `anna` / `anna-pass` (or pick `anna` under **Test
accounts**), and shop: sort and search the patterns, fill the cart, check out with the
discount code `TILE25` or `MOSAIC10`, then pay or cancel the order under **My orders**.
Every request lands in `logs/app.log`:

```bash
cd ~/Documents/Projects/tessella/examples/demo_shop
tail -n 25 logs/app.log
```

### Step 4: Run the test suite (terminal 2)

```bash
bash run_suite.sh
```

The tests use the shop from step 2 if it is running, and start their own on port 8765 if
it is not. They empty the shop before each test, so the orders you made in the browser
disappear. A run is 95 tests and takes about three minutes.

`run_suite.sh` writes:

| Path | What it is |
|------|------------|
| `reports/allure-results/` | Raw Allure results, one JSON per test (with a screenshot attachment per UI test) |
| `reports/allure-report/` | The generated Allure report (`allure generate`), with history carried across runs for flaky-rate/trend charts |
| `reports/junit.xml` | JUnit XML, for CI |
| `test-results/` | A Playwright trace per UI test (the flows Tessella probes), plus the screenshots as PNG files |
| `logs/app.log` | The shop's request log, with the traceback of any request that crashed |

Look at the results. You have two options:

```bash
# Option A: the raw Allure report (everything, with filters: use the pass/fail
# icons at the top to show only failed/broken tests first)
allure open reports/allure-report

# Option B (recommended): skip straight to Tessella's queue once you've triaged
# (see Step 5 below) — it only ever shows failures, nothing to filter
tessella triage && tessella queue
```

Allure's report is a general-purpose test report, built for CI history/trends across many
runs. Tessella's queue is your failure triage inbox — every case shown there already is a
failure, so there's no "show failures first" step needed. Prefer Option B day to day;
reach for Option A when you want the trend/history view across many runs.

In the Allure report, every UI test carries its screenshot. Some useful variations:

```bash
pytest tests/ui/test_sign_in.py::test_login -q             # one test
pytest tests/ui -k cancel --headed --slowmo 500             # watch the browser
pytest tests/api -q                                         # API tests only
```

### Step 5: Run Tessella on the results (terminal 2)

Run Tessella from this folder so it picks up this folder's `tessella.yaml`. That file reads
`reports/allure-report` (not `junit.xml`, which holds the same failures and would make
duplicate Cases), the Playwright traces and `logs/app.log`; re-runs each failure three
times into `.tessella/rerun-results` (so the traces in `test-results/` survive); and allows
network access only to the shop and a local Ollama.

Start without a model, to see collecting and clustering on their own:

```bash
tessella triage --no-model --no-rerun
```

Expect a table of this run's failures, grouped into clusters by signature (normalised
message plus failing line). Failures with the same cause can still land in separate
clusters at this stage when they fail with different messages in different files;
recognising them as one problem is the investigation's job. The *Screens* column shows the
screenshot each UI failure carries.

Add re-runs, which tell flaky tests from steady failures (about a minute):

```bash
tessella triage --no-model
```

Then with a local model for verdicts, if you have Ollama:

```bash
ollama pull qwen3.5:4b                 # reads logs and screenshots; ~3 GB, fine on a CPU laptop
tessella doctor                        # model roles, data policy, network rules
tessella triage
tessella queue                         # review at http://localhost:8484
```

On a CPU-only laptop expect about a minute per model step. The config turns off the
model's thinking phase and caps each group of failures at 4 steps; the main README's
"Choosing models" section has bigger options.

In the queue, approve, edit, reject or delete each draft. Nothing is filed anywhere until
you approve it.

Finally, the probe planner:

```bash
export A_PASS=anna-pass B_PASS=bob-pass
tessella probe
```

It reads the traces, links the order ID across steps and prints the mutations it plans
for each flow. Replaying them against the shop is v2.

### Step 6: Start over

```bash
rm -rf reports test-results logs       # results of the last run
rm -rf .tessella                       # Tessella's memory of past decisions, re-run output
```

Restarting the shop empties its data. The shop and tests never write outside this folder.

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| `address already in use` on port 8765 | A shop is already running. Use it, or stop it: `fuser -k 8765/tcp` |
| Results look stale or odd | The tests reuse whatever shop is on port 8765; restart it from this folder |
| You need another port | `uvicorn shop.app:app --port 9000`, then `DEMO_SHOP_URL=http://127.0.0.1:9000 bash run_suite.sh`; change `probe.base_url` and `network.allow` in `tessella.yaml` too |
| `Executable doesn't exist` from Playwright | `playwright install chromium` inside the activated venv |
| `ModuleNotFoundError: No module named 'shop'` | Run pytest from `examples/demo_shop`; its `pytest.ini` adds the folder to the path |
| `tessella: command not found` | Activate the venv: `source ../../venv/bin/activate` |
| The shop's font looks plain | It loads Bricolage Grotesque from Google Fonts and falls back to a system font offline. Tests do not depend on it |

## What Tessella does with it today (v0.1)

- **Triage** reads `reports/allure-report` with its screenshots, clusters failures by
  signature (normalised message plus failing line), re-runs each failure three times (which
  tells flaky tests apart), and asks the reader model for a verdict that may cite only
  collected evidence.
- **Probe** reads the Playwright traces, links IDs across steps (the order ID from
  `POST /api/orders` into `/pay` and `/cancel`) and lists the mutations it would try, such
  as an identity swap or a parallel pay. Replaying them against the live shop is v2.
- `logs/app.log` is already written in a form Tessella's file log adapter reads; wiring
  log evidence into the triage pipeline is on the v1 list.

## Layout

```
demo_shop/
├── shop/
│   ├── app.py          routes, request log
│   ├── store.py        orders, payments, refunds
│   └── static/index.html
├── tests/
│   ├── conftest.py     starts the shop if needed, resets it per test, fixtures, screenshots
│   ├── framework/      data, API clients, page objects, the Shopper flow
│   ├── api/            auth, catalogue, orders
│   └── ui/             sign-in, patterns, cart, checkout, orders, menu
├── pytest.ini
├── requirements.txt
├── run_suite.sh       runs the suite, writes reports/
└── tessella.yaml
```

The accounts (`anna` / `anna-pass`, `bob` / `bob-pass`, the personas with `mosaic-pass`)
and the `/api/test/reset` endpoint exist only for this demo.
