// Runs the Worker with fake Grok and Claude servers. No real keys needed.
// Run: npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

const TOKENS = JSON.stringify({ "test-token": { name: "test", capSeconds: 100 } });

function makeEnv() {
  const store = new Map();
  return {
    FAMILY_TOKENS: TOKENS,
    XAI_API_KEY: "fake-xai",
    ANTHROPIC_API_KEY: "fake-anthropic",
    USAGE: {
      get: async (k) => store.get(k) ?? null,
      put: async (k, v) => void store.set(k, v),
    },
    store,
  };
}

function mockUpstreams({ stt, claude }) {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("api.x.ai")) return stt(init);
    if (String(url).includes("api.anthropic.com")) return claude(init);
    throw new Error("unexpected fetch " + url);
  };
  return calls;
}

const okStt = () => Response.json({ text: "um hello there", language: "en", duration: 7.2 });
const okClaude = () => Response.json({ content: [{ type: "text", text: "Hello there." }] });

const dictate = (env, { token = "test-token", body = new Uint8Array([1, 2, 3]), query = "" } = {}) =>
  worker.fetch(
    new Request("https://w.example/dictate" + query, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "audio/mp4",
        "X-Duration-Seconds": "15",
      },
      body,
    }),
    env,
  );

test("happy path returns clean text and counts Grok's duration", async () => {
  const env = makeEnv();
  const calls = mockUpstreams({ stt: okStt, claude: okClaude });
  const res = await dictate(env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: "Hello there.", raw: "um hello there" });
  assert.deepEqual([...env.store.values()], ["8"]);

  const sttCall = calls[0];
  assert.equal(sttCall.url, "https://api.x.ai/v1/stt");
  assert.equal(sttCall.init.headers.Authorization, "Bearer fake-xai");
  const fields = [...sttCall.init.body.keys()];
  assert.equal(fields.at(-1), "file", "file must be the last form field");
  assert.ok(!fields.includes("model"));

  const claudeBody = JSON.parse(calls[1].init.body);
  assert.equal(claudeBody.messages[0].content, "<dictation>um hello there</dictation>");
});

test("Claude failure falls back to the raw transcript", async () => {
  const env = makeEnv();
  mockUpstreams({ stt: okStt, claude: () => new Response("boom", { status: 500 }) });
  const res = await dictate(env);
  assert.equal(res.status, 200);
  assert.equal((await res.json()).text, "um hello there");
});

test("Claude network error falls back to the raw transcript", async () => {
  const env = makeEnv();
  mockUpstreams({ stt: okStt, claude: () => { throw new Error("offline"); } });
  const res = await dictate(env);
  assert.equal((await res.json()).text, "um hello there");
});

test("cleanup=0 skips Claude", async () => {
  const env = makeEnv();
  const calls = mockUpstreams({ stt: okStt, claude: okClaude });
  const res = await dictate(env, { query: "?cleanup=0" });
  assert.equal((await res.json()).text, "um hello there");
  assert.equal(calls.length, 1);
});

test("bad token is 401, empty audio is 413, Grok failure is 502", async () => {
  const env = makeEnv();
  mockUpstreams({ stt: () => new Response("nope", { status: 500 }), claude: okClaude });
  assert.equal((await dictate(env, { token: "wrong" })).status, 401);
  assert.equal((await dictate(env, { body: new Uint8Array() })).status, 413);
  assert.equal((await dictate(env)).status, 502);
  mockUpstreams({ stt: () => { throw new Error("offline"); }, claude: okClaude });
  assert.equal((await dictate(env)).status, 502);
});

test("monthly cap returns 429", async () => {
  const env = makeEnv();
  mockUpstreams({ stt: okStt, claude: okClaude });
  const month = new Date().toISOString().slice(0, 7);
  env.store.set(`usage:test:${month}`, "100");
  assert.equal((await dictate(env)).status, 429);
});
