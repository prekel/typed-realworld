import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchArticles, setAuthToken } from "./api";

describe("generated OpenAPI client", () => {
  afterEach(() => {
    setAuthToken(undefined);
    vi.unstubAllGlobals();
  });

  it("sends RealWorld Token authorization through the generated SDK", async () => {
    const fetchMock = vi.fn(async (_request: Request) =>
      new Response(JSON.stringify({ articles: [], articlesCount: 0 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    setAuthToken("sample-jwt");

    expect(await fetchArticles()).toEqual([]);
    expect(fetchMock).toHaveBeenCalledOnce();
    expect(fetchMock.mock.calls[0]?.[0].headers.get("Authorization")).toBe("Token sample-jwt");
  });
});
