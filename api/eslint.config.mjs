import eslint from '@eslint/js';
import prettier from 'eslint-config-prettier';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';

export default defineConfig(
  globalIgnores(['dist', 'coverage', 'src/prisma-client']),
  eslint.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      globals: globals.node,
      parserOptions: {
        projectService: { allowDefaultProject: ['eslint.config.mjs'] },
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    files: ['test/**', '**/*.spec.ts'],
    languageOptions: { globals: globals.jest },
    rules: {
      // Jest types asymmetric matchers such as expect.any(String) as any.
      '@typescript-eslint/no-unsafe-assignment': 'off',
    },
  },
  prettier,
);
