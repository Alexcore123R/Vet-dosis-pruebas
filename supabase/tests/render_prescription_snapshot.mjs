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
 const text=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'});
 for(const value of ['Consulta realizada por: Synthetic person who attended','MVZ responsable:','Cédula profesional:','Autorización individual','Firma de quien realizó la consulta','Synthetic instructions'])assert.ok(text.includes(value),value);
 assert.ok(!text.includes('Firma del MVZ responsable'));
 assert.deepEqual(output.consultationPng,signatureImage(snapshot.prescription_identity.consultation.signature));
 assert.equal(snapshot.prescription_identity.authorization.actor_id,snapshot.prescription_identity.responsible.user_id);
 assert.notEqual(snapshot.prescription_identity.consultation.user_id,snapshot.prescription_identity.responsible.user_id);
 console.log('Server snapshot rendered successfully with the actual consultation signature and separate responsible identity.');
} finally { rmSync(directory,{recursive:true,force:true}); }
