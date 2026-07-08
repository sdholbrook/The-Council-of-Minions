const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

function argValue(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 >= process.argv.length) {
    return fallback;
  }
  return process.argv[index + 1];
}

function nowStamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function sanitizeName(value) {
  return String(value).replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), "utf8");
}

function appendLine(lines, value = "") {
  lines.push(value);
}

async function visibleBodyText(page) {
  return page.evaluate(() => document.body?.innerText || "");
}

async function screenshot(page, artifactDir, name) {
  const filePath = path.join(artifactDir, `${sanitizeName(name)}.png`);
  await page.screenshot({ path: filePath, fullPage: true });
  return filePath;
}

async function collectDiagnostics(page) {
  return {
    url: page.url(),
    title: await page.title().catch(() => ""),
    bodyTextSample: (await visibleBodyText(page).catch(() => "")).slice(0, 4000),
  };
}

function findAppError(text) {
  const patterns = [
    /sorry[, ]+something went wrong/i,
    /something went wrong/i,
    /an error has occurred/i,
    /error code[: ]/i,
    /invalid app/i,
    /app module/i,
    /could not find/i,
    /does not exist/i,
    /you do not have permission/i,
    /you don't have permission/i,
    /permissions for these records/i,
    /permissions to these records/i,
    /something may be wrong with the site map/i,
    /access denied/i,
    /errorhandler\.aspx/i,
    /ErrorCode=0x/i,
    /cannot read properties/i,
    /script error/i,
    /failed to load/i,
    /try again later/i,
  ];

  return patterns.find((pattern) => pattern.test(text));
}

async function assertNoVisibleAppError(page, contextLabel) {
  const text = await visibleBodyText(page);
  const match = findAppError(text);
  if (match) {
    throw new Error(`${contextLabel}: visible app error matched ${match}`);
  }
}

function checkMarkers(text, screen) {
  const expectedAll = screen.mustContainAll || [];
  const missingAll = expectedAll.filter((value) => !text.includes(value));
  const expectedAny = screen.mustContainAny || [];
  const matchedAny = expectedAny.length === 0 || expectedAny.some((value) => text.includes(value));
  return { expectedAll, missingAll, expectedAny, matchedAny };
}

async function waitForScreenMarkers(page, screen, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  let lastCheck = null;

  while (Date.now() < deadline) {
    await assertNoVisibleAppError(page, screen.name);
    const text = await visibleBodyText(page);
    lastCheck = checkMarkers(text, screen);
    if (lastCheck.missingAll.length === 0 && lastCheck.matchedAny) {
      return { text, markerCheck: lastCheck };
    }
    await page.waitForTimeout(1000);
  }

  if (lastCheck?.missingAll?.length > 0) {
    throw new Error(`${screen.name}: expected visible markers were not found within ${timeoutMs}ms: ${lastCheck.missingAll.join(", ")}`);
  }
  throw new Error(`${screen.name}: none of the expected visible markers were found within ${timeoutMs}ms: ${(lastCheck?.expectedAny || []).join(", ")}`);
}

async function waitForAppShell(page, config, interactive) {
  await page.waitForLoadState("domcontentloaded", { timeout: 60000 }).catch(() => {});
  const loginUrlPattern = /login\.microsoftonline\.com|login\.live\.com|microsoftonline\.com/i;
  const loginTextPattern = /sign in|pick an account|enter password/i;

  for (let attempt = 0; attempt < 12; attempt += 1) {
    const currentUrl = page.url();
    const text = await visibleBodyText(page).catch(() => "");
    const loginVisible = loginUrlPattern.test(currentUrl) || loginTextPattern.test(text);
    if (!loginVisible) {
      break;
    }

    if (!interactive) {
      throw new Error("SCREEN_TEST_AUTH_REQUIRED: browser is not authenticated for the model-driven app.");
    }

    await page.waitForTimeout(5000);
  }

  if (interactive) {
    await page.waitForURL((url) => url.href.startsWith(config.environmentUrl), { timeout: 600000 }).catch(() => {});
  }

  await assertNoVisibleAppError(page, "app-shell");
}

async function run() {
  const configPath = argValue("--config");
  if (!configPath) {
    throw new Error("Missing --config <path>.");
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf8").replace(/^\uFEFF/, ""));
  const runId = nowStamp();
  const artifactDir = path.resolve(config.artifactRoot || "_bmad-output/test-artifacts/model-driven-screen/runs", runId);
  fs.mkdirSync(artifactDir, { recursive: true });

  const interactive = process.env.COUNCIL_SCREEN_INTERACTIVE === "1";
  const headed = interactive || process.env.COUNCIL_SCREEN_HEADED === "1";
  const userDataDir = process.env.COUNCIL_SCREEN_USER_DATA_DIR;
  const browserChannel = process.env.COUNCIL_SCREEN_CHANNEL || undefined;

  const consoleEntries = [];
  const pageErrors = [];
  const networkEntries = [];
  const screenshots = [];
  const checks = [];
  let browser;
  let context;
  let page;
  let status = "failed";
  let failure = null;

  try {
    if (userDataDir) {
      fs.mkdirSync(userDataDir, { recursive: true });
      context = await chromium.launchPersistentContext(userDataDir, {
        headless: !headed,
        channel: browserChannel,
        viewport: { width: 1440, height: 1000 },
        recordVideo: { dir: artifactDir },
      });
      page = context.pages()[0] || await context.newPage();
    } else {
      browser = await chromium.launch({ headless: !headed, channel: browserChannel });
      context = await browser.newContext({
        viewport: { width: 1440, height: 1000 },
        recordVideo: { dir: artifactDir },
      });
      page = await context.newPage();
    }

    page.on("console", (message) => {
      consoleEntries.push({ type: message.type(), text: message.text(), location: message.location() });
    });
    page.on("pageerror", (error) => {
      pageErrors.push({ name: error.name, message: error.message, stack: error.stack });
    });
    page.on("response", (response) => {
      const statusCode = response.status();
      if (statusCode >= 400) {
        networkEntries.push({ status: statusCode, url: response.url(), method: response.request().method() });
      }
    });

    await context.tracing.start({ screenshots: true, snapshots: true, sources: true });

    await page.goto(config.appUrl, { waitUntil: "domcontentloaded", timeout: 90000 });
    await waitForAppShell(page, config, interactive);
    screenshots.push({ name: "app-home", path: await screenshot(page, artifactDir, "01-app-home") });
    await assertNoVisibleAppError(page, "app-home");
    checks.push({ name: "app-home", status: "passed", diagnostics: await collectDiagnostics(page) });

    for (const screen of config.screens) {
      await page.goto(screen.url, { waitUntil: "domcontentloaded", timeout: 90000 });
      await waitForAppShell(page, config, interactive);
      const markerResult = await waitForScreenMarkers(page, screen);
      const shot = await screenshot(page, artifactDir, `${String(checks.length + 1).padStart(2, "0")}-${screen.name}`);
      screenshots.push({ name: screen.name, path: shot });
      await assertNoVisibleAppError(page, screen.name);

      checks.push({
        name: screen.name,
        status: "passed",
        expectedAllMarkers: markerResult.markerCheck.expectedAll,
        expectedAnyMarkers: markerResult.markerCheck.expectedAny,
        diagnostics: await collectDiagnostics(page),
      });
    }

    status = "passed";
  } catch (error) {
    failure = {
      message: error.message,
      stack: error.stack,
      diagnostics: page ? await collectDiagnostics(page).catch(() => null) : null,
    };
    if (page) {
      try {
        screenshots.push({ name: "failure", path: await screenshot(page, artifactDir, "failure") });
      } catch {}
    }
    throw error;
  } finally {
    const tracePath = path.join(artifactDir, "trace.zip");
    if (context) {
      try {
        await context.tracing.stop({ path: tracePath });
      } catch {}
    }

    writeJson(path.join(artifactDir, "console.json"), consoleEntries);
    writeJson(path.join(artifactDir, "page-errors.json"), pageErrors);
    writeJson(path.join(artifactDir, "network-errors.json"), networkEntries);

    const result = {
      status,
      runId,
      appUrl: config.appUrl,
      appId: config.appId,
      environmentUrl: config.environmentUrl,
      screenshots,
      trace: fs.existsSync(tracePath) ? tracePath : null,
      consoleErrorCount: consoleEntries.filter((entry) => entry.type === "error").length,
      pageErrorCount: pageErrors.length,
      networkErrorCount: networkEntries.length,
      checks,
      failure,
    };
    writeJson(path.join(artifactDir, "result.json"), result);

    const report = [];
    appendLine(report, "# Council Model-Driven App Screen Test");
    appendLine(report);
    appendLine(report, `- Status: ${status}`);
    appendLine(report, `- Run ID: ${runId}`);
    appendLine(report, `- App URL: ${config.appUrl}`);
    appendLine(report, `- Trace: ${result.trace || "not captured"}`);
    appendLine(report, `- Console errors: ${result.consoleErrorCount}`);
    appendLine(report, `- Page errors: ${result.pageErrorCount}`);
    appendLine(report, `- Network HTTP errors: ${result.networkErrorCount}`);
    if (failure) {
      appendLine(report);
      appendLine(report, "## Failure");
      appendLine(report);
      appendLine(report, `- Message: ${failure.message}`);
    }
    appendLine(report);
    appendLine(report, "## Screenshots");
    appendLine(report);
    for (const shot of screenshots) {
      appendLine(report, `- ${shot.name}: ${shot.path}`);
    }
    fs.writeFileSync(path.join(artifactDir, "REPORT.md"), report.join("\n"), "utf8");

    if (context) {
      await context.close().catch(() => {});
    }
    if (browser) {
      await browser.close().catch(() => {});
    }

    console.log(`COUNCIL_MODEL_DRIVEN_SCREEN_TEST_${status.toUpperCase()}`);
    console.log(`Artifacts: ${artifactDir}`);
  }
}

run().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
