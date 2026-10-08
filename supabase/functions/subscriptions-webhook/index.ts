import { createClient } from "@supabase/supabase-js";
import {
  paidInvoice,
  verifyStripeSignature,
} from "../_shared/subscription_billing.mjs";
Deno.serve(async (req) => {
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const body = await req.text();
  if (body.length > 500000) return reply({ error: "too_large" }, 413);
  try {
    await verifyStripeSignature(
      body,
      req.headers.get("stripe-signature"),
      Deno.env.get("STRIPE_WEBHOOK_SECRET"),
    );
  } catch {
    return reply({ error: "invalid_signature" }, 400);
  }
  try {
    const invoice = paidInvoice(JSON.parse(body));
    if (!invoice) return reply({ received: true });
    const server = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { error } = await server.rpc("billing_invoice_server", invoice);
    if (error) return reply({ error: "invoice_denied" }, 409);
    return reply({ received: true });
  } catch {
    return reply({ error: "invalid_invoice" }, 400);
  }
});
