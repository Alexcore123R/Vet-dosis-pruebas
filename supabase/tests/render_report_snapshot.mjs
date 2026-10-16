// Actual SQL snapshot, entirely synthetic records. No normative assertions.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {renderForm, signatureImage} from '../functions/_shared/forms_pdf.mjs';
const snapshot=JSON.parse(readFileSync(process.argv[2],'utf8'));
const font=readFileSync(new URL('../functions/forms-pdf/DejaVuSans.ttf',import.meta.url));
const rendered=await renderForm(snapshot,font);
const directory=mkdtempSync(join(tmpdir(),'vetdosis-report-snapshot-'));
try {
 const path=join(directory,'synthetic.pdf');writeFileSync(path,rendered.bytes);
 const text=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'}).replace(/\s+/g,' ');
 for(const value of ['basado en Anexo 5, no oficial','INCOMPLETO','Synthetic report product',snapshot.profile.name,snapshot.profile.license])assert.ok(text.includes(value),value);
 assert.equal(snapshot.entries.length,1);
 assert.equal(snapshot.pending_ids.length,2);
 assert.deepEqual(rendered.mvzPng,signatureImage(snapshot.mvz_signature));
 assert.equal(rendered.tutorPng,undefined);
 console.log('Server report snapshot rendered with one validated row, two pending records, own signature and no official claim.');
} finally {rmSync(directory,{recursive:true,force:true});}
