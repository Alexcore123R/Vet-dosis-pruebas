import { betaAccess } from "../_shared/beta_access.ts";
import { createClient } from '@supabase/supabase-js';
import { renderForm } from '../_shared/forms_pdf.mjs';

// Service credentials are server-only Supabase secrets, never Flutter compile-time defines.
const url = Deno.env.get('SUPABASE_URL')!;
const publicKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info, x-vetdosis-build','Access-Control-Allow-Methods':'POST, OPTIONS'};
const base64 = (bytes: Uint8Array) => { let result=''; for(let i=0;i<bytes.length;i+=8192)result+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(result); };
const font = await Deno.readFile(new URL('./DejaVuSans.ttf',import.meta.url));
Deno.serve(async req => {
  if(req.method==='OPTIONS')return new Response(null,{headers:cors});
  const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
  if(req.method!=='POST')return reply({error:'method_not_allowed'},405);
  const authorization=req.headers.get('Authorization');
  if(!authorization?.startsWith('Bearer '))return reply({error:'authentication_required'},401);
  const user=createClient(url,publicKey,{global:{headers:{Authorization:authorization,"x-vetdosis-build":req.headers.get("x-vetdosis-build")??""}},auth:{persistSession:false}});
  const {data:identity,error:identityError}=await user.auth.getUser();
  if(identityError || !identity.user)return reply({error:'authentication_required'},401);
  if(!await betaAccess(user,false))return reply({error:"beta_access_denied"},403);
  try {
    const text=await req.text();if(text.length>500000)return reply({error:'request_too_large'},413);
    const input=JSON.parse(text);
    if(input.action==='template') {
      if(!await betaAccess(user,true,input.clinic))return reply({error:'beta_write_denied'},403);
      // This RPC validates schema locks and verifies admin/responsible-MVZ access.
      const {data,error}=await user.rpc('form_template_preview_check',{p_clinic:input.clinic,p_schema:input.schema,p_branding:input.branding??{}});
      if(error || data!==true)return reply({error:'template_access_or_schema_denied'},403);
      const {data:clinic,error:clinicError}=await user.from('clinics').select('name').eq('id',input.clinic).single();
      if(clinicError || !clinic)return reply({error:'clinic_identity_denied'},403);
      const rendered=await renderForm({schema:input.schema,branding:input.branding??{},clinic_name:clinic.name},font,{templatePreview:true});
      return reply({pdf:base64(rendered.bytes),hash:rendered.hash});
    }
    if(input.action==='rx') {
      if(!['prescription','report'].includes(input.kind)||typeof input.id!=='string')return reply({error:'invalid_rx_request'},400);
      const args={p_kind:input.kind,p_id:input.id};
      const {data:doc,error}=await user.rpc('rx_pdf_snapshot',args);
      if(error||!doc)return reply({error:'rx_access_denied'},403);
      const {data:existing,error:readError}=await user.rpc('rx_pdf_read',args);
      if(readError)return reply({error:'rx_access_denied'},403);if(existing)return reply(existing);
      if(doc.state!=='awaiting_review')return reply({error:'rx_not_prepared'},409);
      const table=input.kind==='prescription'?'prescriptions':'controlled_drug_reports';
      const {data:scope,error:scopeError}=await user.from(table).select('clinic_id').eq('id',input.id).single();
      if(scopeError || !scope || !await betaAccess(user,true,scope.clinic_id))return reply({error:'beta_write_denied'},403);
      const rendered=await renderForm(doc.snapshot,font);if(!rendered.mvzPng)return reply({error:'signature_required'},400);
      const server=createClient(url,serviceKey,{auth:{persistSession:false}});
      const {error:saveError}=await server.rpc('rx_pdf_register',{...args,p_revision:doc.revision,p_content_hash:doc.content_hash,p_pdf:base64(rendered.bytes),p_signature:base64(rendered.mvzPng)});
      if(saveError)return reply({error:'rx_pdf_conflict'},409);
      const {data:stored,error:lastError}=await user.rpc('rx_pdf_read',args);
      if(lastError||!stored)return reply({error:'rx_access_denied'},403);return reply(stored);
    }
    if(input.action==='document_preview' && typeof input.document==='string') {
      const args={p_id:input.document};
      const {data:doc,error}=await user.rpc('form_document_preview_snapshot',args);
      if(error||!doc)return reply({error:'document_access_denied'},403);
      const {data:existing,error:readError}=await user.rpc('form_preview_read',args);
      if(readError)return reply({error:'document_access_denied'},403);if(existing)return reply(existing);
      if(!await betaAccess(user,true,doc.clinic_id))return reply({error:'beta_write_denied'},403);
      const rendered=await renderForm(doc.snapshot,font,{tutorPreview:true});
      const server=createClient(url,serviceKey,{auth:{persistSession:false}});
      const {error:saveError}=await server.rpc('form_preview_register',{...args,p_revision:doc.revision,p_content_hash:doc.content_hash,p_pdf:base64(rendered.bytes)});
      if(saveError)return reply({error:'preview_revision_conflict'},409);
      const {data:stored,error:lastError}=await user.rpc('form_preview_read',args);
      if(lastError||!stored)return reply({error:'document_access_denied'},403);return reply(stored);
    }
    if(input.action!=='document' || typeof input.document!=='string')return reply({error:'invalid_action'},400);
    const {data:doc,error}=await user.rpc('form_document_snapshot',{p_id:input.document});
    if(error || !doc)return reply({error:'document_access_denied'},403);
    const {data:existing,error:readError}=await user.rpc('form_read_pdf',{p_id:doc.id});
    if(readError)return reply({error:'document_access_denied'},403);
    if(existing)return reply(existing);
    if(doc.state!=='awaiting_review')return reply({error:'document_not_prepared'},409);
    if(!await betaAccess(user,true,doc.clinic_id))return reply({error:'beta_write_denied'},403);
    const rendered=await renderForm(doc.snapshot,font);
    if ((!doc.snapshot.clinical && !rendered.tutorPng) || !rendered.mvzPng) return reply({error:'signature_images_required'},400);
    const server=createClient(url,serviceKey,{auth:{persistSession:false}});
    const {error:saveError}=await server.rpc('form_register_pdf',{
      p_id:doc.id,p_revision:doc.revision,p_content_hash:doc.content_hash,
      p_pdf:base64(rendered.bytes),p_tutor_png:rendered.tutorPng ? base64(rendered.tutorPng) : null,p_mvz_png:base64(rendered.mvzPng),
    });
    if(saveError)return reply({error:'pdf_revision_conflict'},409);
    // Recheck the current authenticated caller after render/registration, not only at start.
    const {data:stored,error:lastError}=await user.rpc('form_read_pdf',{p_id:doc.id});
    if(lastError || !stored)return reply({error:'document_access_denied'},403);
    return reply(stored);
  } catch { return reply({error:'pdf_generation_failed'},400); }
});
