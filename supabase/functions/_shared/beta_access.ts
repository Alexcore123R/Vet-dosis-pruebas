// Check with the caller's JWT before any privileged service call or external cost.
export async function betaAccess(user: { rpc: (name: string, args: Record<string, unknown>) => PromiseLike<{data: unknown; error: unknown}> }, write: boolean, clinic: string | null = null) {
  const { error } = await user.rpc('beta_access_check', {p_write: write, p_clinic: clinic});
  return !error;
}
