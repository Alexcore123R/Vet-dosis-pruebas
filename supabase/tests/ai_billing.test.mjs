import test from 'node:test';
import assert from 'node:assert/strict';
import {providerRequest,providerText,listModels,buildMessages} from '../functions/_shared/ai_providers.mjs';
import {checkoutParameters,verifyStripeSignature,paidInvoice} from '../functions/_shared/subscription_billing.mjs';
test('Provider requests use fixed hosts; secrets are headers, OpenAI store is disabled',()=>{
 const messages=[{role:'system',content:'Rules'},{role:'user',content:'Synthetic note'}];
 for(const provider of ['openai','google','anthropic']){const r=providerRequest(provider,'fake-key','synthetic-model',messages);assert.equal(new URL(r.url).protocol,'https:');assert.ok(!r.url.includes('fake-key'));assert.ok(!JSON.stringify(r.body).includes('fake-key'));}
 assert.equal(providerRequest('openai','fake','model',messages).body.store,false);assert.throws(()=>providerRequest('http://attacker','fake','model',messages));
});
test('Text outputs normalize three providers and reject missing/excessive response',()=>{
 assert.equal(providerText('openai',{output:[{content:[{type:'output_text',text:'Fake text'}]}]}),'Fake text');
 assert.equal(providerText('anthropic',{content:[{type:'text',text:'Fake text'}]}),'Fake text');
 assert.equal(providerText('google',{candidates:[{content:{parts:[{text:'Hidden',thought:true},{text:'Fake text'}]}}]}),'Fake text');
 assert.throws(()=>providerText('openai',{}));assert.throws(()=>providerText('anthropic',{content:[{type:'text',text:'x'.repeat(30001)}]}));
});
test('Model listing is key-specific and excludes Gemini embeddings',async()=>{
 const models=await listModels('google','fake-key',async(url,options)=>{assert.equal(options.headers['x-goog-api-key'],'fake-key');return {ok:true,json:async()=>({models:[{name:'models/fake-chat',supportedGenerationMethods:['generateContent']},{name:'models/fake-embed',supportedGenerationMethods:['embedContent']}]})};});assert.deepEqual(models,[{id:'fake-chat',name:'models/fake-chat'}]);
});
test('Prompt marks chat excerpts as unverified and caps context',()=>{
 const result=buildMessages({context:[{body:'x'.repeat(30000)}],history:[{role:'user',body:'Synthetic question'}]});assert.ok(result[0].content.includes('No inventes'));assert.ok(result[1].content.length<15000);assert.equal(result.at(-1).content,'Synthetic question');
});
test('Checkout freezes MXN price and recurrence; return URL cannot mark paid',()=>{
 const p=checkoutParameters({id:'request',plan_code:'individual',period:'annual',price_cents:199000},'https://example.test');assert.equal(p.get('line_items[0][price_data][recurring][interval]'),'year');assert.equal(p.get('line_items[0][price_data][unit_amount]'),'199000');assert.equal(p.get('line_items[0][price_data][currency]'),'mxn');assert.ok(p.get('success_url').includes('review'));assert.throws(()=>checkoutParameters({plan_code:'individual',period:'monthly',price_cents:19900},'http://bad.test'));
});
test('Webhook rejects forged or stale signature and verifies raw body',async()=>{
 const secret='synthetic-only-secret',body='{"synthetic":true}',now=1700000000;const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);const sig=Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(`${now}.${body}`))),b=>b.toString(16).padStart(2,'0')).join('');
 await verifyStripeSignature(body,`t=${now},v1=${sig}`,secret,now);await assert.rejects(verifyStripeSignature(body+' ',`t=${now},v1=${sig}`,secret,now));await assert.rejects(verifyStripeSignature(body,`t=${now},v1=${sig}`,secret,now+301));
});
test('Only paid invoice with request binding activates benefits, not checkout completed',()=>{
 assert.equal(paidInvoice({type:'checkout.session.completed'}),null);assert.throws(()=>paidInvoice({type:'invoice.paid',data:{object:{status:'open'}}}));
 const event={id:'event',type:'invoice.paid',data:{object:{id:'invoice',status:'paid',amount_paid:19900,currency:'mxn',subscription:'subscription',subscription_details:{metadata:{vetdosis_request:'request'}},lines:{data:[{period:{start:1700000000,end:1702592000}}]}}}};const r=paidInvoice(event);assert.equal(r.p_request,'request');assert.equal(r.p_amount,19900);
});
test('Encrypted keys cannot be swapped between user/provider scopes or altered',async()=>{
 const {credentialMaster,sealCredential,openCredential}=await import('../functions/_shared/ai_crypto.mjs');const master=await credentialMaster(btoa('x'.repeat(32)));const sealed=await sealCredential('only-fake-api-key',master,'owner-a:openai');assert.ok(!sealed.ciphertext.includes('only-fake-api-key'));assert.equal(await openCredential(sealed,master,'owner-a:openai'),'only-fake-api-key');await assert.rejects(openCredential(sealed,master,'owner-b:openai'));const altered={...sealed,ciphertext:btoa('changed')};await assert.rejects(openCredential(altered,master,'owner-a:openai'));await assert.rejects(credentialMaster(''));await assert.rejects(credentialMaster(btoa('too-short')));
});
test('Gift duration is honored before the first paid subscription cycle',()=>{
 const r={id:'request',plan_code:'individual',period:'monthly',price_cents:19900,trial_until:new Date((1700000000+86400*30)*1000).toISOString()};const p=checkoutParameters(r,'https://example.test',1700000000);assert.equal(p.get('subscription_data[trial_end]'),String(1700000000+86400*30));assert.throws(()=>checkoutParameters({...r,trial_until:new Date((1700000000+1)*1000).toISOString()},'https://example.test',1700000000));assert.equal(paidInvoice({type:'invoice.paid',data:{object:{status:'paid',amount_paid:0}}}),null);
});

test('Z.AI uses fixed chat-completions host and returns text without reasoning',async()=>{
 const r=providerRequest('zai','synthetic-key','glm-4.5-flash',[{role:'user',content:'Synthetic'}]);assert.equal(r.url,'https://api.z.ai/api/paas/v4/chat/completions');assert.equal(r.headers.Authorization,'Bearer synthetic-key');assert.equal(r.body.thinking.type,'disabled');assert.ok(!JSON.stringify(r.body).includes('synthetic-key'));assert.equal(providerText('zai',{choices:[{message:{content:'Answer',reasoning_content:'Hidden'}}]}),'Answer');assert.deepEqual((await listModels('zai','fake')).map(m=>m.id),['glm-4.5-flash','glm-4.7-flash']);
});
test('Included help cannot include arbitrary prompts, chats or clinical records',async()=>{
 const {helpMessages,starterRuntime,limitedHelpRequest}=await import('../functions/_shared/starter_help.mjs');assert.throws(()=>helpMessages('patient-secret'));const m=helpMessages('payments');assert.equal(m.length,2);assert.ok(m[0].content.includes('No hagas recomendaciones clínicas'));assert.ok(m[1].content.includes('suscripción'));
 assert.equal(starterRuntime(()=>undefined),null);
 const env={STARTER_AI_API_KEY:'synthetic-only',STARTER_AI_FREE_TIER_REVIEWED:'true'};const cfg=starterRuntime(k=>env[k]);assert.equal(cfg.provider,'google');assert.equal(cfg.model,'gemini-2.5-flash');assert.equal(starterRuntime(k=>({...env,STARTER_AI_MODEL:'paid-arbitrary-model'})[k]),null);
 const r=limitedHelpRequest(providerRequest('google','fake','gemini-2.5-flash',m),'google');assert.equal(r.body.generationConfig.maxOutputTokens,1024);assert.equal(r.body.generationConfig.thinkingConfig.thinkingBudget,0);assert.equal(r.body.tools,undefined);
});
