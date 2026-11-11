// Cancela a assinatura do Premium do administrador que chamou. O Premium
// continua até o fim do período já pago (o banco devolve ao Gratuito
// depois, em `asaas_expire`).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { admin, asaas, AsaasError, caller, cors, json } from "../_shared/asaas.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { headers: cors });

  const user = await caller(request);
  if (!user) return json({ error: "not_signed_in" }, 401);

  const { data: current } = await admin
    .from("subscriptions")
    .select("asaas_subscription_id, status")
    .eq("profile_id", user.id)
    .maybeSingle();
  if (!current || current.status === "canceled") return json({ canceled: true });

  if (current.asaas_subscription_id) {
    try {
      await asaas("DELETE", `/subscriptions/${current.asaas_subscription_id}`);
    } catch (error) {
      // Já apagada no Asaas: segue e marca aqui.
      if (!(error instanceof AsaasError && error.status === 404)) {
        console.error("asaas-cancel", error instanceof AsaasError ? JSON.stringify(error.body) : error);
        return json({ error: "asaas" }, 502);
      }
    }
  }
  await admin.rpc("asaas_mark_canceled", { p_profile: user.id });
  return json({ canceled: true });
});
