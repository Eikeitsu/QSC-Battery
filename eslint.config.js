import eslint from "@eslint/js";
import pluginVue from "eslint-plugin-vue";
import globals from "globals";
import tseslint from "typescript-eslint";
import vueParser from "vue-eslint-parser";

const sharedIgnores = {
  ignores: [
    "**/node_modules/**",
    "**/.build/**",
    "**/.release/**",
    "**/module/webroot/**",
    "**/archives/**",
    "**/docs/.vitepress/dist/**",
    "**/docs/.vitepress/cache/**",
    "webui/public/**",
    "package-lock.json",
  ],
};

export default tseslint.config(
  sharedIgnores,
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  ...pluginVue.configs["flat/recommended"],
  {
    files: ["webui/**/*.{ts,vue}"],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tseslint.parser,
        ecmaVersion: "latest",
        sourceType: "module",
        extraFileExtensions: [".vue"],
      },
      globals: {
        ...globals.browser,
      },
    },
    rules: {
      "vue/multi-word-component-names": "off",
      "vue/no-undef-components": ["error", { ignorePatterns: ["^Van[A-Z].*"] }],
      "vue/html-self-closing": [
        "error",
        {
          html: { void: "always", normal: "never", component: "always" },
          svg: "always",
          math: "always",
        },
      ],
      "vue/component-api-style": ["error", ["script-setup"]],
      "vue/block-order": ["error", { order: ["script", "template", "style"] }],
      "vue/define-macros-order": [
        "error",
        {
          order: ["defineProps", "defineEmits", "defineSlots"],
        },
      ],
      "vue/no-unused-refs": "error",
      "vue/no-useless-v-bind": "error",
      "vue/prefer-separate-static-class": "warn",
      "vue/eqeqeq": ["error", "smart"],
      "vue/max-attributes-per-line": "off",
      "vue/singleline-html-element-content-newline": "off",
      "vue/attributes-order": "warn",
      "vue/html-indent": "off",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" },
      ],
      "@typescript-eslint/no-explicit-any": "off",
      "no-undef": "off",
      "no-console": ["warn", { allow: ["warn", "error"] }],
      eqeqeq: ["error", "smart"],
      "prefer-const": "error",
    },
  },
  {
    files: ["webui/**/*.ts"],
    languageOptions: {
      parser: tseslint.parser,
    },
  },
  {
    files: [
      "tooling/**/*.{js,mjs,cjs}",
      "docs/.vitepress/**/*.{js,mjs,cjs}",
      "eslint.config.js",
      "stylelint.config.js",
      "commitlint.config.js",
      "webui/vite.config.ts",
    ],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
      },
      globals: {
        ...globals.node,
        ...globals.browser,
      },
    },
    rules: {
      "@typescript-eslint/no-require-imports": "off",
      "no-console": "off",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" },
      ],
    },
  },
);
