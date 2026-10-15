import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {PDFDocument} from 'pdf-lib';
import {PNG} from 'pngjs';
import {renderForm,pdfHash,signatureImage} from '../functions/_shared/forms_pdf.mjs';
const font=readFileSync(new URL('../functions/forms-pdf/DejaVuSans.ttf',import.meta.url));
const catalog=JSON.parse(readFileSync(new URL('../../assets/clinical/forms.reference.v1.json',import.meta.url)));
const schema=catalog.templates.find(t=>t.type==='euthanasia');
function snapshot(){return {schema,document_id:'SYNTHETIC-ONLY',template_version:1,clinic_name:'Clínica ficticia',prepared_at:'2026-10-07T00:00:00Z',patient:{name:'Paciente sintético',species:'Especie ficticia',breed:'',sex:'sin especificar'},owner:{name:'Tutor sintético'},values:{mvz_name:'MVZ ficticio',mvz_license:'CEDULA-FICTICIA',signer_name:'Tutor sintético',signer_id:'NUMERO-FICTICIO',privacy_url:'https://example.test/privacidad',procedure:'Procedimiento ficticio',information:'Información de prueba',clinical_reason:'Motivo clínico sintético',prior_opinion:'Concepto previo ficticio',method:'Método sin indicaciones clínicas',body_disposition:'Acuerdo ficticio',cost:'Costo ficticio'},branding:{header:'Membrete propio de clínica ficticia',include_logo:false},tutor_signature:[[.1,.2],[.3,.5],[.7,.6],null],mvz_signature:[[.2,.3],[.6,.5],null]};}
test('real PDF contains clinical fields, signatures, unicode, and no source branding',async()=>{
 const input=snapshot(),r=await renderForm(input,font);
 assert.equal(r.hash,await pdfHash(r.bytes));assert.ok(r.bytes.length<2097152);
 const pdf=await PDFDocument.load(r.bytes);assert.ok(pdf.getPageCount()>=2);
 assert.equal(PNG.sync.read(Buffer.from(r.tutorPng)).width,600);
 const path='/tmp/vetdosis-forms-synthetic.pdf';writeFileSync(path,r.bytes);
 const text=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'});
 for(const value of ['Motivo clínico','Concepto previo','Método propuesto','Disposición del cuerpo','Costo','NUMERO-FICTICIO','constatación','Membrete propio'])assert.ok(text.includes(value),value);
 assert.ok(!text.includes('Ramón Padilla'));assert.ok(!text.includes('irrevocable'));
 // A finalizer must retain bytes, not re-render them after changing status.
 const stored=new Uint8Array(r.bytes);input.state='signed';assert.equal(await pdfHash(stored),r.hash);
});
test('long text and table rows paginate without dropping content',async()=>{
 const s=snapshot();s.schema=structuredClone(schema);s.schema.fields.push({id:'extra_table',label:'Tabla de prueba',type:'table',columns:['Dato','Valor']});
 s.values.information='Texto revisado áéíóú '.repeat(400);s.values.extra_table=Array.from({length:40},(_,i)=>[`Fila ${i}`,`Valor ${i}`]);
 const r=await renderForm(s,font);assert.ok((await PDFDocument.load(r.bytes)).getPageCount()>2);
 writeFileSync('/tmp/vetdosis-forms-long.pdf',r.bytes);
 const text=execFileSync('pdftotext',['/tmp/vetdosis-forms-long.pdf','-'],{encoding:'utf8'});assert.ok(text.includes('Fila 39'));assert.ok(text.includes('Firma del tutor'));
});
test('logo is embedded with bounded dimensions; invalid image is rejected',async()=>{
 const s=snapshot();const logo=new PNG({width:30,height:10});logo.data.fill(255);s.branding.logo=PNG.sync.write(logo).toString('base64');s.branding.include_logo=true;
 const r=await renderForm(s,font);assert.ok(r.bytes.length>0);
 s.branding.logo=Buffer.from('not an image').toString('base64');await assert.rejects(renderForm(s,font),/invalid_logo/);
});
test('blank/disconnected point signatures do not become valid PNGs',()=>{
 assert.throws(()=>signatureImage([[.1,.1],[.1,.1]]),/invalid_signature/);
 assert.throws(()=>signatureImage([[.1,.1],null,[.7,.7]]),/invalid_signature/);
 assert.throws(()=>signatureImage([[2,.1],[.3,.4]]),/invalid_signature/);
});
test('clinical sheet has only responsible MVZ signature and preserves clinical data',async()=>{
 const catalog=JSON.parse(readFileSync(new URL('../../assets/clinical/forms.clinical.v1.json',import.meta.url)));
 const s=snapshot();s.schema=catalog.templates.find(t=>t.type==='surgical_sheet');s.clinical=true;delete s.tutor_signature;
 s.values={mvz_name:'MVZ sintético',mvz_license:'FICTICIA',clinical_date:'2026-10-07',reason:'Caso ficticio',procedure:'Procedimiento ficticio',surgeon_id:'SURGEON',anesthetist_id:'ANESTHETIST',asa:'Valoración manual',ekg:'Hallazgo manual',fc:'123.50'};
 s.staff_labels={SURGEON:'Cirujano sintético',ANESTHETIST:'Anestesista sintético'};
 const r=await renderForm(s,font);assert.equal(r.tutorPng,undefined);assert.ok(r.mvzPng);
 writeFileSync('/tmp/vetdosis-clinical-synthetic.pdf',r.bytes);
 const text=execFileSync('pdftotext',['/tmp/vetdosis-clinical-synthetic.pdf','-'],{encoding:'utf8'});
 for(const label of ['Cirujano sintético','Anestesista sintético','Valoración manual','Hallazgo manual','123.50','Firma del MVZ'])assert.ok(text.includes(label),label);
 assert.ok(!text.includes('Firma del tutor'));assert.ok(!text.includes('NUMERO-FICTICIO'));
});
test('prescription preserves captured folio and distinguishes shared identity from own issuer signature',async()=>{
 const s=snapshot();s.clinical=true;s.signature_label='Firma propia de quien emite';delete s.tutor_signature;
 s.schema={type:'prescription',title:'Receta médica veterinaria',fields:[{id:'holder',label:'Titular de los datos',type:'text'},{id:'issuer',label:'Emisor',type:'text'},{id:'folio',label:'Folio capturado (no generado)',type:'text'},{id:'products',label:'Indicaciones manuales',type:'table',columns:['Producto','Cantidad','Vía','Intervalo']}],clauses:[]};
 s.values={holder:'MVZ titular ficticio · Cédula ficticia',issuer:'Auxiliar emisor ficticio',folio:'FOLIO-CAPTURADO-FICTICIO',products:[['Producto ficticio','0.125 ml','Vía ficticia','Intervalo ficticio']],mvz_name:'Auxiliar emisor ficticio',mvz_license:''};
 const r=await renderForm(s,font);writeFileSync('/tmp/vetdosis-prescription-synthetic.pdf',r.bytes);
 const text=execFileSync('pdftotext',['/tmp/vetdosis-prescription-synthetic.pdf','-'],{encoding:'utf8'});
 for(const value of ['FOLIO-CAPTURADO-FICTICIO','MVZ titular ficticio','Auxiliar emisor ficticio','0.125 ml','Firma propia de quien emite'])assert.ok(text.includes(value),value);
 assert.ok(!text.includes('SENASICA-REC-'));assert.equal(r.tutorPng,undefined);
});
test('reference control report prints incomplete status and contains only its frozen validated rows',async()=>{
 const s=snapshot();s.clinical=true;delete s.tutor_signature;
 s.schema={type:'controlled_report',title:'Reporte de referencia · no oficial',fields:[{id:'state',label:'Estado al corte',type:'text'},{id:'pending',label:'Pendientes',type:'text'},{id:'records',label:'Aplicaciones validadas',type:'table',columns:['Producto','Cantidad','Validó']}],clauses:[]};
 s.values={state:'INCOMPLETO',pending:'2 registros pendientes',records:[['Producto sintético validado','1.250 ml','MVZ sintético']],mvz_name:'MVZ sintético',mvz_license:'FICTICIA'};
 const r=await renderForm(s,font);writeFileSync('/tmp/vetdosis-report-synthetic.pdf',r.bytes);
 const text=execFileSync('pdftotext',['/tmp/vetdosis-report-synthetic.pdf','-'],{encoding:'utf8'});
 for(const value of ['no oficial','INCOMPLETO','2 registros pendientes','1.250 ml'])assert.ok(text.includes(value),value);
});

test('canonical clinic name remains on every page with a custom contact letterhead',async()=>{
 const s=snapshot();s.branding.header='Contacto de prueba sin nombre de clínica';s.values.information='Texto de prueba '.repeat(500);
 const rendered=await renderForm(s,font);
 const path='/tmp/vetdosis-canonical-brand.pdf';writeFileSync(path,rendered.bytes);
 const pages=execFileSync('pdftotext',[path,'-'],{encoding:'utf8'}).split('\f').filter(p=>p.trim());
 assert.ok(pages.length>1);for(const page of pages)assert.ok(page.includes(s.clinic_name));
 const pdf=await PDFDocument.load(rendered.bytes,{updateMetadata:false});assert.equal(pdf.getProducer(),'vetdosis-pdf-2');
});
