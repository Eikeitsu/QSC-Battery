/** @type {import('stylelint').Config} */
export default {
  extends: ["stylelint-config-standard-scss", "stylelint-config-recommended-vue/scss"],
  ignoreFiles: [
    "**/node_modules/**",
    "**/.build/**",
    "**/module/webroot/**",
    "**/archives/**",
    "**/docs/.vitepress/dist/**",
  ],
  rules: {
    "selector-class-pattern": null,
    "custom-property-pattern": null,
    "keyframes-name-pattern": null,
    "scss/at-rule-no-unknown": [
      true,
      {
        ignoreAtRules: ["use", "forward", "include", "mixin", "each", "if", "else"],
      },
    ],
    "no-descending-specificity": null,
    "declaration-block-no-redundant-longhand-properties": null,
    "color-function-notation": null,
    "alpha-value-notation": null,
    "import-notation": "string",
    "media-feature-range-notation": null,
    "property-no-vendor-prefix": null,
  },
};
