import { PDFDocument, PDFName, PDFArray, PDFString, rgb } from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';
import { PNG } from 'pngjs';
import { prescriptionIdentity } from './prescription_identity.mjs';
import { formDocumentIdentity } from './form_document_identity.mjs';

export const rendererVersion = 'vetdosis-pdf-3';
export async function pdfHash(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(v => v.toString(16).padStart(2, '0')).join('');
}
export function signatureImage(points) {
  if (!Array.isArray(points) || points.length < 2 || points.length > 5000) throw Error('invalid_signature');
  const valid = points.filter(p => p !== null);
  if (valid.length < 2 || valid.some(p => !Array.isArray(p) || p.length !== 2 || p.some(v => typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > 1)) || !valid.some(p => Math.abs(p[0] - valid[0][0]) + Math.abs(p[1] - valid[0][1]) > .005)) throw Error('invalid_signature');
  const image = new PNG({ width: 600, height: 180 });
  image.data.fill(255);
  const pixel = (x,y) => { if (x < 0 || y < 0 || x >= 600 || y >= 180) return; const i = 4*(y*600+x); image.data[i]=image.data[i+1]=image.data[i+2]=0; };
  let drawn = false;
  for (let i=1;i<points.length;i++) {
    const a=points[i-1],b=points[i]; if (!a || !b) continue;
    const x0=Math.round(a[0]*599),y0=Math.round(a[1]*179),x1=Math.round(b[0]*599),y1=Math.round(b[1]*179);
    const steps=Math.max(Math.abs(x1-x0),Math.abs(y1-y0),1);
    for (let j=0;j<=steps;j++) {
      const x=Math.round(x0+(x1-x0)*j/steps),y=Math.round(y0+(y1-y0)*j/steps);
      for (let dx=-1;dx<=1;dx++) for (let dy=-1;dy<=1;dy++) pixel(x+dx,y+dy);
    }
    if (x0!==x1 || y0!==y1) drawn=true;
  }
  if (!drawn) throw Error('invalid_signature');
  return new Uint8Array(PNG.sync.write(image));
}
function imageBytes(text) {
  if (typeof text !== 'string' || text.length > 350000 || !/^[a-zA-Z0-9+/=\r\n]*$/.test(text)) throw Error('invalid_logo');
  const bytes=Uint8Array.from(atob(text.replace(/\s/g,'')),c=>c.charCodeAt(0));
  if (bytes.length<12 || bytes.length>250000) throw Error('invalid_logo');
  return bytes;
}
export async function renderForm(snapshot, fontBytes, { templatePreview = false, tutorPreview = false } = {}) {
  const schema=snapshot.schema, values=snapshot.values ?? {}, brand=snapshot.branding ?? {};
  if (!schema || !Array.isArray(schema.fields) || schema.fields.length>80 || !Array.isArray(schema.clauses) || schema.clauses.length>40 || typeof schema.title!=='string') throw Error('invalid_template');
  const identity = templatePreview ? null : prescriptionIdentity(snapshot);
  // Validate before generating bytes. A legacy signature cannot fill this slot.
  const formIdentity=templatePreview ? null : formDocumentIdentity(snapshot,{tutorPreview});
  const attentionPng=formIdentity ? signatureImage(formIdentity.attention.signature) : undefined;
  const authorPng=formIdentity ? signatureImage(formIdentity.author.signature) : undefined;
  const consultationPng = identity ? signatureImage(identity.consultation.signature) : undefined;
  const pdf=await PDFDocument.create(); pdf.registerFontkit(fontkit);
  const font=await pdf.embedFont(fontBytes,{subset:true});
  pdf.setTitle(schema.title);pdf.setProducer(rendererVersion);
  // All metadata derives from the prepared snapshot; no timestamp changes on finalization.
  if(snapshot.prepared_at) { pdf.setCreationDate(new Date(snapshot.prepared_at));pdf.setModificationDate(new Date(snapshot.prepared_at)); }
  let logo;
  if (brand.include_logo && brand.logo) {
    const bytes=imageBytes(brand.logo);
    if(bytes[0]===137 && bytes[1]===80) {
      // Decode before embedding to enforce dimensions, not just a MIME claim.
      if(bytes.length<24) throw Error('invalid_logo');
      const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
      const w=view.getUint32(16),h=view.getUint32(20);
      if(!w || !h || w>3000 || h>3000 || w*h>4000000) throw Error('logo_dimensions');
      logo=await pdf.embedPng(bytes);
    } else if(bytes[0]===255 && bytes[1]===216) {
      logo=await pdf.embedJpg(bytes);
      if(logo.width>3000 || logo.height>3000 || logo.width*logo.height>4000000) throw Error('logo_dimensions');
    } else throw Error('invalid_logo');
  }
  let page,y;
  const addPage=()=>{
    page=pdf.addPage([595.28,841.89]);y=790;
    if(snapshot.clinic_name){let label=Array.from(String(snapshot.clinic_name));while(label.length && font.widthOfTextAtSize(label.join(''),10)>390)label.pop();page.drawText(label.join(''),{x:44,y:775,size:10,font});}
    if(logo){const scale=Math.min(100/logo.width,50/logo.height);page.drawImage(logo,{x:448,y:774,width:logo.width*scale,height:logo.height*scale});}
    page.drawLine({start:{x:44,y:752},end:{x:551,y:752},thickness:1,color:rgb(.4,.4,.4)});
    page.drawText(`VetDosis Pro · ${templatePreview?'Vista previa de plantilla':snapshot.document_id}`,{x:44,y:25,size:8,font,color:rgb(.3,.3,.3)});
    y=736;
  };
  addPage();
  const line=(text,size=10)=>{if(y<60)addPage();page.drawText(text,{x:44,y,size,font});y-=size+5;};
  const paragraph=(text,size=10)=>{
    const cleaned=String(text??'').replace(/\r/g,'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'');
    if(cleaned.length>16000)throw Error('text_too_long');
    for(const segment of cleaned.split('\n')) {
      let current='';
      for(const word of segment.split(/\s+/)) {
        if(!word)continue;
        const candidate=current?current+' '+word:word;
        if(font.widthOfTextAtSize(candidate,size)<=502){current=candidate;continue;}
        if(current){line(current,size);current='';}
        if(font.widthOfTextAtSize(word,size)<=502){current=word;continue;}
        for(const ch of word){
          if(font.widthOfTextAtSize(current+ch,size)>502){line(current,size);current='';}
          current+=ch;
        }
      }
      line(current,size);
    }
  };
  if(snapshot.clinic_name)paragraph(snapshot.clinic_name,11);
  if(brand.header && brand.header!==snapshot.clinic_name)paragraph(brand.header,11);
  if(!brand.header && !snapshot.clinic_name)paragraph('[Membrete configurable]',11);
  paragraph(schema.title,15);
  if(templatePreview)paragraph('VISTA PREVIA DE PLANTILLA · SIN FIRMAR',11);
  if(tutorPreview)paragraph('VISTA PREVIA PARA EL TUTOR · PENDIENTE DE SU FIRMA',11);
  if(formIdentity){
    paragraph(`Documento elaborado por: ${formIdentity.author.name}`,10);
    paragraph(`${formIdentity.attentionLabel}: ${formIdentity.attention.name}`,11);
    paragraph(`MVZ responsable: ${formIdentity.responsible.name}`,11);
    paragraph(`Cédula profesional: ${formIdentity.responsible.license}`,10);
    paragraph(formIdentity.authorizationLabel,9);
  }
  paragraph(`Versión de plantilla: ${snapshot.template_version??'propuesta'} · Contenido de referencia revisable por la clínica.`,9);
  if(snapshot.prepared_at)paragraph(`Firmas capturadas para revisión (servidor UTC): ${snapshot.prepared_at}`,9);
  if(identity) {
    paragraph(`MVZ responsable: ${identity.responsible.name}`,11);
    paragraph(`Cédula profesional: ${identity.responsible.license}`,10);
    paragraph(`Consulta realizada por: ${identity.consultation.name}`,11);
    if(identity.preparedBy.user_id !== identity.consultation.user_id)paragraph(`Documento elaborado por: ${identity.preparedBy.name}`,10);
    paragraph(identity.authorizationLabel,9);
  }
  for(const f of schema.fields) {
    if(f.type==='signature')continue;
    paragraph(f.label,11);
    let value=values[f.id];
    if(f.id==='patient')value=snapshot.patient ? `${snapshot.patient.name} · ${snapshot.patient.species} · ${snapshot.patient.breed??''} · ${snapshot.patient.sex??''}` : '[Paciente vinculado]';
    if(f.type==='person' && snapshot.staff_labels?.[value])value=snapshot.staff_labels[value];
    if(f.id==='owner')value=snapshot.owner?.name??'[Propietario vinculado]';
    if(f.type==='table') {
      paragraph((f.columns??[]).join(' | '),9);
      for(const row of value??[])paragraph(row.join(' | '),9);
    } else {
      if(f.id==='privacy_url' && typeof value==='string' && value.startsWith('https://')) {
        if(y<60)addPage();
        const annotation=pdf.context.register(pdf.context.obj({Type:'Annot',Subtype:'Link',Rect:[44,y-2,551,y+12],Border:[0,0,0],A:{S:'URI',URI:PDFString.of(value)}}));
        let annotations=page.node.lookupMaybe(PDFName.of('Annots'),PDFArray);
        if(!annotations){annotations=pdf.context.obj([]);page.node.set(PDFName.of('Annots'),annotations);}
        annotations.push(annotation);
      }
      paragraph(value===undefined?'[Por completar]':Array.isArray(value)?value.join(', '):typeof value==='boolean'?(value?'Sí':'No'):value);
    }
    y-=5;
  }
  if(snapshot.professional_profile_version && snapshot.professional_issuer_profile){paragraph(`Titular de los datos: ${snapshot.professional_profile_version.name} · Emisor responsable: ${snapshot.professional_issuer_profile.name}`,9);}
  for(const clause of schema.clauses){paragraph(clause.text);y-=7;}
  let tutorPng,mvzPng;
  if(!templatePreview) {
    if(!snapshot.clinical && !tutorPreview)tutorPng=signatureImage(formIdentity ? formIdentity.tutor.signature : snapshot.tutor_signature);
    // mvzPng is the existing artifact transport field, not a claim about the
    // signer's profession. New prescription snapshots bind it to consultation.
    mvzPng=attentionPng ?? consultationPng ?? signatureImage(snapshot.mvz_signature);
    const signatures=formIdentity ? [
      ['Firma de elaboración',formIdentity.author.name,null,authorPng],
      [`Firma · ${formIdentity.attentionLabel}`,formIdentity.attention.name,null,attentionPng],
      ...(!snapshot.clinical&&!tutorPreview ? [['Firma del tutor',formIdentity.tutor.name,formIdentity.tutor.identification_number,tutorPng]] : []),
    ] : identity ? [
      ['Firma de quien realizó la consulta',identity.consultation.name,null,consultationPng],
    ] : [
      ...(!snapshot.clinical ? [['Firma del tutor',values.signer_name,values.signer_id,tutorPng]] : []),
      [snapshot.signature_label??'Firma del MVZ responsable',snapshot.professional_issuer_profile && snapshot.signature_label==='Firma del MVZ responsable' ? snapshot.professional_issuer_profile.name : values.mvz_name,snapshot.professional_issuer_profile && snapshot.signature_label==='Firma del MVZ responsable' ? snapshot.professional_issuer_profile.license : values.mvz_license,mvzPng],
    ];
    for(const [title,name,number,png] of signatures) {
      if(y<190)addPage();paragraph(`${title}: ${name}`);
      if(number !== null)paragraph(`Identificación / cédula: ${number}`);
      const img=await pdf.embedPng(png);page.drawImage(img,{x:44,y:y-65,width:216,height:65});y-=90;
    }
    if(tutorPreview)paragraph('El tutor debe revisar este contenido y firmar personalmente. Esta vista previa no es un documento emitido.',10);
    paragraph('La confirmación final y su hora del servidor constan en el registro de VetDosis Pro. El archivo se conserva sin regeneración tras la confirmación.',9);
    if(schema.type==='euthanasia')paragraph('La constatación de muerte se documenta posteriormente en una entrada vinculada; no modifica este consentimiento.',9);
  }
  const bytes=await pdf.save();if(bytes.length>2097152)throw Error('pdf_too_large');
  return {bytes,hash:await pdfHash(bytes),tutorPng,mvzPng,consultationPng,authorPng,attentionPng};
}
