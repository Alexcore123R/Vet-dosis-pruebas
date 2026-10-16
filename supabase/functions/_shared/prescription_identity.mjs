// Presentation contract for server-owned prescription snapshots. This validates
// attribution, not clinical authority: RPCs must verify grants and attestations.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function identifier(value) {
  if (typeof value !== 'string' || !uuid.test(value)) throw Error('invalid_prescription_identity');
  return value;
}
function text(value, error) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 200 || /[\u0000-\u001f\u007f]/.test(value)) throw Error(error);
  return value.trim();
}
function person(value, error) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error(error);
  return { user_id: identifier(value.user_id), name: text(value.name, error) };
}
function instant(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value) || !Number.isFinite(Date.parse(value))) throw Error('invalid_prescription_identity_time');
  const parsed = new Date(value);
  // Date.parse normalizes dates such as February 30; reject that normalization.
  if (parsed.toISOString().slice(0, 19) !== value.slice(0, 19)) throw Error('invalid_prescription_identity_time');
  return value;
}

export function prescriptionIdentity(snapshot) {
  const identity = snapshot.prescription_identity;
  if (identity === undefined && snapshot.prescription_identity_version === undefined) return null;
  if (snapshot.prescription_identity_version !== 1 || !identity || snapshot.schema?.type !== 'prescription' || snapshot.clinical !== true) throw Error('unsupported_prescription_identity');
  const consultation = person(identity.consultation, 'consultation_name_required');
  const responsible = person(identity.responsible, 'responsible_identity_required');
  responsible.license = text(identity.responsible.license, 'responsible_license_required');
  responsible.profile_version_id = identifier(identity.responsible.profile_version_id);
  consultation.attestation_id = identifier(identity.consultation.attestation_id);
  consultation.signed_at = instant(identity.consultation.signed_at);
  // Never substitute the preparer's or the responsible professional's signature.
  consultation.signature = identity.consultation.signature;
  const preparedBy = person(identity.prepared_by, 'preparer_identity_required');
  const names = new Map();
  for (const value of [consultation, preparedBy, responsible]) {
    if (names.has(value.user_id) && names.get(value.user_id) !== value.name) throw Error('prescription_identity_name_mismatch');
    names.set(value.user_id, value.name);
  }
  const preparedAt = instant(snapshot.prepared_at);
  const authorization = identity.authorization;
  if (!authorization || !['individual', 'standing'].includes(authorization.mode) || authorization.actor_id !== responsible.user_id) throw Error('responsible_authorization_required');
  const authorizedAt = instant(authorization.authorized_at);
  const reference = identifier(authorization.reference_id);
  if (Date.parse(consultation.signed_at) > Date.parse(preparedAt) || Date.parse(authorizedAt) > Date.parse(preparedAt)) throw Error('invalid_prescription_identity_time');
  if (typeof identity.controlled !== 'boolean') throw Error('prescription_classification_required');
  if (identity.controlled && (authorization.mode !== 'individual' || consultation.user_id !== responsible.user_id)) throw Error('controlled_responsible_only');
  let authorizationLabel;
  if (authorization.mode === 'standing') {
    if (authorization.document_type !== 'ordinary_prescription' || authorization.case_id !== snapshot.case_id || !uuid.test(authorization.case_id ?? '')) throw Error('standing_prescription_scope_required');
    const until = instant(authorization.valid_until);
    if (Date.parse(until) <= Date.parse(preparedAt) || Date.parse(until) <= Date.parse(authorizedAt)) throw Error('standing_authorization_expired_at_preparation');
    authorizationLabel = `Autorización previa de ${responsible.name}, otorgada el ${authorizedAt}, vigente hasta ${until}, para receta ordinaria del caso ${authorization.case_id}. Referencia: ${reference}. No consta revisión individual de este documento.`;
  } else {
    authorizationLabel = `Autorización individual de ${responsible.name}, registrada el ${authorizedAt}. Referencia: ${reference}.`;
  }
  return { consultation, responsible, preparedBy, authorizationLabel };
}
