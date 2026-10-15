/**
 * The three globals RTK Query's fetchBaseQuery needs and jsdom does not have:
 * fetch, Request and Response (Headers it has). Imported FIRST by
 * api.ado.tags.test.ts, before the slice, so createApi finds a fetch and the
 * test reads every URL the store asked for. Not a test; jest's testMatch
 * ignores it.
 */
export const fetched: string[] = [];

class StubRequest {
  readonly url: string;
  readonly method: string;
  readonly headers: Headers;
  readonly body: unknown;
  constructor(url: string, init: { method?: string; headers?: Headers; body?: unknown } = {}) {
    this.url = url;
    this.method = init.method ?? "GET";
    this.headers = init.headers instanceof Headers ? init.headers : new Headers(init.headers);
    this.body = init.body;
  }
  clone() {
    return this;
  }
}

class StubResponse {
  readonly ok = true;
  readonly status = 200;
  readonly headers = new Headers({ "content-type": "application/json" });
  constructor(private readonly text_: string) {}
  clone() {
    return this;
  }
  async text() {
    return this.text_;
  }
  async json() {
    return JSON.parse(this.text_);
  }
}

const g = globalThis as unknown as Record<string, unknown>;
g.Request = StubRequest;
g.Response = StubResponse;
g.fetch = async (req: StubRequest) => {
  fetched.push(req.url);
  return new StubResponse(JSON.stringify({ count: 0, items: [], status: "success", prompts: [] }));
};
