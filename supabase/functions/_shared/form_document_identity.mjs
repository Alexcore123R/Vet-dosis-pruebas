// Presentation contract only. Server RPCs independently recheck authority.
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hash=/^[0-9a-f]{64}$/;
function id(v){if(typeof v!=='string'||!uuid.test(v))throw Error('invalid_form_identity');return v;}
function text(v){if(typeof v!=='string'||!v.trim()||v.length>200||/[\u0000-\u001f\u007f]/.test(v))throw Error('invalid_form_identity');return v.trim();}
function time(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(v)||!Number.isFinite(Date.parse(v))||new Date(v).toISOString().slice(0,19)!==v.slice(0,19))throw Error('invalid_form_identity_time');return v;}
function person(v){if(!v||typeof v!=='object'||Array.isArray(v))throw Error('invalid_form_identity');return {...v,user_id:id(v.user_id),name:text(v.name)};}
export function formDocumentIdentity(s,{tutorPreview=false}={}){
 if(s.form_identity===undefined&&s.form_identity_version===undefined){if(tutorPreview)throw Error('form_preview_identity_required');return null;}
 const clinical=['clinical_history','surgical_sheet','surgical_risk'].includes(s.schema?.type);
 if(s.form_identity_version!==1||!s.form_identity||!['general','surgery','euthanasia','early_discharge','hospital','clinical_history','surgical_sheet','surgical_risk'].includes(s.schema?.type)||s.clinical!==clinical||s.prescription_identity!==undefined||s.prescription_identity_version!==undefined)throw Error('unsupported_form_identity');
 if(s.form_preview!==tutorPreview||tutorPreview&&clinical)throw Error('form_preview_mode_mismatch');
 const i=s.form_identity,author=person(i.author),attention=person(i.attention),responsible=person(i.responsible),a=i.authorization;
 id(author.id);time(author.signed_at);id(attention.event_id);time(attention.observed_at);id(responsible.profile_version_id);text(responsible.license);
 if(clinical){id(attention.case_id);if(attention.scope!==(s.schema.type==='surgical_sheet'?'cirugia':'evaluacion'))throw Error('form_attention_scope_mismatch');}
 else if(attention.scope!=='consent_explanation'||attention.case_id!==null)throw Error('form_attention_scope_mismatch');
 const names=new Map();for(const p of [author,attention,responsible]){if(names.has(p.user_id)&&names.get(p.user_id)!==p.name)throw Error('form_identity_name_mismatch');names.set(p.user_id,p.name);}
 if(!a||a.mode!=='individual'||a.actor_id!==responsible.user_id||!hash.test(a.request_hash??''))throw Error('individual_form_authorization_required');
 id(a.reference_id);time(a.authorized_at);time(s.prepared_at);
 if([author.signed_at,attention.observed_at,a.authorized_at].some(t=>Date.parse(t)>Date.parse(s.prepared_at)))throw Error('invalid_form_identity_time');
 let tutor=null;
 if(clinical||tutorPreview){if(i.tutor!==null)throw Error('unexpected_tutor_signature');}
 else{tutor=i.tutor;if(!tutor||text(tutor.name)!==s.values?.signer_name||text(tutor.identification_number)!==s.values?.signer_id||!hash.test(tutor.preview_hash??''))throw Error('exact_tutor_identity_required');id(tutor.captured_by);id(tutor.reference_id);time(tutor.captured_at);if(Date.parse(tutor.captured_at)>Date.parse(s.prepared_at))throw Error('invalid_form_identity_time');}
 return {author,attention,responsible,tutor,authorizationLabel:`Autorización individual de ${responsible.name}, registrada el ${a.authorized_at}. Referencia: ${a.reference_id}.`,attentionLabel:clinical?'Realización de la atención':'Explicación del consentimiento'};
}
