import { createClient } from "@supabase/supabase-js";
import { checkoutParameters } from "../_shared/subscription_billing.mjs";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
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
  try {
    const text = await req.text();
    if (text.length > 2000) return reply({ error: "request_too_large" }, 413);
    const body = JSON.parse(text);
    const secret = Deno.env.get("STRIPE_SECRET_KEY"),
      origin = Deno.env.get("APP_CHECKOUT_ORIGIN");
    if (!secret || !origin) {
      return reply({ error: "billing_not_configured" }, 503);
    }
    const { data: r, error } = await user.rpc("billing_request_read", {
      p_id: body.request,
    });
    if (error) return reply({ error: "pricing_or_request_denied" }, 403);
    const response = await fetch(
      "https://api.stripe.com/v1/checkout/sessions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secret}`,
          "Content-Type": "application/x-www-form-urlencoded",
          "Stripe-Version": "2024-06-20",
          "Idempotency-Key": `vetdosis:${r.id}`,
        },
        body: checkoutParameters(r, origin),
        signal: AbortSignal.timeout(20000),
        redirect: "error",
      },
    );
    if (!response.ok) return reply({ error: "checkout_unavailable" }, 502);
    const data = await response.json();
    const url = new URL(data.url);
    if (url.protocol !== "https:" || url.hostname !== "checkout.stripe.com") {
      return reply({ error: "invalid_checkout_url" }, 502);
    }
    return reply({ url: url.toString() });
  } catch {
    return reply({ error: "checkout_unavailable" }, 503);
  }
});
