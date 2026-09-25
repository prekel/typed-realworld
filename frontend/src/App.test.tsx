import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";
import * as api from "./api";

vi.mock("./api", () => ({
  authenticate: vi.fn(),
  errorMessage: (error: unknown) => error instanceof Error ? error.message : "Request failed",
  fetchArticles: vi.fn(),
  publishArticle: vi.fn(),
  setAuthToken: vi.fn(),
}));

const article: api.Article = {
  slug: "hello-realworld",
  title: "Hello RealWorld",
  description: "A typed client",
  tagList: [],
  createdAt: "2026-09-25T10:00:00Z",
  updatedAt: "2026-09-25T10:00:00Z",
  favorited: false,
  favoritesCount: 0,
  author: { username: "alice", bio: null, image: null, following: false },
};

const user: api.AuthenticatedUser = {
  email: "alice@example.com",
  token: "jwt-token",
  username: "alice",
  bio: null,
  image: null,
};

describe("RealWorld frontend", () => {
  beforeEach(() => {
    vi.mocked(api.fetchArticles).mockResolvedValue([]);
  });

  afterEach(() => cleanup());

  it("registers, loads articles, and publishes a new article", async () => {
    const userInput = userEvent.setup();
    vi.mocked(api.fetchArticles).mockResolvedValue([article]);
    vi.mocked(api.authenticate).mockResolvedValue(user);
    vi.mocked(api.publishArticle).mockResolvedValue({
      ...article,
      slug: "typed-frontend",
      title: "Typed frontend",
    });
    render(<App />);

    expect(await screen.findByRole("heading", { name: "Hello RealWorld" })).toBeTruthy();
    await userInput.type(screen.getByLabelText("Username (for registration)"), "alice");
    await userInput.type(screen.getByLabelText("Email"), "alice@example.com");
    await userInput.type(screen.getByLabelText("Password"), "long-password");
    await userInput.click(screen.getByRole("button", { name: "Register" }));

    expect(await screen.findByText("Signed in as alice", { selector: "span" })).toBeTruthy();
    expect(api.setAuthToken).toHaveBeenCalledWith("jwt-token");

    await userInput.type(screen.getByLabelText("Title"), "Typed frontend");
    await userInput.type(screen.getByLabelText("Description"), "Generated API types");
    await userInput.type(screen.getByLabelText("Body"), "Published through the generated client.");
    await userInput.click(screen.getByRole("button", { name: "Publish" }));

    expect(await screen.findByRole("heading", { name: "Typed frontend" })).toBeTruthy();
    expect(api.publishArticle).toHaveBeenCalledWith({
      title: "Typed frontend",
      description: "Generated API types",
      body: "Published through the generated client.",
    });
  });

  it("shows API validation failures to the user", async () => {
    const userInput = userEvent.setup();
    vi.mocked(api.authenticate).mockRejectedValue(new Error("email has already been taken"));
    render(<App />);

    await userInput.type(screen.getByLabelText("Email"), "alice@example.com");
    await userInput.type(screen.getByLabelText("Password"), "long-password");
    await userInput.click(screen.getByRole("button", { name: "Log in" }));

    expect((await screen.findByRole("status")).textContent).toContain("email has already been taken");
  });
});
