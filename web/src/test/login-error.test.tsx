import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import LoginPage from "@/pages/auth/LoginPage";
import { authApi } from "@/services/auth";
import { shouldClearAndRedirect } from "@/services/api";

// U3 (assessment/01-audit.md, assessment/risk-register.json): a wrong password
// on /login hits the global 401 interceptor, which used to hard-redirect to
// "/login" while the user was already there — full page reload, error state
// discarded, blank form with no explanation.

vi.mock("@/services/auth", () => ({
  authApi: { login: vi.fn() },
}));

const loginMock = vi.mocked(authApi.login);

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe("U3 — 401 on /login must not bounce the page", () => {
  it("does not clear/redirect when an auth error arrives while already on /login", () => {
    expect(shouldClearAndRedirect(401, "/login")).toBe(false);
    expect(shouldClearAndRedirect(403, "/login")).toBe(false);
  });

  it("still clears and redirects on auth errors from any other route", () => {
    expect(shouldClearAndRedirect(401, "/assessments")).toBe(true);
    expect(shouldClearAndRedirect(403, "/portfolio/1")).toBe(true);
  });

  it("ignores non-auth statuses entirely", () => {
    expect(shouldClearAndRedirect(404, "/login")).toBe(false);
    expect(shouldClearAndRedirect(500, "/assessments")).toBe(false);
    expect(shouldClearAndRedirect(undefined, "/login")).toBe(false);
  });
});

describe("LoginPage — failed credentials surface an error", () => {
  it("shows 'Invalid email or password.' when login is rejected", async () => {
    loginMock.mockRejectedValue({ response: { status: 401 } });

    render(
      <MemoryRouter initialEntries={["/login"]}>
        <LoginPage />
      </MemoryRouter>
    );

    await fireEvent.change(screen.getByLabelText(/email/i), {
      target: { value: "assessor@example.com" },
    });
    await fireEvent.change(screen.getByLabelText(/password/i), {
      target: { value: "wrong-password" },
    });
    await fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    expect(await screen.findByText(/invalid email or password/i)).toBeInTheDocument();
    // The form must still be there — no reload wiped the page.
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
    expect(loginMock).toHaveBeenCalledWith({
      email: "assessor@example.com",
      password: "wrong-password",
    });
  });
});
