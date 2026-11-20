// Recebe os eventos do Asaas (cobranças e assinaturas) e passa para
// `asaas_apply_event`, que atualiza assinatura, plano e pagamentos. Em
// estorno ou chargeback, também cancela a assinatura no Asaas.
//
// Sem login do Supabase (verify_jwt desligado): o Asaas manda o token do
// webhook no cabeçalho `asaas-access-token`, que precisa ser igual ao
// segredo ASAAS_WEBHOOK_TOKEN. O mesmo evento pode chegar mais de uma vez;
// o banco ignora repetidos.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { admin, asaas, AsaasError } from "../_shared/asaas.ts";

function sameToken(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (request) => {
  const expected = Deno.env.get("ASAAS_WEBHOOK_TOKEN") ?? "";
  const token = request.headers.get("asaas-access-token") ?? "";
  if (request.method !== "POST" || !expected || !sameToken(token, expected)) {
    return new Response("unauthorized", { status: 401 });
  }

  const event = await request.json().catch(() => null);
  if (!event) return new Response("bad request", { status: 400 });

  const { data, error } = await admin.rpc("asaas_apply_event", { p: event });
  if (error) {
    // Erro nosso: responde 500 para o Asaas tentar de novo.
    console.error("asaas-webhook", event.event, event.id, error.message);
    return new Response("error", { status: 500 });
  }

  // Estorno: o Premium já saiu no banco; cancela a assinatura no Asaas para
  // não cobrar de novo. Se o Asaas falhar agora, o asaas-sync tenta de novo
  // (fila de órfãs). Responde 200 de qualquer jeito: o evento já foi aplicado.
  const subscriptionId = event.payment?.subscription;
  if (data === "revoked" && subscriptionId) {
    try {
      await asaas("DELETE", `/subscriptions/${subscriptionId}`);
    } catch (e) {
      if (!(e instanceof AsaasError && e.status === 404)) {
        console.error("asaas-webhook revoke", subscriptionId, e instanceof AsaasError ? JSON.stringify(e.body) : e);
        await admin.rpc("asaas_put_orphan", { p_id: subscriptionId });
      }
    }
  }
  return Response.json({ received: true, result: data });
});
