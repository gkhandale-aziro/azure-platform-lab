const request = require("supertest");

// Use a fixed env so the test assertions are stable regardless of what's
// in the shell when the test runs.
process.env.APP_ENV = "test";
process.env.APP_VERSION = "test-1";

const app = require("./server");

describe("backend", () => {
  test("GET /health returns 200 ok", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok" });
  });

  test("GET /api/info echoes env + version", async () => {
    const res = await request(app).get("/api/info");
    expect(res.status).toBe(200);
    expect(res.body.env).toBe("test");
    expect(res.body.version).toBe("test-1");
    expect(res.body).toHaveProperty("timestamp");
  });

  test("unknown route returns 404", async () => {
    const res = await request(app).get("/no-such-route");
    expect(res.status).toBe(404);
  });
});
