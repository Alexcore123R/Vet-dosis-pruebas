export function checkoutParameters(
  request,
  origin,
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  const url = new URL(origin);
  if (url.protocol !== "https:" || url.username || url.password) {
    throw new Error("https_origin_required");
  }
  if (
    !["individual", "clinic"].includes(request.plan_code) ||
    !["monthly", "annual"].includes(request.period) ||
    !Number.isSafeInteger(request.price_cents) || request.price_cents <= 0
  ) throw new Error("invalid_checkout_request");
  const p = new URLSearchParams({
    mode: "subscription",
    client_reference_id: request.id,
    success_url: new URL("/?subscription=review", url).toString(),
    cancel_url: new URL("/?subscription=cancelled", url).toString(),
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": "mxn",
    "line_items[0][price_data][unit_amount]": String(request.price_cents),
    "line_items[0][price_data][recurring][interval]":
      request.period === "annual" ? "year" : "month",
    "line_items[0][price_data][product_data][name]":
      `VetDosis Pro · ${request.plan_code}`,
    "subscription_data[metadata][vetdosis_request]": request.id,
  });
  if (request.trial_until) {
    const end = Math.floor(Date.parse(request.trial_until) / 1000);
    if (!Number.isFinite(end) || end < nowSeconds + 172800) {
      throw new Error("benefit_window_too_short");
    }
    p.set("subscription_data[trial_end]", String(end));
  }
  return p;
}
export async function verifyStripeSignature(
  body,
  header,
  secret,
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  if (!secret || !header) throw new Error("invalid_signature");
  const parts = header.split(",");
  const t = parts.find((p) => p.startsWith("t="))?.slice(2);
  const signatures = parts.filter((p) => p.startsWith("v1=")).map((p) =>
    p.slice(3)
  );
  if (!/^\d+$/.test(t ?? "") || Math.abs(nowSeconds - Number(t)) > 300) {
    throw new Error("expired_signature");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const hash = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${t}.${body}`),
    ),
  );
  const expected = Array.from(hash, (b) => b.toString(16).padStart(2, "0"))
    .join("");
  const match = signatures.some((s) => {
    if (s.length !== expected.length) return false;
    let diff = 0;
    for (let i = 0; i < s.length; i++) {
      diff |= s.charCodeAt(i) ^ expected.charCodeAt(i);
    }
    return diff === 0;
  });
  if (!match) throw new Error("invalid_signature");
}
export function paidInvoice(event) {
  if (event.type !== "invoice.paid") return null;
  const i = event.data?.object;
  if (i?.status === "paid" && i.amount_paid === 0) return null;
  const request = i?.subscription_details?.metadata?.vetdosis_request;
  const period = i?.lines?.data?.[0]?.period;
  if (
    i?.status !== "paid" || typeof request !== "string" ||
    typeof i.subscription !== "string" || i.currency !== "mxn" ||
    !Number.isSafeInteger(i.amount_paid) || i.amount_paid <= 0 ||
    !Number.isInteger(period?.start) || !Number.isInteger(period?.end) ||
    period.end <= period.start
  ) throw new Error("invalid_paid_invoice");
  return {
    p_request: request,
    p_invoice: i.id,
    p_subscription: i.subscription,
    p_event: event.id,
    p_amount: i.amount_paid,
    p_currency: i.currency,
    p_start: new Date(period.start * 1000).toISOString(),
    p_end: new Date(period.end * 1000).toISOString(),
  };
}
