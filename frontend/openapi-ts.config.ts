import { defineConfig } from "@hey-api/openapi-ts";

export default defineConfig({
  input: "../_build/default/tools/openapi.json",
  output: "src/generated/api",
  plugins: ["@hey-api/typescript", "@hey-api/sdk", "@hey-api/client-fetch"],
});
