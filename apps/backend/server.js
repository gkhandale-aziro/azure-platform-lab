const express = require("express");

const app = express();
const PORT = process.env.PORT || 5678;
const ENV = process.env.APP_ENV || "unknown";
const VERSION = process.env.APP_VERSION || "dev";

app.use(express.json());

// Liveness/readiness probe target.
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Env-aware info endpoint. Frontend calls this and renders the result.
app.get("/api/info", (req, res) => {
  res.status(200).json({
    env: ENV,
    version: VERSION,
    namespace: process.env.POD_NAMESPACE || "unset",
    pod: process.env.HOSTNAME || "unset",
    timestamp: new Date().toISOString(),
  });
});

// Exported separately so tests can mount the app without binding to a port.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`backend listening on :${PORT} env=${ENV} version=${VERSION}`);
  });
}

module.exports = app;
