import { useCallback, useEffect, useState, type FormEvent } from "react";
import {
  authenticate,
  errorMessage,
  fetchArticles,
  publishArticle,
  setAuthToken,
  type Article,
  type AuthenticatedUser,
} from "./api";

type Credentials = {
  username: string;
  email: string;
  password: string;
};

type ArticleDraft = {
  title: string;
  description: string;
  body: string;
};

const emptyCredentials: Credentials = { username: "", email: "", password: "" };
const emptyDraft: ArticleDraft = { title: "", description: "", body: "" };

export function App() {
  const [articles, setArticles] = useState<Article[]>([]);
  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  const [credentials, setCredentials] = useState(emptyCredentials);
  const [draft, setDraft] = useState(emptyDraft);
  const [busy, setBusy] = useState(false);
  const [loadingArticles, setLoadingArticles] = useState(true);
  const [message, setMessage] = useState<string | null>(null);
  const [isError, setIsError] = useState(false);

  const loadArticles = useCallback(async () => {
    setLoadingArticles(true);
    try {
      setArticles(await fetchArticles());
      setMessage(null);
      setIsError(false);
    } catch (error) {
      setMessage(errorMessage(error));
      setIsError(true);
    } finally {
      setLoadingArticles(false);
    }
  }, []);

  useEffect(() => {
    void loadArticles();
  }, [loadArticles]);

  async function onAuthenticate(mode: "login" | "register", event?: FormEvent<HTMLFormElement>) {
    event?.preventDefault();
    setBusy(true);
    setMessage(mode === "login" ? "Signing in…" : "Creating account…");
    setIsError(false);
    try {
      const nextUser = await authenticate(mode, credentials);
      setAuthToken(nextUser.token);
      setUser(nextUser);
      setCredentials((current) => ({ ...current, password: "" }));
      setMessage(`Welcome, ${nextUser.username}.`);
    } catch (error) {
      setMessage(errorMessage(error));
      setIsError(true);
    } finally {
      setBusy(false);
    }
  }

  async function onPublish(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!user) {
      setMessage("Sign in before publishing an article.");
      setIsError(true);
      return;
    }
    setBusy(true);
    setMessage("Publishing…");
    setIsError(false);
    try {
      const article = await publishArticle(draft);
      setArticles((current) => [article, ...current]);
      setDraft(emptyDraft);
      setMessage("Article published.");
    } catch (error) {
      setMessage(errorMessage(error));
      setIsError(true);
    } finally {
      setBusy(false);
    }
  }

  function signOut() {
    setAuthToken(undefined);
    setUser(null);
    setMessage("Signed out.");
    setIsError(false);
    void loadArticles();
  }

  return (
    <main>
      <header>
        <h1>RealWorld</h1>
        <span className="muted">{user ? `Signed in as ${user.username}` : "Guest"}</span>
      </header>

      {message && <div className={isError ? "message error" : "message"} role="status">{message}</div>}

      <div className="grid">
        <section className="panel" aria-labelledby="account-heading">
          <h2 id="account-heading">Account</h2>
          {user ? (
            <>
              <p>Signed in as {user.username}</p>
              <button className="secondary" type="button" onClick={signOut}>Sign out</button>
            </>
          ) : (
            <form onSubmit={(event) => void onAuthenticate("login", event)}>
              <label htmlFor="username">Username (for registration)</label>
              <input
                autoComplete="username"
                id="username"
                value={credentials.username}
                onChange={(event) => setCredentials({ ...credentials, username: event.target.value })}
              />
              <label htmlFor="email">Email</label>
              <input
                autoComplete="email"
                id="email"
                type="email"
                required
                value={credentials.email}
                onChange={(event) => setCredentials({ ...credentials, email: event.target.value })}
              />
              <label htmlFor="password">Password</label>
              <input
                autoComplete="current-password"
                id="password"
                type="password"
                required
                value={credentials.password}
                onChange={(event) => setCredentials({ ...credentials, password: event.target.value })}
              />
              <button disabled={busy} type="submit">Log in</button>
              <button
                className="secondary"
                disabled={busy}
                type="button"
                onClick={() => void onAuthenticate("register")}
              >
                Register
              </button>
            </form>
          )}
        </section>

        <section className="panel" aria-labelledby="article-heading">
          <h2 id="article-heading">New article</h2>
          <form onSubmit={(event) => void onPublish(event)}>
            <label htmlFor="title">Title</label>
            <input id="title" required value={draft.title} onChange={(event) => setDraft({ ...draft, title: event.target.value })} />
            <label htmlFor="description">Description</label>
            <input id="description" required value={draft.description} onChange={(event) => setDraft({ ...draft, description: event.target.value })} />
            <label htmlFor="body">Body</label>
            <textarea id="body" required value={draft.body} onChange={(event) => setDraft({ ...draft, body: event.target.value })} />
            <button disabled={busy || !user} type="submit">Publish</button>
          </form>
        </section>
      </div>

      <section className="panel" aria-labelledby="articles-heading">
        <h2 id="articles-heading">Articles</h2>
        <button className="secondary" disabled={busy || loadingArticles} type="button" onClick={() => void loadArticles()}>
          {loadingArticles ? "Loading…" : "Refresh"}
        </button>
        {articles.length === 0 ? (
          <p className="muted">{loadingArticles ? "Loading articles…" : "No articles yet"}</p>
        ) : (
          articles.map((article) => (
            <article className="article" key={article.slug}>
              <h3>{article.title}</h3>
              <p>{article.description}</p>
              <small>by {article.author.username} · {article.slug}</small>
            </article>
          ))
        )}
      </section>
    </main>
  );
}
