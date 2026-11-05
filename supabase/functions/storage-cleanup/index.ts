// Apaga do Storage as imagens que nenhuma tabela usa mais (órfãs), criadas
// há mais de um dia. Chamada todo dia pelo pg_cron (`storage-cleanup`).
//
// A lista vem de `storage_orphans` (só a service role consulta) e os
// arquivos saem pela API do Storage, que apaga o arquivo de verdade.
// Não exige login: só apaga o que já não é usado, então chamar de novo não
// faz mal.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/** Quantos arquivos por pedido de remoção. */
const BATCH = 100;

Deno.serve(async () => {
  const { data, error } = await supabase.rpc("storage_orphans");
  if (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }

  const byBucket = new Map<string, string[]>();
  for (const { bucket_id, name } of data as { bucket_id: string; name: string }[]) {
    byBucket.set(bucket_id, [...(byBucket.get(bucket_id) ?? []), name]);
  }

  const removed: Record<string, number> = {};
  for (const [bucket, names] of byBucket) {
    removed[bucket] = 0;
    for (let i = 0; i < names.length; i += BATCH) {
      const batch = names.slice(i, i + BATCH);
      const { data: gone, error: removeError } = await supabase.storage
        .from(bucket)
        .remove(batch);
      if (removeError) {
        console.error("storage-cleanup", bucket, removeError.message);
        continue;
      }
      removed[bucket] += gone?.length ?? 0;
    }
  }
  return Response.json({ removed });
});
