import { render, screen, waitFor } from "@testing-library/react";
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import App from "./App.jsx";

describe("<App />", () => {
  beforeEach(() => {
    global.fetch = vi.fn();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  test("renders the title", () => {
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ env: "test", version: "0", namespace: "x", pod: "y", timestamp: "now" }),
    });
    render(<App />);
    expect(screen.getByRole("heading", { name: /three-tier lab/i })).toBeTruthy();
  });

  test("displays backend info on successful fetch", async () => {
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        env: "dev-env",
        version: "1.0.0",
        namespace: "dev-ns",
        pod: "frontend-abc",
        timestamp: "2026-05-08T00:00:00Z",
      }),
    });
    render(<App />);
    await waitFor(() => {
      expect(screen.getByText("dev-env")).toBeTruthy();
      expect(screen.getByText("dev-ns")).toBeTruthy();
      expect(screen.getByText("1.0.0")).toBeTruthy();
      expect(screen.getByText("frontend-abc")).toBeTruthy();
    });
  });

  test("shows error message when fetch fails", async () => {
    global.fetch.mockResolvedValueOnce({ ok: false, status: 502 });
    render(<App />);
    await waitFor(() => {
      expect(screen.getByText(/backend error: HTTP 502/i)).toBeTruthy();
    });
  });
});
