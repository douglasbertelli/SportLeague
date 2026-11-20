// Todo dia (pg_cron `asaas-sync`): acerta no Asaas o valor das assinaturas
// cujo número de times ativos mudou, inclusive as cobranças já geradas e
// ainda não pagas, apaga as assinaturas que nunca foram pagas, cancela as
// que estão há 30 dias sem pagar e as de contas apagadas.
//
// Também consulta o saldo, para a chave da API não ficar parada.
//
// Não exige login: só deixa o Asaas igual ao banco, então chamar de novo
// não faz mal. Uma etapa que falha no banco fica no log e na resposta
// (`errors`), e as outras continuam.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { admin, asaas, AsaasError, premiumDescription } from "../_shared/asaas.ts";

type Change = {
  profile_id: string;
  asaas_subscription_id: string;
  teams: number;
  value_cents: number;
};

type Row = { profile_id: string; asaas_subscription_id: string };

const describe = (error: unknown) =>
  error instanceof AsaasError ? JSON.stringify(error.body) : String(error);

Deno.serve(async () => {
  let updated = 0;
  let canceled = 0;
  const errors: string[] = [];

  /** Chama uma função do banco; se falhar, registra e devolve null. */
  async function rpc<T>(name: string, args?: Record<string, unknown>) {
    const { data, error } = await admin.rpc(name, args);
    if (error) {
      console.error("asaas-sync rpc", name, error.message);
      errors.push(`${name}: ${error.message}`);
      return null;
    }
    return data as T;
  }

  // Uma consulta simples todo dia: mantém a chave da API em uso (o Asaas
  // desabilita chaves paradas há 3 meses) e avisa logo se ela parou de
  // funcionar.
  try {
    await asaas("GET", "/finance/balance");
  } catch (e) {
    console.error("asaas-sync key", describe(e));
    errors.push(`asaas: ${describe(e)}`);
  }

  const changes = await rpc<Change[]>("asaas_value_changes");
  for (const c of changes ?? []) {
    try {
      await asaas("PUT", `/subscriptions/${c.asaas_subscription_id}`, {
        value: c.value_cents / 100,
        description: premiumDescription,
        updatePendingPayments: true,
      });
      await rpc("asaas_set_value", {
        p_profile: c.profile_id,
        p_teams: c.teams,
        p_value_cents: c.value_cents,
      });
      updated++;
    } catch (e) {
      console.error("asaas-sync value", c.asaas_subscription_id, describe(e));
    }
  }

  // Nunca pagas: apaga no Asaas para não gerar cobrança todo mês.
  let stale = 0;
  for (const s of (await rpc<Row[]>("asaas_stale_subscriptions")) ?? []) {
    try {
      await asaas("DELETE", `/subscriptions/${s.asaas_subscription_id}`);
    } catch (e) {
      if (!(e instanceof AsaasError && e.status === 404)) {
        console.error("asaas-sync stale", s.asaas_subscription_id, describe(e));
        continue;
      }
    }
    await rpc("asaas_clear_subscription", {
      p_profile: s.profile_id,
      p_id: s.asaas_subscription_id,
    });
    stale++;
  }

  // 30 dias sem pagar: cancela no Asaas (a conta já voltou ao Gratuito).
  let overdue = 0;
  for (const s of (await rpc<Row[]>("asaas_overdue_subscriptions")) ?? []) {
    try {
      await asaas("DELETE", `/subscriptions/${s.asaas_subscription_id}`);
    } catch (e) {
      if (!(e instanceof AsaasError && e.status === 404)) {
        console.error("asaas-sync overdue", s.asaas_subscription_id, describe(e));
        continue;
      }
    }
    await rpc("asaas_cancel_overdue", {
      p_profile: s.profile_id,
      p_id: s.asaas_subscription_id,
    });
    overdue++;
  }

  // Contas apagadas e cancelamentos que falharam no webhook.
  for (const id of (await rpc<string[]>("asaas_take_orphans")) ?? []) {
    try {
      await asaas("DELETE", `/subscriptions/${id}`);
      canceled++;
    } catch (e) {
      if (e instanceof AsaasError && e.status === 404) continue;
      console.error("asaas-sync orphan", id, describe(e));
      await rpc("asaas_put_orphan", { p_id: id });
    }
  }

  return Response.json(
    { updated, stale, overdue, canceled, errors },
    { status: errors.length ? 500 : 200 },
  );
});
