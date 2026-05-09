import { useEffect, useState } from "react";

export default function App() {
  const [info, setInfo] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch("/api/info")
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      })
      .then(setInfo)
      .catch((e) => setError(e.message));
  }, []);

  return (
    <main style={{ fontFamily: "sans-serif", maxWidth: 640, margin: "2rem auto" }}>
      <h1>three-tier lab</h1>
      {error && <p style={{ color: "crimson" }}>backend error: {error}</p>}
      {!info && !error && <p>loading…</p>}
      {info && (
        <table>
          <tbody>
            <tr><td><strong>env</strong></td><td>{info.env}</td></tr>
            <tr><td><strong>version</strong></td><td>{info.version}</td></tr>
            <tr><td><strong>namespace</strong></td><td>{info.namespace}</td></tr>
            <tr><td><strong>pod</strong></td><td><code>{info.pod}</code></td></tr>
            <tr><td><strong>fetched at</strong></td><td>{info.timestamp}</td></tr>
          </tbody>
        </table>
      )}
    </main>
  );
}
