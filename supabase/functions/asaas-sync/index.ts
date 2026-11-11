// Todo dia (pg_cron `asaas-sync`): acerta no Asaas o valor das assinaturas
// cujo número de times ativos mudou, inclusive as cobranças já geradas e
// ainda não pagas, e cancela as assinaturas de contas apagadas.
//
// Não exige login: só deixa o Asaas igual ao banco, então chamar de novo
// não faz mal.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { admin, asaas, AsaasError } from "../_shared/asaas.ts";

type Change = {
  profile_id: string;
  asaas_subscription_id: string;
  teams: number;
  value_cents: number;
};

const describe = (error: unknown) =>
  error instanceof AsaasError ? JSON.stringify(error.body) : String(error);

Deno.serve(async () => {
  let updated = 0;
  let canceled = 0;

  const { data: changes, error } = await admin.rpc("asaas_value_changes");
  if (error) return Response.json({ error: error.message }, { status: 500 });

  for (const c of (changes ?? []) as Change[]) {
    try {
      await asaas("PUT", `/subscriptions/${c.asaas_subscription_id}`, {
        value: c.value_cents / 100,
        description: c.teams > 1 ? `Premium com ${c.teams} times` : "Premium com 1 time",
        updatePendingPayments: true,
      });
      await admin.rpc("asaas_set_value", {
        p_profile: c.profile_id,
        p_teams: c.teams,
        p_value_cents: c.value_cents,
      });
      updated++;
    } catch (e) {
      console.error("asaas-sync value", c.asaas_subscription_id, describe(e));
    }
  }

  const { data: orphans } = await admin.rpc("asaas_take_orphans");
  for (const id of (orphans ?? []) as string[]) {
    try {
      await asaas("DELETE", `/subscriptions/${id}`);
      canceled++;
    } catch (e) {
      if (e instanceof AsaasError && e.status === 404) continue;
      console.error("asaas-sync orphan", id, describe(e));
      await admin.rpc("asaas_put_orphan", { p_id: id });
    }
  }

  return Response.json({ updated, canceled });
});
