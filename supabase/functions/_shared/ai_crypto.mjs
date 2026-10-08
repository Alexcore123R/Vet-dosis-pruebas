const encode = (bytes) => btoa(String.fromCharCode(...bytes));
const decode = (value) => Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
export async function credentialMaster(secret) {
  if (typeof secret !== "string" || !secret) {
    throw new Error("gateway_unconfigured");
  }
  const bytes = decode(secret);
  if (bytes.length !== 32) throw new Error("gateway_unconfigured");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}
export async function sealCredential(plaintext, key, label) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      additionalData: new TextEncoder().encode(label),
    },
    key,
    new TextEncoder().encode(plaintext),
  );
  return {
    ciphertext: encode(new Uint8Array(ciphertext)),
    nonce: encode(nonce),
  };
}
export async function openCredential(envelope, key, label) {
  const nonce = decode(envelope.nonce);
  if (nonce.length !== 12) throw new Error("invalid_nonce");
  const plaintext = await crypto.subtle.decrypt(
    {
      name: "AES-GCM",
      iv: nonce,
      additionalData: new TextEncoder().encode(label),
    },
    key,
    decode(envelope.ciphertext),
  );
  return new TextDecoder().decode(plaintext);
}
