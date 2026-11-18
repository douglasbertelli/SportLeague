// Recebe os eventos do Adapty (assinaturas das lojas, no app Android/iOS) e
// passa para `adapty_apply_event`, que guarda a assinatura e acerta o plano.
//
// Sem login do Supabase (verify_jwt desligado): no painel do Adapty
// (Integrations > Webhook) o "Authorization header value" precisa ser igual
// ao segredo ADAPTY_WEBHOOK_TOKEN. Ao salvar a integração, o Adapty manda um
// pedido de teste sem evento, que só recebe 200.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { admin } from "../_shared/asaas.ts";

function sameToken(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (request) => {
  const expected = Deno.env.get("ADAPTY_WEBHOOK_TOKEN") ?? "";
  const token = request.headers.get("authorization") ?? "";
  if (request.method !== "POST" || !expected || !sameToken(token, expected)) {
    return new Response("unauthorized", { status: 401 });
  }

  const event = await request.json().catch(() => null);
  if (!event || typeof event !== "object") {
    return new Response("bad request", { status: 400 });
  }
  // Pedido de teste do Adapty.
  if (!event.event_type) return Response.json({ received: true });

  const { data, error } = await admin.rpc("adapty_apply_event", { p: event });
  if (error) {
    // Erro nosso: responde 500 para o Adapty tentar de novo.
    console.error("adapty-webhook", event.event_type, error.message);
    return new Response("error", { status: 500 });
  }
  return Response.json({ received: true, result: data });
});
