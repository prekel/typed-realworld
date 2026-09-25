import {
  createArticle,
  listArticles,
  loginUser,
  registerUser,
  type ArticlesResponse,
  type UserResponse,
} from "./generated/api";
import { client } from "./generated/api/client.gen";

export type Article = ArticlesResponse["articles"][number];
export type AuthenticatedUser = UserResponse["user"];

let authToken: string | undefined;

client.setConfig({
  baseUrl: window.location.origin,
  auth: () => (authToken ? `Token ${authToken}` : undefined),
});

export function setAuthToken(token: string | undefined): void {
  authToken = token;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : undefined;
}

export function errorMessage(error: unknown): string {
  const errorRecord = asRecord(error);
  const fields = asRecord(errorRecord?.errors);
  if (fields) {
    const messages = Object.entries(fields).flatMap(([field, value]) =>
      Array.isArray(value)
        ? value.filter((item): item is string => typeof item === "string").map((item) => `${field} ${item}`)
        : [],
    );
    if (messages.length > 0) return messages.join(", ");
  }
  return error instanceof Error ? error.message : "Request failed";
}

async function unwrap<T>(
  result: Promise<{ data?: T; error?: unknown; response?: Response } | undefined>,
): Promise<T> {
  const response = await result;
  if (!response) throw new Error("The API returned no response data");
  if (response.error !== undefined) {
    const message = errorMessage(response.error);
    const status = response.response?.status;
    throw new Error(status ? `${message} (HTTP ${status})` : message);
  }
  if (response.data === undefined) throw new Error("The API returned no response data");
  return response.data;
}

export async function fetchArticles(): Promise<Article[]> {
  const response = await unwrap(listArticles({ query: { limit: 20, offset: 0 } }));
  return response.articles;
}

export async function authenticate(
  mode: "login" | "register",
  credentials: { email: string; password: string; username: string },
): Promise<AuthenticatedUser> {
  const response =
    mode === "login"
      ? await unwrap(
          loginUser({ body: { user: { email: credentials.email, password: credentials.password } } }),
        )
      : await unwrap(
          registerUser({
            body: {
              user: {
                email: credentials.email,
                username: credentials.username,
                password: credentials.password,
              },
            },
          }),
        );
  return response.user;
}

export async function publishArticle(input: {
  title: string;
  description: string;
  body: string;
}): Promise<Article> {
  const response = await unwrap(
    createArticle({
      body: { article: { ...input, tagList: [] } },
    }),
  );
  const { body: _body, ...article } = response.article;
  return article;
}
