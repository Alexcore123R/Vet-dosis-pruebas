import {
  credentialMaster,
  openCredential,
  sealCredential,
} from "../_shared/ai_crypto.mjs";
import { createClient } from "@supabase/supabase-js";
import {
  buildMessages,
  listModels,
  providerNames,
  providerRequest,
  providerText,
} from "../_shared/ai_providers.mjs";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const label = (provider: string, scope: string, owner: string) =>
  `vetdosis:1:${provider}:${scope}:${owner}`;
Deno.serve(async (req) => {
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        ...cors,
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  if (req.method === "OPTIONS") return reply({});
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return reply({ error: "authentication_required" }, 401);
  }
  const user = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    },
  );
  const { data: identity, error: authError } = await user.auth.getUser();
  if (authError || !identity.user) {
    return reply({ error: "authentication_required" }, 401);
  }
  const actor = identity.user.id;
  const server = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  let claimed: string | null = null;
  try {
    const body = await req.text();
    if (body.length > 24000) return reply({ error: "request_too_large" }, 413);
    const input = JSON.parse(body);
    const aes = await credentialMaster(
      Deno.env.get("AI_KEY_ENCRYPTION_SECRET"),
    );
    if (input.action === "save_key") {
      if (
        !providerNames.includes(input.provider) ||
        !["personal", "clinic"].includes(input.scope) ||
        typeof input.key !== "string" || input.key.length < 10 ||
        input.key.length > 2000
      ) return reply({ error: "invalid_key_request" }, 400);
      const sealed = await sealCredential(
        input.key,
        aes,
        label(
          input.provider,
          input.scope,
          input.scope === "personal" ? actor : input.clinic,
        ),
      );
      const { data, error } = await server.rpc("ai_key_store_server", {
        p_user: actor,
        p_scope: input.scope,
        p_clinic: input.scope === "clinic" ? input.clinic : null,
        p_provider: input.provider,
        p_cipher: sealed.ciphertext,
        p_nonce: sealed.nonce,
      });
      if (error) return reply({ error: "key_save_denied" }, 403);
      return reply({ id: data });
    }
    if (input.action === "models") {
      const { data: key, error } = await server.rpc("ai_key_get_server", {
        p_user: actor,
        p_connection: input.connection,
      });
      if (error || !key) return reply({ error: "key_access_denied" }, 403);
      const plaintext = await openCredential(
        key,
        aes,
        label(key.provider, key.scope, key.owner_id ?? key.clinic_id),
      );
      return reply({ models: await listModels(key.provider, plaintext) });
    }
    if (input.action !== "send") return reply({ error: "invalid_action" }, 400);
    const { data: r, error: prepareError } = await user.rpc("ai_prepare", {
      p_chat: input.chat,
      p_connection: input.connection,
      p_model: input.model,
      p_message: input.message,
      p_operation: input.operation,
      p_personal: input.personal === true,
      p_team: input.team === true,
    });
    if (prepareError) {
      return reply({
        error: prepareError.message.includes("ai_daily_limit")
          ? "ai_daily_limit"
          : "chat_prepare_denied",
      }, 403);
    }
    if (r.state === "done") return reply({ request: r.id, state: "done" });
    if (r.state !== "queued") {
      return reply({ error: "request_already_started" }, 409);
    }
    const { data: snapshot, error: claimError } = await server.rpc(
      "ai_claim_server",
      { p_id: r.id, p_user: actor },
    );
    if (claimError) {
      if (claimError.message !== "request_already_claimed") {
        await server.rpc("ai_finish_server", {
          p_id: r.id,
          p_user: actor,
          p_body: "",
          p_success: false,
        });
      }
      return reply({ error: "request_already_started_or_denied" }, 409);
    }
    claimed = r.id;
    const k = snapshot.key;
    const plaintext = await openCredential(
      k,
      aes,
      label(k.provider, k.scope, k.owner_id ?? k.clinic_id),
    );
    const request = providerRequest(
      k.provider,
      plaintext,
      input.model,
      buildMessages(snapshot),
    );
    const headers = new Headers();
    for (const [name, value] of Object.entries(request.headers)) {
      if (typeof value !== "string") {
        throw new Error("invalid_provider_headers");
      }
      headers.set(name, value);
    }
    const response = await fetch(request.url, {
      method: "POST",
      headers,
      body: JSON.stringify(request.body),
      signal: AbortSignal.timeout(45000),
      redirect: "error",
    });
    if (!response.ok) throw new Error("provider_request_failed");
    const output = providerText(k.provider, await response.json());
    const { error: finishError } = await server.rpc("ai_finish_server", {
      p_id: r.id,
      p_user: actor,
      p_body: output,
      p_success: true,
    });
    if (finishError) throw new Error("finish_failed");
    claimed = null;
    const { data: state, error: stateError } = await user.rpc("ai_prepare", {
      p_chat: input.chat,
      p_connection: input.connection,
      p_model: input.model,
      p_message: input.message,
      p_operation: input.operation,
      p_personal: input.personal === true,
      p_team: input.team === true,
    });
    if (stateError || state?.state !== "done") {
      return reply({ error: "context_or_access_changed" }, 409);
    }
    const { error: readError } = await user.rpc("ai_messages_read", {
      p_chat: input.chat,
    });
    if (readError) return reply({ error: "chat_access_lost" }, 403);
    return reply({ request: r.id, state: "done" });
  } catch {
    if (claimed) {
      await server.rpc("ai_finish_server", {
        p_id: claimed,
        p_user: actor,
        p_body: "",
        p_success: false,
      });
    }
    // Never log or echo provider bodies, keys, prompts, or decrypted credentials.
    return reply({ error: "ai_unavailable_or_request_failed" }, 503);
  }
});
