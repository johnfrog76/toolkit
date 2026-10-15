import tseslint from "typescript-eslint";
import reactPlugin from "eslint-plugin-react";
import reactHooksPlugin from "eslint-plugin-react-hooks";
import prettierConfig from "eslint-config-prettier";
import { createRequire } from "node:module";

// The installed React's version, read here rather than with eslint-plugin-react's
// "detect": the plugin's detection calls context.getFilename(), which ESLint 10
// removed, and every rule that asks for the version then throws. Reading the
// package keeps the answer whatever React is installed, so nothing is typed twice.
const reactVersion = createRequire(import.meta.url)("react/package.json").version;

export default tseslint.config(
  { ignores: ["dist/**", "node_modules/**"] },

  ...tseslint.configs.recommended,

  {
    plugins: { react: reactPlugin, "react-hooks": reactHooksPlugin },
    settings: { react: { version: reactVersion } },
    rules: {
      ...reactPlugin.configs.recommended.rules,
      ...reactHooksPlugin.configs.recommended.rules,
      "react/react-in-jsx-scope": "off",
      "react/prop-types": "off",
    },
  },

  {
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_", varsIgnorePattern: "^_" }],
      "@typescript-eslint/consistent-type-imports": ["error", { prefer: "type-imports" }],
      "@typescript-eslint/no-explicit-any": "warn",
      // Downgraded to warn: the codebase intentionally uses setState-in-effect
      // for resetting derived state on dep change — a common, accepted pattern.
      "react-hooks/set-state-in-effect": "warn",
    },
  },

  prettierConfig,
);
