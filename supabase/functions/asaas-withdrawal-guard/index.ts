// Validação de saque do Asaas (Integrações → Segurança → Validação de saque
// via Webhook). O SportLeague só recebe pagamentos: nenhum saque é feito
// pela API. Então toda transferência, Pix ou pagamento de conta pedido pela
// API é recusado. Se a chave da API vazar, ninguém tira dinheiro com ela.
//
// Os saques feitos pelo site ou app do Asaas não passam por aqui (desde
// que "Validar também saques via interface" fique desmarcado).
//
// Sem login do Supabase (verify_jwt desligado) e sem token: a resposta é
// sempre a mesma, recusar.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(async (request) => {
  const body = await request.json().catch(() => null);
  console.warn("asaas-withdrawal-guard: saque pela API recusado", body?.type);
  return Response.json({
    status: "REFUSED",
    refuseReason: "Saques pela API não são permitidos nesta conta.",
  });
});
