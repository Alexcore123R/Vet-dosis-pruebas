import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {renderForm,signatureImage} from '../functions/_shared/forms_pdf.mjs';
const s=JSON.parse(readFileSync(process.argv[2],'utf8'));
const font=readFileSync(new URL('../functions/forms-pdf/DejaVuSans.ttf',import.meta.url));
const d=mkdtempSync(join(tmpdir(),'vetdosis-form-flow-'));
try{
 const r=await renderForm(s,font);const path=join(d,'form.pdf');writeFileSync(path,r.bytes);
 const text=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'}).replace(/\s+/g,' ');
 for(const value of ['Documento elaborado por: Synthetic participant','Explicación del consentimiento: Synthetic presenter','MVZ responsable:','Autorización individual','Firma del tutor: Synthetic tutor'])assert.ok(text.includes(value),value);
 assert.ok(!text.includes('Firma del MVZ responsable'));assert.deepEqual(r.attentionPng,signatureImage(s.form_identity.attention.signature));assert.deepEqual(r.authorPng,signatureImage(s.form_identity.author.signature));assert.deepEqual(r.tutorPng,signatureImage(s.form_identity.tutor.signature));
 assert.notDeepEqual(r.attentionPng,r.authorPng);
 const preview=structuredClone(s);preview.form_preview=true;preview.form_identity.tutor=null;
 const pr=await renderForm(preview,font,{tutorPreview:true});assert.equal(pr.tutorPng,undefined);writeFileSync(path,pr.bytes);
 assert.ok(execFileSync('pdftotext',[path,'-'],{encoding:'utf8'}).includes('PENDIENTE DE SU FIRMA'));
 for(const mutate of [v=>delete v.form_identity.attention.signature,v=>v.form_identity_version=2,v=>v.form_identity.tutor=null,v=>v.form_identity.authorization.mode='standing',v=>v.form_identity.attention.scope='cirugia']){
  const bad=structuredClone(s);mutate(bad);await assert.rejects(renderForm(bad,font));
 }
 await assert.rejects(renderForm(preview,font),/form_preview_mode_mismatch/);
 const clinical=JSON.parse(readFileSync(process.argv[3],'utf8'));const cr=await renderForm(clinical,font);assert.equal(cr.tutorPng,undefined);writeFileSync(path,cr.bytes);
 const ct=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'}).replace(/\s+/g,' ');
 assert.ok(ct.includes('Realización de la atención: Synthetic presenter'));assert.ok(!ct.includes('Firma del tutor'));assert.ok(!('weight' in clinical.values));assert.ok(!('temperature' in clinical.values));
 console.log('Actual PostgreSQL snapshot rendered with three separate signatures; unknown identity, borrowed fallback and premature issuance rejected.');
} finally{rmSync(d,{recursive:true,force:true});}
