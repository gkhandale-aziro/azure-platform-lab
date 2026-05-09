import globals from "globals";
import reactPlugin from "eslint-plugin-react";

export default [
  // Skip generated artifacts and dependency dirs — flat config doesn't auto-ignore these.
  {
    ignores: ["dist/**", "node_modules/**", "coverage/**", "build/**"],
  },
  {
    files: ["**/*.{js,jsx}"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: {
        ...globals.browser,
        ...globals.node,
        // Vitest globals (configured via globals: true in vite.config.js)
        describe: "readonly",
        test: "readonly",
        expect: "readonly",
        vi: "readonly",
        beforeEach: "readonly",
        afterEach: "readonly",
      },
    },
    plugins: { react: reactPlugin },
    settings: { react: { version: "18.3" } },
    rules: {
      "no-unused-vars": "error",
      semi: ["error", "always"],
      // React 17+ JSX transform — no `import React` needed at top of files.
      "react/jsx-uses-react": "off",
      "react/react-in-jsx-scope": "off",
      // Tells no-unused-vars that JSX usage (e.g. <App />, <React.StrictMode>)
      // counts as referencing the imported variable.
      "react/jsx-uses-vars": "error",
    },
  },
];
