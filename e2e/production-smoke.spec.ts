import { test, expect } from "@playwright/test";

test("production app serves the EBS PRO sign-in screen", async ({ page }) => {
  const response = await page.goto("/");
  expect(response?.ok()).toBeTruthy();
  await expect(page).toHaveTitle(/EBS PRO/i);
  await expect(page.getByRole("heading", { name: "Sign in to your account" })).toBeVisible();
  await expect(page.getByLabel("Email address")).toBeVisible();
  await expect(page.getByLabel("Password")).toBeVisible();
});

test("signup form exposes required fields and strong-password guidance", async ({ page }) => {
  await page.goto("/");
  await page.getByText("Create account", { exact: true }).click();
  await expect(page.getByRole("heading", { name: "Create your account" })).toBeVisible();
  await expect(page.getByLabel("Full name")).toBeVisible();
  await expect(page.getByLabel("Email address")).toBeVisible();
  const password = page.getByLabel("Password");
  await expect(password).toHaveAttribute("minlength", "12");
  await expect(page.getByText(/12\+ characters, uppercase and lowercase/i)).toBeVisible();
});

test("forgot-password request returns a clear confirmation without exposing account existence", async ({ page }) => {
  await page.route("**/auth/v1/recover*", async route => {
    if (route.request().method() === "OPTIONS") {
      await route.fulfill({ status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-methods": "POST, OPTIONS", "access-control-allow-headers": "*" } });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", headers: { "access-control-allow-origin": "*" }, body: "{}" });
  });
  await page.goto("/");
  await page.getByLabel("Email address").fill("browser-smoke@example.invalid");
  await page.getByText("Forgot password?", { exact: true }).click();
  await expect(page.getByText(/Password recovery email sent/i)).toBeVisible();
});

test("mobile browser permissions can supply GPS and camera streams to the PWA", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "Runs in the mobile Chromium project.");
  await page.goto("/");
  const capabilities = await page.evaluate(async () => {
    const position = await new Promise<{ latitude: number; longitude: number }>((resolve, reject) =>
      navigator.geolocation.getCurrentPosition(
        value => resolve({ latitude: value.coords.latitude, longitude: value.coords.longitude }),
        reject,
        { timeout: 5000 }
      )
    );
    const stream = await navigator.mediaDevices.getUserMedia({ video: true });
    const hasVideoTrack = stream.getVideoTracks().length > 0;
    stream.getTracks().forEach(track => track.stop());
    return { position, hasVideoTrack };
  });
  expect(capabilities.position.latitude).toBeCloseTo(33.5651, 3);
  expect(capabilities.position.longitude).toBeCloseTo(73.0169, 3);
  expect(capabilities.hasVideoTrack).toBeTruthy();
});

test("mobile viewport keeps the authentication controls usable", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "Runs in the mobile Chromium project.");
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Sign in to your account" })).toBeVisible();
  const email = page.getByLabel("Email address");
  const bounds = await email.boundingBox();
  expect(bounds).not.toBeNull();
  expect(bounds!.width).toBeGreaterThan(200);
  expect(bounds!.x).toBeGreaterThanOrEqual(0);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(412);
});
