// Integration check: render the actual server-generated, synthetic snapshot.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { renderForm, signatureImage } from '../functions/_shared/forms_pdf.mjs';
const snapshot=JSON.parse(readFileSync(process.argv[2],'utf8'));
const font=readFileSync(new URL('../functions/forms-pdf/DejaVuSans.ttf',import.meta.url));
const output=await renderForm(snapshot,font);
const directory=mkdtempSync(join(tmpdir(),'vetdosis-rx-snapshot-'));
try {
 const path=join(directory,'synthetic.pdf');writeFileSync(path,output.bytes);
 const text=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'}).replace(/\s+/g,' ');
 const standing=snapshot.prescription_identity.authorization.mode==='standing';
 const expectedName=standing?'Synthetic participant':'Synthetic person who attended';
 for(const value of [`Consulta realizada por: ${expectedName}`,'MVZ responsable:','Cédula profesional:',standing?'Autorización previa':'Autorización individual','Firma de quien realizó la consulta',standing?'Synthetic standing':'Synthetic instructions'])assert.ok(text.includes(value),value);
 if(standing){assert.ok(text.includes('No consta revisión individual'));assert.ok(!text.includes('Autorización individual'));}
 assert.ok(!text.includes('Firma del MVZ responsable'));
 assert.deepEqual(output.consultationPng,signatureImage(snapshot.prescription_identity.consultation.signature));
 assert.equal(snapshot.prescription_identity.authorization.actor_id,snapshot.prescription_identity.responsible.user_id);
 assert.notEqual(snapshot.prescription_identity.consultation.user_id,snapshot.prescription_identity.responsible.user_id);
 console.log('Server snapshot rendered successfully with the actual consultation signature and separate responsible identity.');
} finally { rmSync(directory,{recursive:true,force:true}); }
